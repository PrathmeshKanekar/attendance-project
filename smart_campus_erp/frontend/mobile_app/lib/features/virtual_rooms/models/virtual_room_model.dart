class VirtualRoomModel {
  final String id;
  final String name;
  final String building;
  final String department;
  final int floorNumber;
  final int capacity;
  final double centerLat;
  final double centerLng;
  final String createdByName;
  final String createdAt;
  final List<RoomCornerModel> corners;
  final bool hasPolygon;

  VirtualRoomModel({
    required this.id,
    required this.name,
    required this.building,
    required this.department,
    required this.floorNumber,
    required this.capacity,
    required this.centerLat,
    required this.centerLng,
    required this.createdByName,
    required this.createdAt,
    required this.corners,
    required this.hasPolygon,
  });

  factory VirtualRoomModel.fromJson(Map<String, dynamic> json) {
    var cornersList = json['corners'] as List? ?? [];
    List<RoomCornerModel> corners = cornersList
        .map((c) => RoomCornerModel.fromJson(c as Map<String, dynamic>))
        .toList();

    return VirtualRoomModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['room_name'] as String? ?? '',
      building: json['building'] as String? ?? '',
      department: json['department'] as String? ?? '',
      floorNumber: json['floor_number'] as int? ?? json['floor'] as int? ?? 0,
      capacity: json['capacity'] as int? ?? 60,
      centerLat: (json['center_lat'] as num?)?.toDouble() ?? 0.0,
      centerLng: (json['center_lng'] as num?)?.toDouble() ?? 0.0,
      createdByName: json['created_by_name'] as String? ?? 'Unknown',
      createdAt: json['created_at'] as String? ?? '',
      corners: corners,
      hasPolygon: json['has_polygon'] as bool? ?? (corners.length >= 4),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'building': building,
      'department': department,
      'floor_number': floorNumber,
      'capacity': capacity,
      'center_lat': centerLat,
      'center_lng': centerLng,
      'corners': corners.map((c) => c.toJson()).toList(),
    };
  }
}

class RoomCornerModel {
  final int cornerIndex;
  final double latitude;
  final double longitude;
  final double altitude;
  final double heading;
  final double accuracy;

  RoomCornerModel({
    required this.cornerIndex,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.heading,
    required this.accuracy,
  });

  factory RoomCornerModel.fromJson(Map<String, dynamic> json) {
    return RoomCornerModel(
      cornerIndex: json['corner_index'] as int? ?? 0,
      latitude: (json['latitude'] as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? (json['lng'] as num?)?.toDouble() ?? 0.0,
      altitude: (json['altitude'] as num?)?.toDouble() ?? (json['alt'] as num?)?.toDouble() ?? 0.0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0.0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'corner_index': cornerIndex,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'heading': heading,
      'accuracy': accuracy,
    };
  }
}
