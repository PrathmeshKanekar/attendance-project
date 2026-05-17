"""
geo_utils.py — 3D Spatial Mathematics for Virtual Room Attendance
=================================================================
All coordinate transformations use ENU (East-North-Up) local frame.
Every public function has explicit type hints and raises on bad input.
"""
from __future__ import annotations
import math
import logging
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .models import VirtualRoom

logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────────────────
# Earth constants
# ─────────────────────────────────────────────────────────────────────────────

EARTH_RADIUS_M = 6_371_000.0          # Mean radius (meters)
LAT_TO_M       = 111_111.0            # Meters per degree of latitude (approx)


def lng_to_m(lat_deg: float) -> float:
    """Meters per degree of longitude at the given latitude."""
    return LAT_TO_M * math.cos(math.radians(lat_deg))


# ─────────────────────────────────────────────────────────────────────────────
# Basic geometry helpers
# ─────────────────────────────────────────────────────────────────────────────

def haversine_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """
    Great-circle distance (meters) between two WGS-84 points.
    Accurate to ~0.5% at distances < 1000 km.
    """
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi        = math.radians(lat2 - lat1)
    dlamb       = math.radians(lng2 - lng1)
    a = (
        math.sin(dphi  / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlamb / 2) ** 2
    )
    return 2 * EARTH_RADIUS_M * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


@dataclass
class Vec3:
    """Immutable 3D vector in ENU local frame (metres)."""
    x: float
    y: float
    z: float

    @property
    def magnitude(self) -> float:
        return math.sqrt(self.x ** 2 + self.y ** 2 + self.z ** 2)

    def normalized(self) -> "Vec3":
        m = self.magnitude
        if m < 1e-9:
            raise ValueError("Cannot normalise zero vector")
        return Vec3(self.x / m, self.y / m, self.z / m)

    def dot(self, other: "Vec3") -> float:
        return self.x * other.x + self.y * other.y + self.z * other.z

    def cross(self, other: "Vec3") -> "Vec3":
        return Vec3(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        )

    def to_dict(self) -> dict:
        return {"x": self.x, "y": self.y, "z": self.z, "mag": self.magnitude}

    @classmethod
    def from_dict(cls, d: dict) -> "Vec3":
        return cls(float(d["x"]), float(d["y"]), float(d["z"]))


def enu_vector(
    origin_lat: float, origin_lng: float, origin_alt: float,
    target_lat: float, target_lng: float, target_alt: float,
) -> Vec3:
    """
    3D displacement vector from origin → target in ENU local frame (metres).
    East = +X, North = +Y, Up = +Z.
    """
    east  = (target_lng - origin_lng) * lng_to_m(origin_lat)
    north = (target_lat - origin_lat) * LAT_TO_M
    up    = target_alt - origin_alt
    return Vec3(east, north, up)


# ─────────────────────────────────────────────────────────────────────────────
# Polygon geometry helpers
# ─────────────────────────────────────────────────────────────────────────────

def polygon_area_m2(corners: list) -> float:
    """
    Compute the area of a polygon defined by corner objects with lat/lng.
    Uses the Shoelace formula in local ENU coordinates.
    """
    if len(corners) < 3:
        return 0.0

    origin_lat = corners[0].lat
    origin_lng = corners[0].lng
    origin_alt = corners[0].altitude

    # Convert all corners to local ENU
    points = []
    for c in corners:
        v = enu_vector(origin_lat, origin_lng, origin_alt, c.lat, c.lng, c.altitude)
        points.append((v.x, v.y))

    # Shoelace formula
    n = len(points)
    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += points[i][0] * points[j][1]
        area -= points[j][0] * points[i][1]
    return abs(area) / 2.0


