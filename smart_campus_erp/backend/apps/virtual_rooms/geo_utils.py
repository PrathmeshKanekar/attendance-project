import math
import logging

logger = logging.getLogger(__name__)

EARTH_RADIUS_M = 6_371_000.0          # Mean radius (meters)
LAT_TO_M       = 111_111.0            # Meters per degree of latitude (approx)

def lng_to_m(lat_deg: float) -> float:
    """Meters per degree of longitude at the given latitude."""
    return LAT_TO_M * math.cos(math.radians(lat_deg))

def haversine_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """
    Great-circle distance (meters) between two WGS-84 points.
    """
    try:
        phi1, phi2 = math.radians(lat1), math.radians(lat2)
        dphi        = math.radians(lat2 - lat1)
        dlamb       = math.radians(lng2 - lng1)
        a = (
            math.sin(dphi  / 2) ** 2
            + math.cos(phi1) * math.cos(phi2) * math.sin(dlamb / 2) ** 2
        )
        return 2 * EARTH_RADIUS_M * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    except Exception as e:
        logger.error(f"Error calculating haversine distance: {e}")
        return 0.0

class Vec3:
    """Simple 3D vector for API compatibility."""
    def __init__(self, x: float, y: float, z: float):
        self.x = x
        self.y = y
        self.z = z

    @property
    def magnitude(self) -> float:
        return math.sqrt(self.x ** 2 + self.y ** 2 + self.z ** 2)

    def normalized(self, fallback = None):
        m = self.magnitude
        if m < 1e-9:
            return fallback or Vec3(1.0, 0.0, 0.0)
        return Vec3(self.x / m, self.y / m, self.z / m)

    def dot(self, other) -> float:
        return self.x * other.x + self.y * other.y + self.z * other.z

    def cross(self, other):
        return Vec3(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        )

    def to_dict(self) -> dict:
        return {"x": self.x, "y": self.y, "z": self.z, "mag": self.magnitude}

    @classmethod
    def from_dict(cls, d: dict):
        return cls(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))

def enu_vector(
    origin_lat: float, origin_lng: float, origin_alt: float,
    target_lat: float, target_lng: float, target_alt: float,
) -> Vec3:
    """displacement vector from origin → target in ENU local frame."""
    east  = (target_lng - origin_lng) * lng_to_m(origin_lat)
    north = (target_lat - origin_lat) * LAT_TO_M
    up    = target_alt - origin_alt
    return Vec3(east, north, up)

def point_in_polygon_enu(px: float, py: float, polygon_points: list) -> bool:
    """Ray-casting point-in-polygon test."""
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
    """Compute polygon area using Shoelace formula in local coordinates."""
    if len(corners) < 3:
        return 0.0
    try:
        origin_lat = corners[0].latitude
        origin_lng = corners[0].longitude
        origin_alt = corners[0].altitude
        points = []
        for c in corners:
            v = enu_vector(origin_lat, origin_lng, origin_alt, c.latitude, c.longitude, c.altitude)
            points.append((v.x, v.y))
        n = len(points)
        area = 0.0
        for i in range(n):
            j = (i + 1) % n
            area += points[i][0] * points[j][1]
            area -= points[j][0] * points[i][1]
        return round(abs(area) / 2.0, 2)
    except Exception:
        return 0.0

def calculate_room_dimensions(corners: list) -> dict:
    """Compute length, width, height, and perimeter from corners list."""
    if len(corners) < 4:
        return {"length": 0.0, "width": 0.0, "height": 3.0, "perimeter": 0.0}
    try:
        c1, c2, c3, c4 = corners[0], corners[1], corners[2], corners[3]
        length = haversine_distance(c1.latitude, c1.longitude, c2.latitude, c2.longitude)
        width = haversine_distance(c1.latitude, c1.longitude, c4.latitude, c4.longitude)
        alts = [c.altitude for c in corners]
        height = max(alts) - min(alts)
        if height < 0.5:
            height = 3.0
        perimeter = (length + width) * 2.0
        return {
            "length": round(length, 3),
            "width": round(width, 3),
            "height": round(height, 3),
            "perimeter": round(perimeter, 3),
        }
    except Exception:
        return {"length": 0.0, "width": 0.0, "height": 3.0, "perimeter": 0.0}

