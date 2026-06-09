import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Ray-casting point-in-polygon verification algorithm.
/// Returns true if [point] is inside the closed polygon defined by [polygon].
bool isPointInsidePolygon(LatLng point, List<LatLng> polygon) {
  if (polygon.length < 3) return false;

  final double pLat = point.latitude;
  final double pLng = point.longitude;

  int intersections = 0;
  final int n = polygon.length;

  for (int i = 0; i < n; i++) {
    final LatLng a = polygon[i];
    final LatLng b = polygon[(i + 1) % n];

    final double aLat = a.latitude;
    final double aLng = a.longitude;
    final double bLat = b.latitude;
    final double bLng = b.longitude;

    // Check if a horizontal ray from point crosses this edge
    if (((aLat <= pLat && pLat < bLat) ||
         (bLat <= pLat && pLat < aLat)) &&
        (pLng < (bLng - aLng) * (pLat - aLat) / (bLat - aLat) + aLng)) {
      intersections++;
    }
  }

  return (intersections % 2) == 1;
}

/// Distance from point p to line segment (a, b) in meters using local flat-earth approximation.
double distanceToSegment(LatLng p, LatLng a, LatLng b) {
  final double latMid = (a.latitude + b.latitude) / 2.0;
  const double metersPerDegreeLat = 110574.0;
  final double metersPerDegreeLng = 111320.0 * math.cos(latMid * math.pi / 180.0);

  final double px = p.longitude * metersPerDegreeLng;
  final double py = p.latitude * metersPerDegreeLat;
  final double ax = a.longitude * metersPerDegreeLng;
  final double ay = a.latitude * metersPerDegreeLat;
  final double bx = b.longitude * metersPerDegreeLng;
  final double by = b.latitude * metersPerDegreeLat;

  final double l2 = (ax - bx) * (ax - bx) + (ay - by) * (ay - by);
  if (l2 == 0) return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));

  double t = ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / l2;
  t = math.max(0.0, math.min(1.0, t));

  final double projx = ax + t * (bx - ax);
  final double projy = ay + t * (by - ay);

  return math.sqrt((px - projx) * (px - projx) + (py - projy) * (py - projy));
}

/// Minimum perpendicular distance in meters from point p to any boundary segment of the polygon.
double distanceToPolygonBoundary(LatLng p, List<LatLng> polygon) {
  if (polygon.length < 3) return double.infinity;
  double minDistance = double.infinity;
  int j = polygon.length - 1;
  for (int i = 0; i < polygon.length; i++) {
    final double dist = distanceToSegment(p, polygon[i], polygon[j]);
    if (dist < minDistance) minDistance = dist;
    j = i;
  }
  return minDistance;
}

/// Parse polygon corners from various virtual room representation formats.
///
/// Handles:
///   - `Map` with `corner_coordinates` or `corners` key (list of {lat, lng} maps)
///   - `VirtualRoomModel` with `.corners` property (list of RoomCornerModel)
///   - Fallback to `boundary_geojson` in GeoJSON [lng, lat] format
List<LatLng> parsePolygonFromRoom(dynamic roomData) {
  if (roomData == null) return [];

  // ── 1. Try corner_coordinates / corners list ──────────────────────────────
  List? list;
  if (roomData is Map) {
    list = (roomData['corner_coordinates'] as List?) ?? (roomData['corners'] as List?);
  } else {
    // VirtualRoomModel or similar typed object
    try {
      list = roomData.corners;
    } catch (_) {}
  }

  if (list != null && list.isNotEmpty) {
    try {
      final List<LatLng> points = [];
      for (final item in list) {
        double lat = 0.0;
        double lng = 0.0;
        if (item is Map) {
          // From raw JSON maps: {"lat": ..., "lng": ...} or {"latitude": ..., "longitude": ...}
          lat = ((item['latitude'] ?? item['lat'] ?? 0.0) as num).toDouble();
          lng = ((item['longitude'] ?? item['lng'] ?? 0.0) as num).toDouble();
        } else {
          // From typed model objects (e.g. RoomCornerModel)
          try {
            lat = (item.latitude as num).toDouble();
            lng = (item.longitude as num).toDouble();
          } catch (_) {}
        }
        if (lat != 0.0 || lng != 0.0) {
          points.add(LatLng(lat, lng));  // LatLng(latitude, longitude) — correct order
        }
      }
      if (points.length >= 3) {
        return points;
      }
    } catch (_) {}
  }

  // ── 2. Fallback to boundary_geojson ───────────────────────────────────────
  dynamic geojson;
  if (roomData is Map) {
    geojson = roomData['boundary_geojson'];
  } else {
    try {
      geojson = roomData.boundaryGeoJson;
    } catch (_) {}
  }

  if (geojson is Map && geojson.isNotEmpty) {
    // Handle Feature wrapper: {"type": "Feature", "geometry": {...}}
    Map<String, dynamic> geom = Map<String, dynamic>.from(geojson);
    if (geojson.containsKey('geometry') && geojson['geometry'] is Map) {
      geom = Map<String, dynamic>.from(geojson['geometry'] as Map);
    }

    if (geom.containsKey('coordinates') && geom['coordinates'] is List) {
      try {
        final coordinates = geom['coordinates'][0] as List;
        int takeCount = coordinates.length;
        // GeoJSON polygons close the ring — remove duplicate closing point
        if (coordinates.length > 1 &&
            coordinates.first[0] == coordinates.last[0] &&
            coordinates.first[1] == coordinates.last[1]) {
          takeCount = coordinates.length - 1;
        }
        final List<LatLng> pts = coordinates
          .take(takeCount)
          .map((c) => LatLng(
            (c[1] as num).toDouble(),  // GeoJSON: [lng, lat] → index 1 is latitude
            (c[0] as num).toDouble(),  // GeoJSON: [lng, lat] → index 0 is longitude
          ))
          .toList();
        if (pts.length >= 3) {
          return pts;
        }
      } catch (_) {}
    }
  }

  return [];
}

/// Debug verification — call once on startup or room select to validate the algorithm.
/// Prints results to debug console. Remove before production build.
void verifyGeofenceAlgorithm() {
  final polygon = [
    LatLng(16.6729439, 74.2053677),
    LatLng(16.6729439, 74.2055552),
    LatLng(16.6727631, 74.2055552),
    LatLng(16.6727631, 74.2053677),
  ];

  // MUST print true — user was physically inside
  final insideTest = isPointInsidePolygon(
    LatLng(16.672820, 74.205481), polygon);
  debugPrint('🔬 INSIDE TEST  (expect true):  $insideTest');

  // MUST print false — point clearly outside
  final outsideTest = isPointInsidePolygon(
    LatLng(16.673500, 74.207000), polygon);
  debugPrint('🔬 OUTSIDE TEST (expect false): $outsideTest');

  // MUST print false — null island
  final nullTest = isPointInsidePolygon(
    LatLng(0.0, 0.0), polygon);
  debugPrint('🔬 NULL ISLAND  (expect false): $nullTest');

  // Distance to boundary for inside point
  final dist = distanceToPolygonBoundary(
    LatLng(16.672820, 74.205481), polygon);
  debugPrint('🔬 DISTANCE TO BOUNDARY: ${dist.toStringAsFixed(2)} m');

  assert(insideTest == true,  'ALGORITHM BUG: Inside test failed!');
  assert(outsideTest == false, 'ALGORITHM BUG: Outside test failed!');
  assert(nullTest == false,    'ALGORITHM BUG: Null island test failed!');
  debugPrint('✅ All geofence algorithm verification tests PASSED.');
}
