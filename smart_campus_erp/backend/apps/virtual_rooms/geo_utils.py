"""
Production-grade geofencing utilities for 3D Virtual Classroom validation.
Optimized for indoor GPS drift and irregular capture orders.

Features:
- Polygon Corner Sorting (Anti-clockwise)
- Point-in-Polygon (Ray Casting)
- Dynamic Accuracy Compensation
- Indoor Altitude Stabilization
- Standardized geo-validation response contract
"""
import math


# ════════════════════════════════════════════════════════════════
# Core Distance Calculation
# ════════════════════════════════════════════════════════════════

def haversine_distance(lat1: float, lng1: float,
                       lat2: float, lng2: float) -> float:
    """Returns distance in METERS."""
    R = 6_371_000.0
    phi1 = math.radians(float(lat1))
    phi2 = math.radians(float(lat2))
    delta_phi = math.radians(float(lat2) - float(lat1))
    delta_lambda = math.radians(float(lng2) - float(lng1))
    a = (math.sin(delta_phi / 2) ** 2
         + math.cos(phi1) * math.cos(phi2)
         * math.sin(delta_lambda / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


# ════════════════════════════════════════════════════════════════
# Polygon Geometry Helpers
# ════════════════════════════════════════════════════════════════

def _sort_corners(polygon: list) -> list:
    """Sort polygon corners in anti-clockwise order relative to centroid."""
    if len(polygon) < 3:
        return polygon
    clat, clng = _polygon_centroid(polygon)
    def _get_angle(p):
        return math.atan2(p[0] - clat, p[1] - clng)
    return sorted(polygon, key=_get_angle)


def _point_in_polygon_geo(lat: float, lng: float,
                          polygon: list) -> bool:
    """Ray-casting algorithm for geographic coordinates."""
    n = len(polygon)
    if n < 3: return False
    inside = False
    j = n - 1
    for i in range(n):
        yi, xi = polygon[i]
        yj, xj = polygon[j]
        if ((yi > lat) != (yj > lat)) and \
           (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside


def _polygon_centroid(polygon: list) -> tuple:
    n = len(polygon)
    if n == 0: return (0.0, 0.0)
    return sum(p[0] for p in polygon) / n, sum(p[1] for p in polygon) / n


def _expand_polygon(polygon: list, buffer_meters: float) -> list:
    """Radial expansion relative to centroid."""
    if not polygon or buffer_meters <= 0:
        return polygon
    clat, clng = _polygon_centroid(polygon)
    expanded = []
    for lat, lng in polygon:
        dist = haversine_distance(clat, clng, lat, lng)
        if dist < 0.1:
            expanded.append((lat, lng))
            continue
        scale = (dist + buffer_meters) / dist
        expanded.append((clat + (lat - clat) * scale, clng + (lng - clng) * scale))
    return expanded


def _distance_to_polygon_edge(lat: float, lng: float,
                               polygon: list) -> float:
    min_dist = float('inf')
    n = len(polygon)
    for i in range(n):
        j = (i + 1) % n
        dist = _point_to_segment_distance(lat, lng, polygon[i][0], polygon[i][1], polygon[j][0], polygon[j][1])
        min_dist = min(min_dist, dist)
    return min_dist


def _point_to_segment_distance(px, py, ax, ay, bx, by) -> float:
    dx, dy = bx - ax, by - ay
    l2 = dx*dx + dy*dy
    if l2 == 0: return haversine_distance(px, py, ax, ay)
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / l2))
    return haversine_distance(px, py, ax + t * dx, ay + t * dy)


# ════════════════════════════════════════════════════════════════
# Room Validation
# ════════════════════════════════════════════════════════════════

def check_inside_room(lat: float, lng: float,
                      altitude: float, room,
                      horizontal_accuracy: float = 10.0,
                      custom_radius: float = None) -> dict:
    """
    Validates if student is inside classroom with indoor GPS tolerance.
    Returns a standardized dictionary contract.
    """
    has_polygon = getattr(room, 'has_polygon', False)

    if has_polygon:
        return _check_polygon_mode(lat, lng, altitude, room, horizontal_accuracy)
    else:
        return _check_radius_mode(lat, lng, altitude, room, horizontal_accuracy, custom_radius)


def _check_polygon_mode(lat: float, lng: float,
                        altitude: float, room,
                        horizontal_accuracy: float) -> dict:
    # 1. Fetch and sequence corners
    raw_polygon = room.get_corners()
    polygon = _sort_corners(raw_polygon)
    
    # 2. Dynamic Accuracy Buffer
    accuracy_slack = max(5.0, horizontal_accuracy * 0.7)
    total_buffer = accuracy_slack + 5.0
    expanded_polygon = _expand_polygon(polygon, total_buffer)
    
    # 3. 2D Check
    inside_2d = _point_in_polygon_geo(lat, lng, expanded_polygon)
    
    # 4. Fallback Radius Check
    clat, clng = _polygon_centroid(polygon)
    dist_to_center = haversine_distance(lat, lng, clat, clng)
    max_radius = max([haversine_distance(clat, clng, p[0], p[1]) for p in polygon])
    effective_radius = max_radius + total_buffer
    
    if not inside_2d and horizontal_accuracy > 25.0:
        if dist_to_center <= effective_radius:
            inside_2d = True

    # 5. Altitude Validation
    altitude_ok = _check_altitude(altitude, room, horizontal_accuracy)

    # 6. Standardized Response Contract
    return {
        'inside'                : inside_2d and altitude_ok,
        'inside_2d'             : inside_2d,
        'altitude_ok'           : altitude_ok,
        'distance_from_center'  : round(dist_to_center, 2),
        'distance_to_boundary'  : round(0.0 if inside_2d else _distance_to_polygon_edge(lat, lng, polygon), 2),
        'radius_used'           : round(max_radius, 2), # Polygon 'radius' is its furthest corner
        'effective_radius'      : round(effective_radius, 2),
        'accuracy_slack_applied': round(total_buffer, 2),
        'validation_mode'       : 'polygon',
    }


def _check_radius_mode(lat: float, lng: float,
                       altitude: float, room,
                       horizontal_accuracy: float,
                       custom_radius: float = None) -> dict:
    distance = haversine_distance(lat, lng, float(room.center_lat), float(room.center_lng))
    base_radius = float(custom_radius if custom_radius is not None else room.radius_meters)
    
    # Accuracy-aware expansion
    accuracy_slack = max(5.0, horizontal_accuracy * 0.8)
    effective_radius = base_radius + accuracy_slack + 10.0
    
    inside_2d = distance <= effective_radius
    altitude_ok = _check_altitude(altitude, room, horizontal_accuracy)

    return {
        'inside'                : inside_2d and altitude_ok,
        'inside_2d'             : inside_2d,
        'altitude_ok'           : altitude_ok,
        'distance_from_center'  : round(distance, 2),
        'distance_to_boundary'  : round(max(0.0, distance - effective_radius), 2),
        'radius_used'           : base_radius,
        'effective_radius'      : round(effective_radius, 2),
        'accuracy_slack_applied': round(accuracy_slack + 10.0, 2),
        'validation_mode'       : 'radius',
    }


def _check_altitude(altitude: float, room, horizontal_accuracy: float) -> bool:
    room_min = float(room.min_altitude)
    room_max = float(room.max_altitude)
    if room_min == 0.0 and room_max == 50.0: return True
    alt_buffer = 35.0
    if horizontal_accuracy > 30.0: alt_buffer = 60.0
    return (room_min - alt_buffer) <= float(altitude) <= (room_max + alt_buffer)


def calculate_room_dimensions(corners: list) -> dict:
    """Calculates room stats from 4 corners."""
    if len(corners) < 3: return {'estimated_area': 0.0, 'center_lat': 0.0, 'center_lng': 0.0}
    pts = _sort_corners([(float(c['lat']), float(c['lng'])) for c in corners])
    n = len(pts)
    clat, clng = _polygon_centroid(pts)
    edges = []
    for i in range(n):
        edges.append(haversine_distance(pts[i][0], pts[i][1], pts[(i+1)%n][0], pts[(i+1)%n][1]))
    if n == 4:
        w, l = (edges[0] + edges[2]) / 2, (edges[1] + edges[3]) / 2
    else:
        w, l = min(edges), max(edges)
    return {
        'estimated_length': round(l, 2),
        'estimated_width': round(w, 2),
        'estimated_area': round(l * w, 2),
        'center_lat': round(clat, 7),
        'center_lng': round(clng, 7),
    }