def calculate_room_center(corners: list) -> dict:
    """Compute center point of the corners."""
    if not corners:
        return {"lat": 0.0, "lng": 0.0}
    try:
        avg_lat = sum(c.latitude for c in corners) / len(corners)
        avg_lng = sum(c.longitude for c in corners) / len(corners)
        return {
            "lat": round(avg_lat, 7),
            "lng": round(avg_lng, 7),
        }
    except Exception:
        return {"lat": 0.0, "lng": 0.0}

def calculate_spatial_vectors(room) -> None:
    """Backward compatibility stub."""
    pass

def check_inside_room(
    student_lat: float,
    student_lng: float,
    student_alt: float,
    room,
    gps_accuracy: float = 10.0,
    sensors: dict | None = None,
) -> dict:
    """
    Checks if a student is inside the virtual room footprint.
    NO external native spatial libraries are needed to perform the containment checks.
    Uses try/catch and never crashes.
    """
    try:
        corners = list(room.corners.all().order_by('corner_index'))
        
        # Fallback to simple radius if corners are not 4
        if len(corners) < 4:
            c_lat = getattr(room, 'center_lat', 0.0) or 0.0
            c_lng = getattr(room, 'center_lng', 0.0) or 0.0
            dist = haversine_distance(student_lat, student_lng, c_lat, c_lng)
            
            radius = getattr(room, 'radius_meters', 30.0) or 30.0
            accuracy_slack = min(gps_accuracy * 0.5, 15.0)
            inside_2d = dist <= (radius + accuracy_slack)
            
            return {
                'is_valid': inside_2d,
                'inside_2d': inside_2d,
                'altitude_ok': True,
                'distance_to_boundary': max(0.0, dist - radius),
                'validation_mode': 'radius',
                'confidence': round(max(0.0, 1.0 - (dist / radius)), 3) if radius > 0 else 0.5,
                'spoof_flags': [],
            }

        # Otherwise do standard 2D ray-casting polygon containment
        poly = [(c.latitude, c.longitude) for c in corners]
        n = len(poly)
        inside_2d = False
        p1x, p1y = poly[0]
        for i in range(n + 1):
            p2x, p2y = poly[i % n]
            if student_lng > min(p1y, p2y):
                if student_lng <= max(p1y, p2y):
                    if student_lat <= max(p1x, p2x):
                        if p1y != p2y:
                            xinters = (student_lng - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                        if p1x == p2x or student_lat <= xinters:
                            inside_2d = not inside_2d
            p1x, p1y = p2x, p2y

        c_lat = getattr(room, 'center_lat', 0.0) or 0.0
        c_lng = getattr(room, 'center_lng', 0.0) or 0.0
        dist_from_center = haversine_distance(student_lat, student_lng, c_lat, c_lng)
        
        # Approximate size of room for radius-based boundary buffer
        effective_radius = max(
            haversine_distance(poly[0][0], poly[0][1], poly[2][0], poly[2][1]),
            haversine_distance(poly[1][0], poly[1][1], poly[3][0], poly[3][1])
        ) / 2.0
        if effective_radius < 5.0:
            effective_radius = 15.0

        is_valid = inside_2d or (dist_from_center <= (effective_radius + min(gps_accuracy * 0.5, 10.0)))

        return {
            'is_valid': is_valid,
            'inside_2d': inside_2d or (dist_from_center <= effective_radius),
            'altitude_ok': True,
            'distance_to_boundary': round(max(0.0, dist_from_center - effective_radius), 2),
            'validation_mode': 'polygon',
            'confidence': round(max(0.0, 1.0 - (dist_from_center / effective_radius)), 3) if effective_radius > 0 else 0.5,
            'spoof_flags': [],
        }
    except Exception as e:
        logger.error(f"Error checking inside room: {e}")
        return {
            'is_valid': True,
            'inside_2d': True,
            'altitude_ok': True,
            'distance_to_boundary': 0.0,
            'validation_mode': 'fallback',
            'confidence': 0.8,
            'spoof_flags': [],
        }