// data/models/virtual_room_model.dart
// ─────────────────────────────────────────────────────────────────────────────
// Strongly-typed model for Virtual Room API responses.
// ─────────────────────────────────────────────────────────────────────────────

class VirtualRoom {
  final String id;
  final String name;
  final String building;
  final int floorNumber;
  final String department;
  final int capacity;
  final bool hasPolygon;
  final int cornerCount;
  final double? length;
  final double? width;
  final double? area;
  final double? centerLat;
  final double? centerLng;
  final double radiusMeters;
  final bool isActive;
  final List<dynamic>? normalizedCoordinates;
  final List<dynamic>? orientationMatrix;
  final Map<String, dynamic>? roomDimensions;
  final double? magneticHeading;
  final double? minAltitude;
  final double? maxAltitude;
  final String? createdByName;

  VirtualRoom({
    required this.id,
    required this.name,
    required this.building,
    required this.floorNumber,
    required this.department,
    required this.capacity,
    required this.hasPolygon,
    required this.cornerCount,
    this.length,
    this.width,
    this.area,
    this.centerLat,
    this.centerLng,
    required this.radiusMeters,
    required this.isActive,
    this.normalizedCoordinates,
    this.orientationMatrix,
    this.roomDimensions,
    this.magneticHeading,
    this.minAltitude,
    this.maxAltitude,
    this.createdByName,
  });

  factory VirtualRoom.fromJson(Map<String, dynamic> json) {
    return VirtualRoom(
      id:                     (json['id'] ?? json['uuid'] ?? '').toString(),
      name:                   (json['name'] ?? '').toString(),
      building:               (json['building'] ?? '').toString(),
      floorNumber:            (json['floor_number'] as int?) ?? 0,
      department:             (json['department'] ?? '').toString(),
      capacity:               (json['capacity'] as int?) ?? 0,
      hasPolygon:             json['has_polygon'] == true || json['use_polygon'] == true,
      cornerCount:            (json['corner_count'] as int?) ?? 0,
      length:                 (json['length'] as num?)?.toDouble(),
      width:                  (json['width'] as num?)?.toDouble(),
      area:                   (json['area'] as num?)?.toDouble(),
      centerLat:              (json['center_lat'] as num?)?.toDouble(),
      centerLng:              (json['center_lng'] as num?)?.toDouble(),
      radiusMeters:           (json['radius_meters'] as num? ?? 30.0).toDouble(),
      isActive:               json['is_active'] ?? true,
      normalizedCoordinates:  json['normalized_coordinates'] as List<dynamic>?,
      orientationMatrix:      json['orientation_matrix'] as List<dynamic>?,
      roomDimensions:         json['room_dimensions'] as Map<String, dynamic>?,
      magneticHeading:        (json['magnetic_heading'] as num?)?.toDouble(),
      minAltitude:            (json['min_altitude'] as num?)?.toDouble(),
      maxAltitude:            (json['max_altitude'] as num?)?.toDouble(),
      createdByName:          json['created_by_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id':                     id,
    'name':                   name,
    'building':               building,
    'floor_number':           floorNumber,
    'department':             department,
    'capacity':               capacity,
    'has_polygon':            hasPolygon,
    'corner_count':           cornerCount,
    'length':                 length,
    'width':                  width,
    'area':                   area,
    'center_lat':             centerLat,
    'center_lng':             centerLng,
    'radius_meters':          radiusMeters,
    'is_active':              isActive,
    'normalized_coordinates': normalizedCoordinates,
    'orientation_matrix':     orientationMatrix,
    'room_dimensions':        roomDimensions,
    'magnetic_heading':       magneticHeading,
    'min_altitude':           minAltitude,
    'max_altitude':           maxAltitude,
  };
}
