import 'dart:math' as math;
import '../room_capture_overlay.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ROOM SPATIAL RECONSTRUCTION STRUCT
// ─────────────────────────────────────────────────────────────────────────────
class ReconstructedRoom {
  final List<RoomCornerReading> orderedCorners;
  final List<CartesianPoint> localPoints; // Offsets in meters relative to centroid
  final List<double> wallLengths; // Length of each wall in meters
  final double perimeter; // Total perimeter in meters
  final double areaSqMeters; // Shoelace formula area
  final double centroidLat;
  final double centroidLng;
  final double orientationAngleDegrees; // Orientation angle relative to North
  final double qualityScore; // 0.0 to 100.0 indicator of capture precision
  final bool isClockwise;

  ReconstructedRoom({
    required this.orderedCorners,
    required this.localPoints,
    required this.wallLengths,
    required this.perimeter,
    required this.areaSqMeters,
    required this.centroidLat,
    required this.centroidLng,
    required this.orientationAngleDegrees,
    required this.qualityScore,
    required this.isClockwise,
  });

  Map<String, dynamic> toJson() => {
    'area_sq_meters': areaSqMeters,
    'perimeter': perimeter,
    'centroid': {
      'lat': centroidLat,
      'lng': centroidLng,
    },
    'orientation_degrees': orientationAngleDegrees,
    'quality_score': qualityScore,
    'wall_lengths': wallLengths,
    'corners': orderedCorners.map((e) => {
      'lat': e.latitude,
      'lng': e.longitude,
      'alt': e.altitude,
      'heading': e.heading,
      'accuracy': e.accuracy,
    }).toList(),
    'local_cartesian_points': localPoints.map((e) => {'x': e.x, 'y': e.y}).toList(),
  };
}

class CartesianPoint {
  final double x;
  final double y;
  CartesianPoint(this.x, this.y);
}

// ─────────────────────────────────────────────────────────────────────────────
// RECONSTRUCTION ENGINE
// ─────────────────────────────────────────────────────────────────────────────
class RoomReconstructionEngine {
  static const double earthRadiusMeters = 6371000.0;

  // Primary entrypoint to reconstruct room metrics
  static ReconstructedRoom reconstruct(List<RoomCornerReading> rawCorners) {
    if (rawCorners.isEmpty) {
      throw ArgumentError('At least one corner must be provided to reconstruct room.');
    }

    // 1. Calculate Centroid
    double sumLat = 0.0;
    double sumLng = 0.0;
    for (var c in rawCorners) {
      sumLat += c.latitude;
      sumLng += c.longitude;
    }
    final centroidLat = sumLat / rawCorners.length;
    final centroidLng = sumLng / rawCorners.length;

    // 2. Order corners Clockwise around centroid to ensure standard polygon connection
    final ordered = List<RoomCornerReading>.from(rawCorners);
    ordered.sort((a, b) {
      final angleA = math.atan2(a.longitude - centroidLng, a.latitude - centroidLat);
      final angleB = math.atan2(b.longitude - centroidLng, b.latitude - centroidLat);
      return angleB.compareTo(angleA); // Clockwise sort
    });

    // 3. Project to Local Cartesian space (flat meters relative to centroid)
    final localPoints = <CartesianPoint>[];
    final latRad = centroidLat * math.pi / 180.0;
    
    // Scale factors: meters per degree
    final metersPerDegreeLat = (math.pi / 180.0) * earthRadiusMeters;
    final metersPerDegreeLng = (math.pi / 180.0) * earthRadiusMeters * math.cos(latRad);

    for (var c in ordered) {
      final x = (c.longitude - centroidLng) * metersPerDegreeLng;
      final y = (c.latitude - centroidLat) * metersPerDegreeLat;
      localPoints.add(CartesianPoint(x, y));
    }

    // 4. Determine Clockwise status (shoelace sign)
    double shoelaceSum = 0.0;
    final n = localPoints.length;
    for (int i = 0; i < n; i++) {
      final next = (i + 1) % n;
      shoelaceSum += (localPoints[i].x * localPoints[next].y) - (localPoints[next].x * localPoints[i].y);
    }
    final isClockwise = shoelaceSum < 0;

    // 5. Calculate Enclosed Area (Shoelace Formula)
    final areaSqMeters = (shoelaceSum.abs()) / 2.0;

    // 6. Compute Wall Lengths & Perimeter
    final wallLengths = <double>[];
    double perimeter = 0.0;
    for (int i = 0; i < n; i++) {
      final next = (i + 1) % n;
      final dx = localPoints[next].x - localPoints[i].x;
      final dy = localPoints[next].y - localPoints[i].y;
      final len = math.sqrt(dx * dx + dy * dy);
      wallLengths.add(len);
      perimeter += len;
    }

    // 7. Calculate Principal Orientation (relative to North)
    // We base the alignment on the longest wall segment to minimize jitter
    double maxLen = -1.0;
    int longestWallIdx = 0;
    for (int i = 0; i < wallLengths.length; i++) {
      if (wallLengths[i] > maxLen) {
        maxLen = wallLengths[i];
        longestWallIdx = i;
      }
    }
    
    double orientationDeg = 0.0;
    if (n > 1) {
      final p1 = localPoints[longestWallIdx];
      final p2 = localPoints[(longestWallIdx + 1) % n];
      // Angle relative to positive Y axis (North)
      final radians = math.atan2(p2.x - p1.x, p2.y - p1.y);
      orientationDeg = (radians * 180.0 / math.pi + 360.0) % 360.0;
    }

    // 8. Compute Capture Quality Score (0.0 to 100.0)
    double quality = 100.0;
    
    // Penalty for poor GPS accuracy
    double avgAccuracy = 0.0;
    for (var c in ordered) {
      avgAccuracy += c.accuracy;
    }
    avgAccuracy /= ordered.length;
    
    if (avgAccuracy > 5.0) {
      quality -= (avgAccuracy - 5.0) * 2.0; // Penalty of 2% per meter above 5m error
    }

    // Penalty for non-convexity (if 4 corners)
    if (n == 4) {
      bool isConvex = true;
      for (int i = 0; i < 4; i++) {
        final p0 = localPoints[i];
        final p1 = localPoints[(i + 1) % 4];
        final p2 = localPoints[(i + 2) % 4];
        final crossProduct = (p1.x - p0.x) * (p2.y - p1.y) - (p1.y - p0.y) * (p2.x - p1.x);
        if (i == 0) {
          final firstSign = crossProduct > 0;
          isConvex = firstSign;
        } else {
          if ((crossProduct > 0) != isConvex) {
            isConvex = false;
            break;
          }
        }
      }
      if (!isConvex) {
        quality -= 30.0; // 30% penalty for concave/crossing shapes
      }
    }

    quality = quality.clamp(10.0, 100.0); // Hard floor of 10% quality

    return ReconstructedRoom(
      orderedCorners: ordered,
      localPoints: localPoints,
      wallLengths: wallLengths,
      perimeter: perimeter,
      areaSqMeters: areaSqMeters,
      centroidLat: centroidLat,
      centroidLng: centroidLng,
      orientationAngleDegrees: orientationDeg,
      qualityScore: quality,
      isClockwise: isClockwise,
    );
  }
}
