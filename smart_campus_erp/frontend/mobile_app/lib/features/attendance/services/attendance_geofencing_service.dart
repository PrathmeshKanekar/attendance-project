import 'dart:math' as math;

class AttendanceGeofencingService {
  /// Ray-casting algorithm (Jordan Curve Theorem) to check if a student
  /// is physically inside the classroom polygon boundaries.
  static bool checkPointInPolygon(double lat, double lng, List<Map<String, double>> polygon) {
    if (polygon.length < 3) return false;
    bool isInside = false;
    int j = polygon.length - 1;
    
    for (int i = 0; i < polygon.length; i++) {
      double xi = polygon[i]['lat'] ?? 0.0;
      double yi = polygon[i]['lng'] ?? 0.0;
      double xj = polygon[j]['lat'] ?? 0.0;
      double yj = polygon[j]['lng'] ?? 0.0;

      bool intersect = ((yi > lng) != (yj > lng)) &&
          (lat < (xj - xi) * (lng - yi) / (yj - yi) + xi);
      if (intersect) {
        isInside = !isInside;
      }
      j = i;
    }
    return isInside;
  }

  /// Calculates the shortest perpendicular physical distance (in meters) 
  /// from the student's coordinate to any edge of the room polygon.
  static double getDistanceToPolygonBoundary(double lat, double lng, List<Map<String, double>> polygon) {
    if (polygon.isEmpty) return 999.0;
    
    double minDistance = double.infinity;
    for (int i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      
      final lat1 = p1['lat'] ?? 0.0;
      final lng1 = p1['lng'] ?? 0.0;
      final lat2 = p2['lat'] ?? 0.0;
      final lng2 = p2['lng'] ?? 0.0;
      
      final dist = _pointToSegmentDistanceInMeters(lat, lng, lat1, lng1, lat2, lng2);
      if (dist < minDistance) {
        minDistance = dist;
      }
    }
    
    return minDistance;
  }

  /// Haversine distance between two coordinates in meters
  static double calculateHaversineDistance(double lat1, double lng1, double lat2, double lng2) {
    const double rEarth = 6371000.0; // Earth radius in meters
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLng = _degreesToRadians(lng2 - lng1);
    
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) * math.cos(_degreesToRadians(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return rEarth * c;
  }

  // Helper: Converts degrees to radians
  static double _degreesToRadians(double degree) {
    return degree * math.pi / 180.0;
  }

  // Helper: Distance from a point to a line segment projected in local meter offsets
  static double _pointToSegmentDistanceInMeters(
    double pLat, double pLng,
    double lat1, double lng1,
    double lat2, double lng2,
  ) {
    // Project points locally (approximate equirectangular projection centered around p1)
    final double latRad = lat1 * math.pi / 180.0;
    final double metersPerDegreeLat = 110574.0;
    final double metersPerDegreeLng = 111320.0 * math.cos(latRad);
    
    final double px = (pLng - lng1) * metersPerDegreeLng;
    final double py = (pLat - lat1) * metersPerDegreeLat;
    
    final double x2 = (lng2 - lng1) * metersPerDegreeLng;
    final double y2 = (lat2 - lat1) * metersPerDegreeLat;
    
    // Segment length squared in meters
    final double segmentLenSq = x2 * x2 + y2 * y2;
    if (segmentLenSq == 0.0) {
      return math.sqrt(px * px + py * py);
    }
    
    // Projection factor t clamped between 0 and 1
    double t = (px * x2 + py * y2) / segmentLenSq;
    t = math.max(0.0, math.min(1.0, t));
    
    // Project projection offsets
    final double dx = px - (t * x2);
    final double dy = py - (t * y2);
    
    return math.sqrt(dx * dx + dy * dy);
  }
}
