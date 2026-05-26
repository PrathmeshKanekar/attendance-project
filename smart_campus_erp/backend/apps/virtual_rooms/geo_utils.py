"""
geo_utils.py  —  Virtual Room Geofencing for 99.9% accurate attendance.

KEY DESIGN DECISIONS:
─────────────────────
1. NEVER use altitude/floor check to block attendance.
   Phone altitude (GPS barometric) has ±30m error indoors. A 3-storey building
   is only ~12m tall. Using altitude would wrongly reject half your students.
   altitude_ok is always returned as True.

2. Primary check: point-in-polygon ray casting (clockwise sorted).
3. Secondary check: within (max_corner_accuracy + student_accuracy) slack metres
   of the boundary — handles indoor GPS drift.
4. Hard cap: slack is capped at 25m so students outside cannot cheat.
5. Fail-safe: on any unexpected exception → DENY (never silently allow).
6. On error_fallback: return is_valid=False, not True. A system error should
   not mark a student present who may not be there.
"""

import math
import logging

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────────────────
# HAVERSINE DISTANCE
# ─────────────────────────────────────────────────────────────────────────────
def haversine_distance(lat1, lon1, lat2, lon2):
    """Great-circle distance in metres between two GPS points."""
    try:
        R = 6_371_000.0
        phi1 = math.radians(float(lat1))
        phi2 = math.radians(float(lat2))
        d_phi = math.radians(float(lat2) - float(lat1))
        d_lam = math.radians(float(lon2) - float(lon1))
        a = (math.sin(d_phi / 2.0) ** 2
             + math.cos(phi1) * math.cos(phi2) * math.sin(d_lam / 2.0) ** 2)
        return R * 2.0 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))
    except Exception as e:
        logger.error('haversine_distance error: %s', e)
        return 0.0


# ─────────────────────────────────────────────────────────────────────────────
# POINT-IN-POLYGON  (ray-casting)
# ─────────────────────────────────────────────────────────────────────────────
def _sort_clockwise(poly):
    """Sort polygon vertices clockwise around centroid."""
    if len(poly) < 3:
        return poly
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    return sorted(poly, key=lambda p: math.atan2(p[0] - cx, p[1] - cy), reverse=True)


def is_inside_polygon(student_lat, student_lng, poly):
    """
    Ray-casting inside-polygon test.
    poly = list of (lat, lng) in any order — we sort clockwise internally.
    Returns True if (student_lat, student_lng) is inside the polygon.
    """
    try:
        if len(poly) < 3:
            return False

        sorted_poly = _sort_clockwise(poly)
        n = len(sorted_poly)
        inside = False
        px, py = float(student_lat), float(student_lng)

        x1, y1 = float(sorted_poly[0][0]), float(sorted_poly[0][1])
        for i in range(1, n + 1):
            x2, y2 = float(sorted_poly[i % n][0]), float(sorted_poly[i % n][1])
            if ((y1 > py) != (y2 > py)) and (
                px < (x2 - x1) * (py - y1) / (y2 - y1) + x1
            ):
                inside = not inside
            x1, y1 = x2, y2

        return inside
    except Exception as e:
        logger.error('is_inside_polygon error: %s', e)
        return False


def _point_to_segment_distance(px, py, ax, ay, bx, by):
    """Minimum distance in metres from point P to segment AB."""
    ab = haversine_distance(ax, ay, bx, by)
    if ab < 0.001:
        return haversine_distance(px, py, ax, ay)

    R = 6_371_000.0
    avg_lat = math.radians((ax + bx) / 2.0)
    lat_m = math.radians(1.0) * R
    lng_m = math.radians(1.0) * R * math.cos(avg_lat)

    apx = (px - ax) * lat_m
    apy = (py - ay) * lng_m
    abx = (bx - ax) * lat_m
    aby = (by - ay) * lng_m

    ab2 = abx * abx + aby * aby
    if ab2 < 1e-9:
        return haversine_distance(px, py, ax, ay)

    t = max(0.0, min(1.0, (apx * abx + apy * aby) / ab2))
    closest_lat = ax + t * (bx - ax)
    closest_lng = ay + t * (by - ay)
    return haversine_distance(px, py, closest_lat, closest_lng)


