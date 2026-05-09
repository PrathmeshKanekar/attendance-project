"""
Real Haversine geofencing utilities.
No mocking. No hardcoded values.
All calculations use real spherical earth geometry.
"""
import math


def haversine_distance(lat1: float, lng1: float,
                       lat2: float, lng2: float) -> float:
    """
    Calculate the great-circle distance between two GPS points.
    Returns distance in METERS.
    Uses the Haversine formula (accurate for short distances).
    """
    R = 6_371_000.0  # Earth radius in meters

    phi1     = math.radians(float(lat1))
    phi2     = math.radians(float(lat2))
    delta_phi    = math.radians(float(lat2) - float(lat1))
    delta_lambda = math.radians(float(lng2) - float(lng1))

    a = (math.sin(delta_phi / 2) ** 2
         + math.cos(phi1) * math.cos(phi2)
         * math.sin(delta_lambda / 2) ** 2)

    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c


def check_inside_room(lat: float, lng: float,
                      altitude: float, room,
                      horizontal_accuracy: float = 10.0,
                      custom_radius: float = None) -> dict:
    """
    Check if a GPS point is inside a boundary with accuracy awareness.

    Args:
        lat, lng            : Student's current GPS coordinates
        altitude            : Student's altitude in meters
        room                : VirtualRoom model instance (for center coords)
        horizontal_accuracy : GPS accuracy in meters
        custom_radius       : If provided, overrides room.radius_meters (DYNAMIC RADIUS)

    Returns:
        {
          'inside'              : bool,
          'inside_2d'           : bool,
          'altitude_ok'         : bool,
          'distance_from_center': float,
          'distance_to_boundary': float,
          'radius_used'         : float,
        }
    """
    distance = haversine_distance(
        lat, lng,
        float(room.center_lat),
        float(room.center_lng),
    )

    # USE DYNAMIC RADIUS FROM SESSION
    base_radius = float(custom_radius if custom_radius is not None else room.radius_meters)

    # ACCURACY-AWARE RADIUS:
    # Add a 'slack' based on accuracy to prevent false rejections.
    accuracy_slack = min(horizontal_accuracy * 0.5, 15.0)
    effective_radius = base_radius + accuracy_slack + 5.0  # +5m fixed buffer

    inside_2d = distance <= effective_radius

    # Altitude check: skip if room uses factory defaults (0, 50)
    room_min = float(room.min_altitude)
    room_max = float(room.max_altitude)
    uses_default_altitude = (room_min == 0.0 and room_max == 50.0)

    if uses_default_altitude:
        altitude_ok = True
    else:
        # ── ROBUST ALTITUDE VALIDATION ──
        # Mobile GPS altitude is notoriously inaccurate (often ±50m).
        # We use a very generous 50m buffer to avoid false rejections on different floors.
        # Additionally, if horizontal accuracy is poor, we assume altitude is also unreliable.
        alt_slack = 50.0
        if horizontal_accuracy > 20.0:
            alt_slack = 80.0  # Extremely loose if GPS is poor
            
        altitude_ok = (room_min - alt_slack) <= float(altitude) <= (room_max + alt_slack)

    # Logging for diagnostics
    print(
        f"GEO_VALIDATION: Student at ({lat}, {lng}, alt={altitude}) | "
        f"Accuracy: {horizontal_accuracy}m | "
        f"Target Center: ({room.center_lat}, {room.center_lng}) | "
        f"Distance: {distance:.2f}m | "
        f"Base Radius: {base_radius}m | "
        f"Effective Radius: {effective_radius:.2f}m | "
        f"Alt OK: {altitude_ok} (Range: {room_min-alt_slack:.1f} to {room_max+alt_slack:.1f})"
    )

    return {
        'inside'              : inside_2d and altitude_ok,
        'inside_2d'           : inside_2d,
        'altitude_ok'         : altitude_ok,
        'distance_from_center': round(distance, 2),
        'distance_to_boundary': round(
            max(0.0, distance - effective_radius), 2
        ),
        'radius_used'           : base_radius,
        'effective_radius'      : round(effective_radius, 2),
        'accuracy_slack_applied': round(accuracy_slack + 5.0, 2),
    }


def detect_gps_spoofing(lat: float, lng: float,
                        prev_lat, prev_lng,
                        elapsed_seconds: float) -> dict:
    """
    Basic GPS spoofing detection based on physically impossible speed.
    Returns {'spoofed': bool, 'reason': str}
    """
    if prev_lat is None or prev_lng is None:
        return {'spoofed': False, 'reason': 'First location record'}

    distance = haversine_distance(lat, lng, prev_lat, prev_lng)
    elapsed  = max(float(elapsed_seconds), 1.0)
    speed    = distance / elapsed  # meters per second

    # > 55 m/s = > 200 km/h — impossible on foot
    if speed > 55.0:
        return {
            'spoofed': True,
            'reason' : (
                f'Unrealistic movement speed: {speed:.1f} m/s '
                f'({speed * 3.6:.1f} km/h)'
            ),
        }

    return {'spoofed': False, 'reason': 'Normal movement speed'}
