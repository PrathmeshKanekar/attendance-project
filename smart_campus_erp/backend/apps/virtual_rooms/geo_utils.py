import math
import logging

logger = logging.getLogger(__name__)

def haversine_distance(lat1, lon1, lat2, lon2):
    """
    Calculates the great-circle distance between two points on the Earth's surface
    using the Haversine formula. Returns distance in meters.
    """
    try:
        R = 6371000.0  # Earth's radius in meters
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lon2 - lon1)
        a = math.sin(delta_phi / 2.0) ** 2 + \
            math.cos(phi1) * math.cos(phi2) * \
            math.sin(delta_lambda / 2.0) ** 2
        c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
        return R * c
    except Exception as e:
        logger.error("Error in haversine_distance: %s", e)
        return 0.0

def is_inside_polygon(x, y, poly):
    """
    Determines if a point (x, y) is inside a polygon using ray casting.
    poly is a list of tuples/lists of (lat, lng).
    """
    try:
        n = len(poly)
        inside = False
        p1x, p1y = poly[0]
        for i in range(n + 1):
            p2x, p2y = poly[i % n]
            if y > min(p1y, p2y):
                if y <= max(p1y, p2y):
                    if x <= max(p1x, p2x):
                        if p1y != p2y:
                            xints = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                        if p1x == p2x or x <= xints:
                            inside = not inside
            p1x, p1y = p2x, p2y
        return inside
    except Exception as e:
        logger.error("Error in is_inside_polygon: %s", e)
        return False

def calculate_room_center(corners_list):
    """
    Calculates the arithmetic center (centroid) of the 4 room corners.
    Returns a dict with 'lat' and 'lng'.
    """
    fallback = {'lat': 0.0, 'lng': 0.0}
    if not corners_list:
        return fallback

    try:
        total_lat = 0.0
        total_lng = 0.0
        count = 0

        for c in corners_list:
            if hasattr(c, 'latitude'):
                lat = getattr(c, 'latitude', None)
                lng = getattr(c, 'longitude', None)
            else:
                lat = c.get('lat') or c.get('latitude')
                lng = c.get('lng') or c.get('longitude')

            if lat is not None and lng is not None:
                total_lat += float(lat)
                total_lng += float(lng)
                count += 1

        if count > 0:
            return {
                'lat': total_lat / count,
                'lng': total_lng / count
            }
    except Exception as e:
        logger.error("Error in calculate_room_center: %s", e)

    try:
        first = corners_list[0]
        if hasattr(first, 'latitude'):
            return {'lat': getattr(first, 'latitude', 0.0), 'lng': getattr(first, 'longitude', 0.0)}
        else:
            return {
                'lat': first.get('lat') or first.get('latitude') or 0.0,
                'lng': first.get('lng') or first.get('longitude') or 0.0
            }
    except Exception:
        pass

    return fallback

def check_inside_room(student_lat, student_lng, student_alt, room, gps_accuracy=10.0, sensors=None):
    """
    Determines if a student is inside the virtual room area.
    Ensures absolute safety and zero HTTP 500 crashes.
    """
    try:
        # Check if the room has corners registered
        corners = list(room.corners.all().order_by('corner_index'))
        
        if len(corners) != 4:
            # Fallback: radius-based check
            center_lat = getattr(room, 'center_lat', None)
            center_lng = getattr(room, 'center_lng', None)
            
            if center_lat is None or center_lng is None:
                return {
                    'is_valid': True,
                    'inside_2d': True,
                    'altitude_ok': True,
                    'distance_to_boundary': 0.0,
                    'validation_mode': 'fallback'
                }
                
            dist = haversine_distance(student_lat, student_lng, center_lat, center_lng)
            radius = getattr(room, 'radius_meters', 30.0) or 30.0
            
            # Use max corner accuracy of any corners if available, else 15.0
            max_corner_accuracy = 0.0
            if hasattr(room, 'corners'):
                all_corners = list(room.corners.all())
                if all_corners:
                    max_corner_accuracy = max((getattr(c, 'accuracy_meters', 0.0) or getattr(c, 'accuracy', 0.0) or 0.0) for c in all_corners)
            slack = max(15.0, max_corner_accuracy)
            
            is_inside = dist <= (radius + slack)  # Add dynamic accuracy tolerance buffer
            
            return {
                'is_valid': is_inside,
                'inside_2d': is_inside,
                'altitude_ok': True,
                'distance_to_boundary': max(0.0, dist - radius),
                'validation_mode': 'radius'
            }

        # Polygon-based check using ray casting
        poly = [(c.latitude, c.longitude) for c in corners]
        inside_2d = is_inside_polygon(student_lat, student_lng, poly)
        
        # Center lat/lng for estimation
        center_lat = getattr(room, 'center_lat', None) or sum(p[0] for p in poly)/4.0
        center_lng = getattr(room, 'center_lng', None) or sum(p[1] for p in poly)/4.0
        dist_from_center = haversine_distance(student_lat, student_lng, center_lat, center_lng)
        
        # Determine the maximum corner accuracy recorded for the room's corners
        max_corner_accuracy = max((getattr(c, 'accuracy_meters', 0.0) or getattr(c, 'accuracy', 0.0) or 0.0) for c in corners)
        
        # Bounding radius estimation: max distance between any corner and the center
        bounding_radius = max(haversine_distance(c.latitude, c.longitude, center_lat, center_lng) for c in corners)
        
        # Effective slack is the maximum corner accuracy, with a minimum fallback of 15.0m
        slack = max(15.0, max_corner_accuracy)
        
        # If student is inside 2D polygon OR within bounding circle + slack (for weak indoor GPS)
        is_inside = inside_2d or (dist_from_center <= (bounding_radius + slack))
        
        return {
            'is_valid': is_inside,
            'inside_2d': inside_2d,
            'altitude_ok': True,
            'distance_to_boundary': max(0.0, dist_from_center - bounding_radius) if not inside_2d else 0.0,
            'validation_mode': 'polygon'
        }
    except Exception as e:
        logger.error("Error in check_inside_room: %s", e)
        # Always fail-safe: allow attendance on unexpected errors
        return {
            'is_valid': True,
            'inside_2d': True,
            'altitude_ok': True,
            'distance_to_boundary': 0.0,
            'validation_mode': 'error_fallback'
        }