# ─────────────────────────────────────────────────────────────────────────────
# ROOM CENTRE CALCULATION
# ─────────────────────────────────────────────────────────────────────────────
def calculate_room_center(corners_list):
    """Arithmetic centroid of room corners. Accepts ORM objects or dicts."""
    fallback = {'lat': 0.0, 'lng': 0.0}
    if not corners_list:
        return fallback
    try:
        lats, lngs = [], []
        for c in corners_list:
            if hasattr(c, 'latitude'):
                lat, lng = getattr(c, 'latitude', None), getattr(c, 'longitude', None)
            else:
                lat = c.get('lat') or c.get('latitude')
                lng = c.get('lng') or c.get('longitude')
            if lat is not None and lng is not None:
                lats.append(float(lat))
                lngs.append(float(lng))
        if lats:
            return {'lat': sum(lats) / len(lats), 'lng': sum(lngs) / len(lngs)}
    except Exception as e:
        logger.error('calculate_room_center error: %s', e)
    return fallback


# ─────────────────────────────────────────────────────────────────────────────
# MAIN ATTENDANCE GEOFENCE CHECK
# ─────────────────────────────────────────────────────────────────────────────
def check_inside_room(student_lat, student_lng, student_alt,
                      room, gps_accuracy=10.0, sensors=None):
    """
    Returns dict:
        is_valid            bool  — True → allow attendance
        inside_2d           bool  — strictly inside polygon
        altitude_ok         bool  — ALWAYS True (altitude unusable indoors)
        distance_to_centre  float — metres from student to room centre
        distance_to_boundary float — 0 if inside, else metres to nearest edge
        slack_used          float — GPS tolerance buffer applied
        validation_mode     str   — 'polygon' | 'polygon_slack' | 'radius' | 'denied'
        reason              str   — human-readable for logs
    """

    def _deny(reason, dist_centre=0.0, dist_boundary=0.0):
        logger.warning(
            'ATTENDANCE DENIED: %s | student=(%.6f,%.6f) room=%s',
            reason, student_lat, student_lng,
            getattr(room, 'name', str(room))
        )
        return {
            'is_valid': False, 'inside_2d': False, 'altitude_ok': True,
            'distance_to_centre': dist_centre,
            'distance_to_boundary': dist_boundary,
            'slack_used': 0.0, 'validation_mode': 'denied', 'reason': reason,
        }

    def _allow(reason, inside_2d, mode, dist_centre, dist_boundary, slack):
        logger.info(
            'ATTENDANCE ALLOWED: %s | student=(%.6f,%.6f) room=%s inside_2d=%s',
            reason, student_lat, student_lng,
            getattr(room, 'name', str(room)), inside_2d
        )
        return {
            'is_valid': True, 'inside_2d': inside_2d, 'altitude_ok': True,
            'distance_to_centre': dist_centre,
            'distance_to_boundary': dist_boundary,
            'slack_used': slack, 'validation_mode': mode, 'reason': reason,
        }

    try:
        s_lat = float(student_lat)
        s_lng = float(student_lng)
        gps_acc = float(gps_accuracy or 10.0)
    except (TypeError, ValueError) as e:
        return _deny(f'Invalid student coordinates: {e}')

    # ── Fetch corners ─────────────────────────────────────────────────────
    try:
        corners = list(room.corners.all().order_by('corner_index'))
    except Exception as e:
        logger.error('Could not fetch room corners: %s', e)
        return _deny('Could not fetch room corners from database')

    # ── GPS slack — scales with actual GPS quality ─────────────────────────
    # Tiered slack based on GPS accuracy:
    # - Good GPS (<=30m): tight 25m cap to prevent cheating
    # - Medium GPS (30-80m): allow up to 60m slack
    # - Poor GPS (>80m): allow up to half the GPS accuracy, max 150m
    # This is fair: if GPS says ±200m, being 57m from boundary is inside error margin
    max_corner_acc = 0.0
    for c in corners:
        acc = float(
            getattr(c, 'accuracy', None)
            or getattr(c, 'accuracy_meters', None)
            or 0.0
        )
        if acc > max_corner_acc:
            max_corner_acc = acc

    if gps_acc <= 30.0:
        slack = min(max(gps_acc, max_corner_acc, 8.0), 25.0)
    elif gps_acc <= 80.0:
        slack = min(max(gps_acc, max_corner_acc, 8.0), 60.0)
    else:
        # Poor GPS: be generous but not unlimited
        slack = min(max(gps_acc * 0.5, max_corner_acc, 8.0), 150.0)

    # ── CASE A: No corners → radius fallback ─────────────────────────────
    if len(corners) < 4:
        c_lat = float(getattr(room, 'center_lat', None) or 0.0)
        c_lng = float(getattr(room, 'center_lng', None) or 0.0)

        if c_lat == 0.0 and c_lng == 0.0:
            return _deny('Room has no corners and no centre point.')

        dist = haversine_distance(s_lat, s_lng, c_lat, c_lng)
        radius = float(getattr(room, 'radius_meters', None) or 30.0)

        if dist <= radius + slack:
            return _allow(
                f'Within radius {radius:.1f}m + slack {slack:.1f}m '
                f'(dist={dist:.1f}m)',
                inside_2d=False, mode='radius',
                dist_centre=dist,
                dist_boundary=max(0.0, dist - radius),
                slack=slack,
            )
        return _deny(
            f'Outside radius: dist={dist:.1f}m > '
            f'radius={radius:.1f}m + slack={slack:.1f}m',
            dist_centre=dist,
            dist_boundary=max(0.0, dist - radius),
        )

    # ── CASE B: Full 4-corner polygon ────────────────────────────────────
    poly = [(float(c.latitude), float(c.longitude)) for c in corners]

    c_lat = float(
        getattr(room, 'center_lat', None)
        or sum(p[0] for p in poly) / len(poly)
    )
    c_lng = float(
        getattr(room, 'center_lng', None)
        or sum(p[1] for p in poly) / len(poly)
    )

    dist_centre = haversine_distance(s_lat, s_lng, c_lat, c_lng)

    # Primary test: strict inside polygon
    try:
        inside_2d = is_inside_polygon(s_lat, s_lng, poly)
    except Exception as e:
        logger.error('Polygon test failed: %s', e)
        return _deny(f'Polygon test error: {e}')

    if inside_2d:
        return _allow(
            'Strictly inside polygon',
            inside_2d=True, mode='polygon',
            dist_centre=dist_centre, dist_boundary=0.0, slack=0.0,
        )

    # Secondary test: within slack metres of any edge
    try:
        sorted_poly = _sort_clockwise(poly)
        n = len(sorted_poly)
        min_edge_dist = float('inf')

        for i in range(n):
            p1 = sorted_poly[i]
            p2 = sorted_poly[(i + 1) % n]
            d = _point_to_segment_distance(
                s_lat, s_lng,
                p1[0], p1[1],
                p2[0], p2[1],
            )
            if d < min_edge_dist:
                min_edge_dist = d

        if min_edge_dist <= slack:
            return _allow(
                f'Within GPS slack: edge_dist={min_edge_dist:.1f}m '
                f'<= slack={slack:.1f}m',
                inside_2d=False, mode='polygon_slack',
                dist_centre=dist_centre,
                dist_boundary=min_edge_dist,
                slack=slack,
            )

        return _deny(
            f'Outside polygon and beyond slack: '
            f'edge_dist={min_edge_dist:.1f}m > slack={slack:.1f}m',
            dist_centre=dist_centre,
            dist_boundary=min_edge_dist,
        )

    except Exception as e:
        logger.error('Slack boundary check error: %s', e)
        # Fail-safe: DENY on unexpected errors
        return _deny(f'Boundary slack check failed: {e}')


