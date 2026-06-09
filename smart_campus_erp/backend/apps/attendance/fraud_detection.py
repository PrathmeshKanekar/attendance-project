import math

def detect_impossible_movement(
    prev_lat, prev_lng, prev_time,
    curr_lat, curr_lng, curr_time,
) -> dict:
    """
    Detects teleportation — movement faster than humanly possible.
    Returns {'is_suspicious': bool, 'speed_mps': float, 'reason': str}
    """
    if not all([prev_lat, prev_lng, prev_time, curr_lat, curr_lng, curr_time]):
        return {'is_suspicious': False, 'speed_mps': 0.0, 'reason': 'insufficient_data'}

    elapsed_sec = (curr_time - prev_time).total_seconds()
    if elapsed_sec <= 0:
        return {'is_suspicious': False, 'speed_mps': 0.0, 'reason': 'zero_time_delta'}

    R = 6_371_000.0
    lat1, lat2 = math.radians(prev_lat), math.radians(curr_lat)
    dlat = math.radians(curr_lat - prev_lat)
    dlng = math.radians(curr_lng - prev_lng)
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlng / 2) ** 2
    distance_m = R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    speed_mps = distance_m / elapsed_sec
    MAX_HUMAN_SPEED = 12.0  # ~43 km/h — sprinting limit

    if speed_mps > MAX_HUMAN_SPEED:
        return {
            'is_suspicious': True,
            'speed_mps': speed_mps,
            'reason': f'Movement speed {speed_mps:.1f} m/s exceeds human limit',
        }
    return {'is_suspicious': False, 'speed_mps': speed_mps, 'reason': 'normal'}


def check_gps_accuracy_threshold(accuracy: float, threshold: float = 50.0) -> bool:
    """Returns True if GPS accuracy is acceptable (lower = better)."""
    return accuracy <= threshold


def detect_developer_mode_flags(security_flags: dict) -> bool:
    """
    Checks Flutter-reported security flags for developer/mock indicators.
    Flags are set by the Flutter anti-spoofing service.
    """
    if not security_flags:
        return False
    suspicious_keys = [
        'is_mock_location', 'developer_mode', 'usb_debugging',
        'rooted', 'emulator', 'allow_mock_location',
    ]
    return any(security_flags.get(k, False) for k in suspicious_keys)