def check_polygon_self_intersection(corners: list) -> bool:
    """
    Check if the polygon defined by corners has self-intersecting edges.
    Returns True if there IS a self-intersection (invalid polygon).
    """
    if len(corners) < 4:
        return False

    origin_lat = corners[0].lat
    origin_lng = corners[0].lng
    origin_alt = corners[0].altitude

    points = []
    for c in corners:
        v = enu_vector(origin_lat, origin_lng, origin_alt, c.lat, c.lng, c.altitude)
        points.append((v.x, v.y))

    n = len(points)
    edges = []
    for i in range(n):
        edges.append((points[i], points[(i + 1) % n]))

    def ccw(a, b, c):
        return (c[1] - a[1]) * (b[0] - a[0]) > (b[1] - a[1]) * (c[0] - a[0])

    def segments_intersect(a, b, c, d):
        return ccw(a, c, d) != ccw(b, c, d) and ccw(a, b, c) != ccw(a, b, d)

    for i in range(n):
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue  # Adjacent edges share a vertex
            if segments_intersect(edges[i][0], edges[i][1], edges[j][0], edges[j][1]):
                return True
    return False


def point_in_polygon_enu(px: float, py: float, polygon_points: list) -> bool:
    """
    Ray-casting point-in-polygon test.
    polygon_points: list of (x, y) tuples in local ENU frame.
    """
    n = len(polygon_points)
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = polygon_points[i]
        xj, yj = polygon_points[j]
        if ((yi > py) != (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside


def calculate_polygon_area(corners: list) -> float:
    """Compute polygon area using Shoelace formula in local ENU coordinates."""
    return polygon_area_m2(corners)


def calculate_room_dimensions(corners: list) -> dict:
    """
    Compute room's physical dimensions: length, width, height, and perimeter.
    Corners should be ordered by corner_index.
    """
    if len(corners) < 4:
        return {"length": 0.0, "width": 0.0, "height": 0.0, "perimeter": 0.0}
    c1, c2, c3, c4 = corners[0], corners[1], corners[2], corners[3]

    # Haversine-based dimensions
    length = haversine_distance(c1.lat, c1.lng, c2.lat, c2.lng)
    width = haversine_distance(c1.lat, c1.lng, c4.lat, c4.lng)

    alts = [c.altitude for c in corners]
    height = max(alts) - min(alts)
    if height < 0.5:
        height = 3.0  # Default fallback room height

    d12 = haversine_distance(c1.lat, c1.lng, c2.lat, c2.lng)
    d23 = haversine_distance(c2.lat, c2.lng, c3.lat, c3.lng)
    d34 = haversine_distance(c3.lat, c3.lng, c4.lat, c4.lng)
    d41 = haversine_distance(c4.lat, c4.lng, c1.lat, c1.lng)
    perimeter = d12 + d23 + d34 + d41

    return {
        "length": round(length, 3),
        "width": round(width, 3),
        "height": round(height, 3),
        "perimeter": round(perimeter, 3),
    }


def calculate_room_center(corners: list) -> dict:
    """Compute average coordinates for room center."""
    if not corners:
        return {"lat": 0.0, "lng": 0.0}
    avg_lat = sum(c.lat for c in corners) / len(corners)
    avg_lng = sum(c.lng for c in corners) / len(corners)
    return {
        "lat": round(avg_lat, 7),
        "lng": round(avg_lng, 7),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Spatial vector calculation (called after 4 corners are captured)
# ─────────────────────────────────────────────────────────────────────────────

def calculate_spatial_vectors(room: "VirtualRoom") -> None:
    """
    Build the room's local ENU coordinate frame from its 4 captured corners.
    Computes polygon, centroid, dimensions, spatial vectors, and normalized coordinates.
    """
    from django.contrib.gis.geos import Point, Polygon
    from .models import SpatialMetadata

    corners = list(room.corners.order_by("corner_index"))
    if len(corners) < 4:
        raise ValueError(f"Room {room.id} has only {len(corners)} corners — need 4.")

    c1, c2, c3, c4 = corners[0], corners[1], corners[2], corners[3]

    origin_lat = c1.lat
    origin_lng = c1.lng
    origin_alt = c1.altitude

    # Raw displacement vectors (ENU, metres)
    raw_x = enu_vector(origin_lat, origin_lng, origin_alt, c2.lat, c2.lng, c2.altitude)
    raw_y = enu_vector(origin_lat, origin_lng, origin_alt, c4.lat, c4.lng, c4.altitude)

    unit_x = raw_x.normalized()
    unit_y = raw_y.normalized()
    unit_z = unit_x.cross(unit_y)

    # Normalize Z if possible
    z_mag = unit_z.magnitude
    if z_mag > 1e-9:
        unit_z = Vec3(unit_z.x / z_mag, unit_z.y / z_mag, unit_z.z / z_mag)

    alts = [c.altitude for c in corners]
    min_alt = min(alts)
    max_alt = max(alts)

    # Build polygon ring (must close)
    ring_pts = [(c.lng, c.lat) for c in corners]
    ring_pts.append(ring_pts[0])

    try:
        polygon = Polygon(ring_pts, srid=4326)
        centroid = polygon.centroid
    except Exception as e:
        logger.error("Failed to create polygon for room %s: %s", room.id, e)
        raise

    heading_rad = math.atan2(raw_x.x, raw_x.y)
    heading_deg = (math.degrees(heading_rad) + 360) % 360

    length = round(raw_x.magnitude, 3)
    width  = round(raw_y.magnitude, 3)

    # Compute area using ENU Shoelace formula
    area = round(polygon_area_m2(corners), 2)

    # Compute normalized coordinates (local X/Y for each corner)
    normalized_coords = []
    for c in corners:
        disp = enu_vector(origin_lat, origin_lng, origin_alt, c.lat, c.lng, c.altitude)
        local_x = disp.dot(unit_x)
        local_y = disp.dot(unit_y)
        local_z = disp.dot(unit_z)
        normalized_coords.append({
            "x": round(local_x, 4),
            "y": round(local_y, 4),
            "z": round(local_z, 4),
        })

    # Compute orientation matrix (3×3 rotation from ENU to local room frame)
    orientation_matrix = [
        [round(unit_x.x, 6), round(unit_x.y, 6), round(unit_x.z, 6)],
        [round(unit_y.x, 6), round(unit_y.y, 6), round(unit_y.z, 6)],
        [round(unit_z.x, 6), round(unit_z.y, 6), round(unit_z.z, 6)],
    ]

    height = round(max_alt - min_alt, 3) if (max_alt - min_alt) > 0.5 else 3.0

    room.polygon_area      = area
    room.min_altitude      = round(min_alt, 3)
    room.max_altitude      = round(max_alt, 3)
    room.polygon           = polygon
    room.centroid          = centroid
    room.center_lat        = centroid.y
    room.center_lng        = centroid.x
    room.normalized_coordinates = normalized_coords
    room.orientation_matrix = orientation_matrix
    room.room_dimensions = {
        "length": length,
        "width": width,
        "height": height,
    }
    room.x_axis_vector = unit_x.to_dict()
    room.y_axis_vector = unit_y.to_dict()
    room.z_axis_vector = unit_z.to_dict()

    room.save(update_fields=[
        "polygon_area", "min_altitude", "max_altitude",
        "polygon", "centroid", "center_lat", "center_lng",
        "normalized_coordinates", "orientation_matrix", "room_dimensions",
        "x_axis_vector", "y_axis_vector", "z_axis_vector",
    ])

    SpatialMetadata.objects.update_or_create(
        room=room,
        defaults={
            "metadata": {
                "origin_point":  {"lat": origin_lat, "lng": origin_lng, "alt": origin_alt},
                "x_axis_vector": unit_x.to_dict(),
                "y_axis_vector": unit_y.to_dict(),
                "z_axis_vector": unit_z.to_dict(),
                "x_extent":      length,
                "y_extent":      width,
            }
        }
    )

    logger.info(
        "Spatial vectors computed for room %s: %s×%s m, area=%.1f m², heading=%.1f°",
        room.room_name, length, width, area, heading_deg,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Student location validation
# ─────────────────────────────────────────────────────────────────────────────

def check_inside_room(
    student_lat: float,
    student_lng: float,
    student_alt: float,
    room: "VirtualRoom",
    gps_accuracy: float = 10.0,
    sensors: dict | None = None,
) -> dict:
    """
    Production spatial validator:
    1. If room has 4 corners and vectors -> use 3D Local Vector projection.
    2. Fallback -> use Haversine radius check.

    Returns a dict compatible with AttendanceLocationLog fields.
    """
    # Collect anti-spoofing flags
    spoof_flags = []

    # Check GPS accuracy — flag if > 30m (likely indoor/degraded)
    if gps_accuracy > 30:
        spoof_flags.append("high_gps_uncertainty")

    # If sensors provided, do basic anti-spoofing checks
    if sensors:
        accel = sensors.get("accelerometer", {})
        accel_mag = math.sqrt(
            accel.get("x", 0) ** 2 + accel.get("y", 0) ** 2 + accel.get("z", 0) ** 2
        )
        # Normal gravity is ~9.81 m/s² — if magnitude is far off, flag it
        if accel_mag < 5.0 or accel_mag > 15.0:
            spoof_flags.append("unusual_accelerometer")

    # ── Fallback: radius-only mode ──────────────────────────────────────
    has_polygon = getattr(room, 'has_polygon', False)
    has_vectors = hasattr(room, 'spatial_vectors')

    if not has_polygon or not has_vectors:
        try:
            room.spatial_vectors
        except Exception:
            has_vectors = False

    if not has_polygon or not has_vectors:
        center_lat = getattr(room, 'center_lat', None)
        center_lng = getattr(room, 'center_lng', None)

        if center_lat is None or center_lng is None:
            return {
                'is_valid': False,
                'validation_mode': 'error',
                'inside_2d': False,
                'altitude_ok': False,
                'local_x': None,
                'local_y': None,
                'local_z': None,
                'confidence': 0.0,
                'spoof_flags': ['no_room_geometry'],
            }

        dist = haversine_distance(student_lat, student_lng, center_lat, center_lng)
        effective_radius = getattr(room, 'radius_meters', 30.0)
        accuracy_slack = min(gps_accuracy * 0.5, 15.0)
        inside_2d = dist <= (effective_radius + accuracy_slack)

        tol = getattr(room, 'altitude_tolerance', 4.0)
        alt_min = getattr(room, 'min_altitude', student_alt - 5)
        alt_max = getattr(room, 'max_altitude', student_alt + 5)
        altitude_ok = (alt_min - tol) <= student_alt <= (alt_max + tol)

        is_valid = inside_2d and altitude_ok
        confidence = max(0.0, 1.0 - (dist / effective_radius)) if effective_radius > 0 else 0.0

        return {
            'is_valid': is_valid,
            'validation_mode': 'radius',
            'inside_2d': inside_2d,
            'altitude_ok': altitude_ok,
            'local_x': None,
            'local_y': None,
            'local_z': None,
            'confidence': round(min(confidence, 1.0), 3),
            'spoof_flags': spoof_flags,
        }

    # ── Full 3D polygon + vector validation ─────────────────────────────
    try:
        res = _validate_3d(student_lat, student_lng, student_alt, room, gps_accuracy, spoof_flags)

        # Apply backup validation only if primary validation failed and signal is unstable/degraded
        if not res.get('is_valid', False):
            gps_unstable = (gps_accuracy > 15.0) or ("high_gps_uncertainty" in spoof_flags)
            low_sensor_confidence = len(spoof_flags) > 0

            if gps_unstable or low_sensor_confidence:
                center_lat = room.center_lat if room.center_lat is not None else (room.centroid.y if room.centroid else student_lat)
                center_lng = room.center_lng if room.center_lng is not None else (room.centroid.x if room.centroid else student_lng)

                # Fallback radius: calculated from polygon dimensions (diagonal / 2 or max dimension * 0.7)
                length = room.length if room.length is not None else 20.0
                width = room.width if room.width is not None else 20.0
                fallback_radius = max(length, width) * 0.7

                dist = haversine_distance(student_lat, student_lng, center_lat, center_lng)
                accuracy_slack = min(gps_accuracy * 0.5, 15.0)

                # Validate against circular geo-fence backup
                if dist <= (fallback_radius + accuracy_slack) and res.get('altitude_ok', False):
                    res['is_valid'] = True
                    res['validation_mode'] = 'polygon_3d_fallback'
                    res['fallback_applied'] = True
                    # Recalculate confidence for circular boundary fallback
                    fallback_conf = max(0.0, 1.0 - (dist / fallback_radius)) if fallback_radius > 0 else 0.0
                    res['confidence'] = round(min(fallback_conf, 0.9), 3)

        return res
    except Exception as exc:
        logger.error("3D validation failed for room %s: %s", room.id, exc)
        # Fallback to radius
        dist = haversine_distance(student_lat, student_lng, room.center_lat, room.center_lng)
        effective_radius = max(room.length or 30, room.width or 30)
        inside_2d = dist <= effective_radius
        return {
            'is_valid': inside_2d,
            'validation_mode': 'radius_fallback',
            'inside_2d': inside_2d,
            'altitude_ok': True,
            'local_x': None,
            'local_y': None,
            'local_z': None,
            'confidence': 0.5,
            'spoof_flags': spoof_flags + ['3d_validation_error'],
        }


def _validate_3d(
    student_lat: float,
    student_lng: float,
    student_alt: float,
    room: "VirtualRoom",
    gps_accuracy: float,
    spoof_flags: list,
) -> dict:
    """
    Full 3D validation pipeline using Spatial Vectors.
    Projects student GPS into local room coordinate system.
    """
    from django.contrib.gis.geos import Point

    sv = room.spatial_vectors
    origin = sv.origin_point

    # 1. PostGIS 2D containment check
    pt2d = Point(student_lng, student_lat, srid=4326)
    inside_2d = room.boundary_polygon.contains(pt2d)

    # 2. Altitude check
    tol = getattr(room, 'altitude_tolerance', 4.0)
    alt_min_eff = room.min_altitude - tol
    alt_max_eff = room.max_altitude + tol
    altitude_ok = alt_min_eff <= student_alt <= alt_max_eff

    # 3. Local coordinate projection
    disp = enu_vector(
        origin["lat"], origin["lng"], origin["alt"],
        student_lat, student_lng, student_alt,
    )

    ux = Vec3.from_dict(sv.x_axis_vector)
    uy = Vec3.from_dict(sv.y_axis_vector)
    uz = Vec3.from_dict(sv.z_axis_vector)

    local_x = disp.dot(ux)
    local_y = disp.dot(uy)
    local_z = disp.dot(uz)

    # 4. Bounding box check with GPS accuracy slack
    slack = min(gps_accuracy * 0.5, 10.0)
    within_x = -slack <= local_x <= sv.x_extent + slack
    within_y = -slack <= local_y <= sv.y_extent + slack

    # 5. Combined validity
    is_valid = inside_2d and altitude_ok and within_x and within_y

    # 6. Confidence calculation
    # Distance from center as fraction of room diagonal
    room_diagonal = math.sqrt(sv.x_extent ** 2 + sv.y_extent ** 2)
    center_x = sv.x_extent / 2
    center_y = sv.y_extent / 2
    dist_from_center = math.sqrt((local_x - center_x) ** 2 + (local_y - center_y) ** 2)
    confidence = max(0.0, 1.0 - (dist_from_center / (room_diagonal / 2))) if room_diagonal > 0 else 0.0

    # 7. Distance to boundary for diagnostics
    if is_valid:
        distance_to_boundary = 0.0
    else:
        # Approximate: how far outside the bounding box
        dx = max(0, -local_x, local_x - sv.x_extent)
        dy = max(0, -local_y, local_y - sv.y_extent)
        distance_to_boundary = math.sqrt(dx ** 2 + dy ** 2)

    return {
        'is_valid': is_valid,
        'validation_mode': 'polygon_3d',
        'inside_2d': inside_2d,
        'altitude_ok': altitude_ok,
        'local_x': round(local_x, 3),
        'local_y': round(local_y, 3),
        'local_z': round(local_z, 3),
        'confidence': round(min(confidence, 1.0), 3),
        'spoof_flags': spoof_flags,
        'distance_to_boundary': round(distance_to_boundary, 2),
    }