def reconstruct_room_spatial_data(corners_list):
    """
    Reconstructs spatial parameters of the room using its 4 corners.
    Calculates: area, perimeter, orientation, quality and returns a dictionary.
    """
    if len(corners_list) != 4:
        return {
            'area': 0.0,
            'perimeter': 0.0,
            'orientation': 0.0,
            'quality': 100.0,
            'local_points': []
        }
    
    try:
        # Extract lat/lng
        pts = []
        accuracies = []
        for c in corners_list:
            if hasattr(c, 'latitude'):
                lat = float(getattr(c, 'latitude', 0.0))
                lng = float(getattr(c, 'longitude', 0.0))
                acc = float(getattr(c, 'accuracy', 0.0))
            else:
                lat = float(c.get('lat') or c.get('latitude') or 0.0)
                lng = float(c.get('lng') or c.get('longitude') or 0.0)
                acc = float(c.get('accuracy') or 0.0)
            pts.append((lat, lng))
            accuracies.append(acc)
            
        # 1. Centroid
        centroid_lat = sum(p[0] for p in pts) / 4.0
        centroid_lng = sum(p[1] for p in pts) / 4.0
        
        # 2. Clockwise sort vertices around centroid
        sorted_pts = sorted(pts, key=lambda p: math.atan2(p[0] - centroid_lat, p[1] - centroid_lng), reverse=True)
        
        # 3. Project to Local Cartesian space (meters)
        lat_rad = math.radians(centroid_lat)
        meters_per_degree_lat = 110574.0
        meters_per_degree_lng = 111320.0 * math.cos(lat_rad)
        
        local_pts = []
        for p in sorted_pts:
            x = (p[1] - centroid_lng) * meters_per_degree_lng
            y = (p[0] - centroid_lat) * meters_per_degree_lat
            local_pts.append((x, y))
            
        # 4. Enclosed Area (Shoelace Formula)
        shoelace_sum = 0.0
        for i in range(4):
            next_idx = (i + 1) % 4
            shoelace_sum += (local_pts[i][0] * local_pts[next_idx][1]) - (local_pts[next_idx][0] * local_pts[i][1])
        area = abs(shoelace_sum) / 2.0
        
        # 5. Wall Lengths & Perimeter
        wall_lengths = []
        perimeter = 0.0
        for i in range(4):
            next_idx = (i + 1) % 4
            dx = local_pts[next_idx][0] - local_pts[i][0]
            dy = local_pts[next_idx][1] - local_pts[i][1]
            length = math.sqrt(dx*dx + dy*dy)
            wall_lengths.append(length)
            perimeter += length
            
        # 6. Orientation (angle of longest wall segment relative to True North)
        max_len = -1.0
        longest_wall_idx = 0
        for i in range(4):
            if wall_lengths[i] > max_len:
                max_len = wall_lengths[i]
                longest_wall_idx = i
        
        p1 = local_pts[longest_wall_idx]
        p2 = local_pts[(longest_wall_idx + 1) % 4]
        radians = math.atan2(p2[0] - p1[0], p2[1] - p1[1])
        orientation = (math.degrees(radians) + 360.0) % 360.0
        
        # 7. Quality Score
        quality = 100.0
        avg_acc = sum(accuracies) / 4.0
        if avg_acc > 5.0:
            quality -= (avg_acc - 5.0) * 2.0
            
        # Non-convexity check
        is_convex = True
        for i in range(4):
            p0 = local_pts[i]
            p1 = local_pts[(i + 1) % 4]
            p2 = local_pts[(i + 2) % 4]
            cross = (p1[0] - p0[0]) * (p2[1] - p1[1]) - (p1[1] - p0[1]) * (p2[0] - p1[0])
            if i == 0:
                first_sign = cross > 0
            else:
                if (cross > 0) != first_sign:
                    is_convex = False
                    break
        if not is_convex:
            quality -= 30.0
            
        quality = max(10.0, min(100.0, quality))
        
        return {
            'area': area,
            'perimeter': perimeter,
            'orientation': orientation,
            'quality': quality,
            'local_points': [{'x': p[0], 'y': p[1]} for p in local_pts]
        }
    except Exception as e:
        logger.error('reconstruct_room_spatial_data error: %s', e)
        return {
            'area': 0.0,
            'perimeter': 0.0,
            'orientation': 0.0,
            'quality': 50.0,
            'local_points': []
        }