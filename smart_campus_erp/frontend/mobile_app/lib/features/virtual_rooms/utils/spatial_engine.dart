// spatial_engine.dart
// ─────────────────────────────────────────────────────────────────────────────
// Production-grade client-side Spatial Engine for 3D coordinate mathematics.
// Perfectly mirrors the backend geo_utils.py implementation.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

const double earthRadiusM = 6371000.0;
const double latToM = 111111.0;

double lngToM(double latDeg) {
  return latToM * math.cos(latDeg * math.pi / 180.0);
}

/// Immutable 3D Vector for local Coordinate Frame (ENU).
class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3(this.x, this.y, this.z);

  double get magnitude => math.sqrt(x * x + y * y + z * z);

  Vec3 normalized() {
    final m = magnitude;
    if (m < 1e-9) {
      throw StateError("Cannot normalize a near-zero vector");
    }
    return Vec3(x / m, y / m, z / m);
  }

  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  Vec3 cross(Vec3 other) {
    return Vec3(
      y * other.z - z * other.y,
      z * other.x - x * other.z,
      x * other.y - y * other.x,
    );
  }

  Map<String, double> toMap() => {'x': x, 'y': y, 'z': z, 'mag': magnitude};

  factory Vec3.fromMap(Map<String, dynamic> m) {
    return Vec3(
      (m['x'] as num? ?? 0.0).toDouble(),
      (m['y'] as num? ?? 0.0).toDouble(),
      (m['z'] as num? ?? 0.0).toDouble(),
    );
  }

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

/// Computes local ENU (East-North-Up) vector relative to origin.
Vec3 enuVector({
  required double originLat,
  required double originLng,
  required double originAlt,
  required double targetLat,
  required double targetLng,
  required double targetAlt,
}) {
  final east = (targetLng - originLng) * lngToM(originLat);
  final north = (targetLat - originLat) * latToM;
  final up = targetAlt - originAlt;
  return Vec3(east, north, up);
}

/// Great-circle distance using Haversine formula (meters).
double haversineDistance(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = lat1 * math.pi / 180.0;
  final phi2 = lat2 * math.pi / 180.0;
  final dphi = (lat2 - lat1) * math.pi / 180.0;
  final dlamb = (lng2 - lng1) * math.pi / 180.0;
  
  final a = math.sin(dphi / 2) * math.sin(dphi / 2) +
      math.cos(phi1) * math.cos(phi2) * math.sin(dlamb / 2) * math.sin(dlamb / 2);
  
  return 2.0 * earthRadiusM * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));
}

/// Shoelace formula in local ENU coordinates.
double polygonAreaM2(List<Map<String, double>> corners) {
  if (corners.length < 3) return 0.0;
  
  final originLat = corners[0]['lat']!;
  final originLng = corners[0]['lng']!;
  final originAlt = corners[0]['alt'] ?? 0.0;

  final points = corners.map((c) {
    final v = enuVector(
      originLat: originLat,
      originLng: originLng,
      originAlt: originAlt,
      targetLat: c['lat']!,
      targetLng: c['lng']!,
      targetAlt: c['alt'] ?? 0.0,
    );
    return [v.x, v.y];
  }).toList();

  double area = 0.0;
  final n = points.length;
  for (int i = 0; i < n; i++) {
    final j = (i + 1) % n;
    area += points[i][0] * points[j][1];
    area -= points[j][0] * points[i][1];
  }
  return area.abs() / 2.0;
}

/// Checks if polygon edges intersect self (invalid boundary).
bool checkSelfIntersection(List<Map<String, double>> corners) {
  if (corners.length < 4) return false;

  final originLat = corners[0]['lat']!;
  final originLng = corners[0]['lng']!;
  final originAlt = corners[0]['alt'] ?? 0.0;

  final points = corners.map((c) {
    final v = enuVector(
      originLat: originLat,
      originLng: originLng,
      originAlt: originAlt,
      targetLat: c['lat']!,
      targetLng: c['lng']!,
      targetAlt: c['alt'] ?? 0.0,
    );
    return [v.x, v.y];
  }).toList();

  final n = points.length;
  final edges = <List<List<double>>>[];
  for (int i = 0; i < n; i++) {
    edges.add([points[i], points[(i + 1) % n]]);
  }

  bool ccw(List<double> a, List<double> b, List<double> c) {
    return (c[1] - a[1]) * (b[0] - a[0]) > (b[1] - a[1]) * (c[0] - a[0]);
  }

  bool segmentsIntersect(List<double> a, List<double> b, List<double> c, List<double> d) {
    return ccw(a, c, d) != ccw(b, c, d) && ccw(a, b, c) != ccw(a, b, d);
  }

  for (int i = 0; i < n; i++) {
    for (int j = i + 2; j < n; j++) {
      if (i == 0 && j == n - 1) continue; // sharing a vertex
      if (segmentsIntersect(edges[i][0], edges[i][1], edges[j][0], edges[j][1])) {
        return true;
      }
    }
  }
  return false;
}

/// Ray-casting point in polygon algorithm.
bool pointInPolygon(double px, double py, List<List<double>> polygonPoints) {
  bool inside = false;
  int n = polygonPoints.length;
  int j = n - 1;
  
  for (int i = 0; i < n; i++) {
    final xi = polygonPoints[i][0];
    final yi = polygonPoints[i][1];
    final xj = polygonPoints[j][0];
    final yj = polygonPoints[j][1];
    
    if (((yi > py) != (yj > py)) &&
        (px < (xj - xi) * (py - yi) / (yj - yi) + xi)) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}

/// Calculates area of a polygon defined by WGS84 coordinates.
double calculatePolygonArea(List<Map<String, double>> corners) {
  return polygonAreaM2(corners);
}

/// Calculates room dimensions: length, width, height, and perimeter.
Map<String, double> calculateRoomDimensions(List<Map<String, double>> corners) {
  if (corners.length < 4) {
    return {"length": 0.0, "width": 0.0, "height": 0.0, "perimeter": 0.0};
  }
  final c1 = corners[0];
  final c2 = corners[1];
  final c3 = corners[2];
  final c4 = corners[3];

  final length = haversineDistance(c1['lat']!, c1['lng']!, c2['lat']!, c2['lng']!);
  final width = haversineDistance(c1['lat']!, c1['lng']!, c4['lat']!, c4['lng']!);

  final alts = corners.map((c) => c['alt'] ?? 0.0).toList();
  double height = alts.reduce(math.max) - alts.reduce(math.min);
  if (height < 0.5) {
    height = 3.0;
  }

  final d12 = haversineDistance(c1['lat']!, c1['lng']!, c2['lat']!, c2['lng']!);
  final d23 = haversineDistance(c2['lat']!, c2['lng']!, c3['lat']!, c3['lng']!);
  final d34 = haversineDistance(c3['lat']!, c3['lng']!, c4['lat']!, c4['lng']!);
  final d41 = haversineDistance(c4['lat']!, c4['lng']!, c1['lat']!, c1['lng']!);
  final perimeter = d12 + d23 + d34 + d41;

  return {
    "length": length,
    "width": width,
    "height": height,
    "perimeter": perimeter,
  };
}

/// Calculates average coordinates for room center.
Map<String, double> calculateRoomCenter(List<Map<String, double>> corners) {
  if (corners.isEmpty) {
    return {"lat": 0.0, "lng": 0.0};
  }
  double sumLat = 0.0;
  double sumLng = 0.0;
  for (final c in corners) {
    sumLat += c['lat']!;
    sumLng += c['lng']!;
  }
  return {
    "lat": sumLat / corners.length,
    "lng": sumLng / corners.length,
  };
}
