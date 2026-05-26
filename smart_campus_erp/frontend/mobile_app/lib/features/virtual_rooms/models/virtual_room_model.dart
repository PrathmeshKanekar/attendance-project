class RoomCornerModel {
  final String id;
  final int cornerIndex;
  final double latitude;
  final double longitude;
  final double altitude;
  final double heading;
  final double accuracy;
  final Map<String, dynamic> sensorTelemetry;

  const RoomCornerModel({
    required this.id,
    required this.cornerIndex,
    required this.latitude,
    required this.longitude,
    this.altitude = 0.0,
    this.heading = 0.0,
    this.accuracy = 0.0,
    this.sensorTelemetry = const {},
  });

  factory RoomCornerModel.fromJson(Map<String, dynamic> json) {
    return RoomCornerModel(
      id: json['id']?.toString() ?? '',
      cornerIndex: json['corner_index'] as int? ?? 1,
      latitude: (json['latitude'] as num? ?? json['lat'] as num? ?? 0.0).toDouble(),
      longitude: (json['longitude'] as num? ?? json['lng'] as num? ?? 0.0).toDouble(),
      altitude: (json['altitude'] as num? ?? json['alt'] as num? ?? 0.0).toDouble(),
      heading: (json['heading'] as num? ?? 0.0).toDouble(),
      accuracy: (json['accuracy'] as num? ?? 0.0).toDouble(),
      sensorTelemetry: json['sensor_telemetry'] as Map<String, dynamic>? ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'corner_index': cornerIndex,
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'heading': heading,
    'accuracy': accuracy,
    'sensor_telemetry': sensorTelemetry,
  };
}

class VirtualRoomModel {
  final String id;
  final String college;
  final String name;
  final String building;
  final String department;
  final int floorNumber;
  final int capacity;
  final double? centerLat;
  final double? centerLng;
  
  // Spatial Reconstruction fields from Backend API
  final double areaSqMeters;
  final double perimeterMeters;
  final double orientationDegrees;
  final double reconstructionQuality;
  final Map<String, dynamic> spatialMetadata;

  final String? createdBy;
  final String createdByName;
  final DateTime? createdAt;
  final bool isActive;
  final List<RoomCornerModel> corners;
  final bool hasPolygon;

  const VirtualRoomModel({
    required this.id,
    required this.college,
    required this.name,
    this.building = '',
    this.department = '',
    this.floorNumber = 0,
    this.capacity = 60,
    this.centerLat,
    this.centerLng,
    this.areaSqMeters = 0.0,
    this.perimeterMeters = 0.0,
    this.orientationDegrees = 0.0,
    this.reconstructionQuality = 100.0,
    this.spatialMetadata = const {},
    this.createdBy,
    this.createdByName = 'Unknown',
    this.createdAt,
    this.isActive = true,
    this.corners = const [],
    this.hasPolygon = false,
  });

  factory VirtualRoomModel.fromJson(Map<String, dynamic> json) {
    var list = json['corners'] as List? ?? [];
    List<RoomCornerModel> fetchedCorners = list
        .map((e) => RoomCornerModel.fromJson(e as Map<String, dynamic>))
        .toList();
    fetchedCorners.sort((a, b) => a.cornerIndex.compareTo(b.cornerIndex));

    return VirtualRoomModel(
      id: json['id']?.toString() ?? '',
      college: json['college']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      building: json['building']?.toString() ?? '',
      department: json['department']?.toString() ?? '',
      floorNumber: json['floor_number'] as int? ?? 0,
      capacity: json['capacity'] as int? ?? 60,
      centerLat: json['center_lat'] != null ? (json['center_lat'] as num).toDouble() : null,
      centerLng: json['center_lng'] != null ? (json['center_lng'] as num).toDouble() : null,
      
      // Map API Spatial Reconstruction fields
      areaSqMeters: (json['area_sq_meters'] as num? ?? 0.0).toDouble(),
      perimeterMeters: (json['perimeter_meters'] as num? ?? json['perimeter'] as num? ?? 0.0).toDouble(),
      orientationDegrees: (json['orientation_degrees'] as num? ?? json['orientation'] as num? ?? 0.0).toDouble(),
      reconstructionQuality: (json['reconstruction_quality'] as num? ?? json['quality'] as num? ?? 100.0).toDouble(),
      spatialMetadata: json['spatial_metadata'] as Map<String, dynamic>? ?? const {},

      createdBy: json['created_by']?.toString(),
      createdByName: json['created_by_name']?.toString() ?? 'Unknown',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      isActive: json['is_active'] == true,
      corners: fetchedCorners,
      hasPolygon: json['has_polygon'] == true || fetchedCorners.length == 4,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'college': college,
    'name': name,
    'building': building,
    'department': department,
    'floor_number': floorNumber,
    'capacity': capacity,
    'center_lat': centerLat,
    'center_lng': centerLng,
    'area_sq_meters': areaSqMeters,
    'perimeter_meters': perimeterMeters,
    'orientation_degrees': orientationDegrees,
    'reconstruction_quality': reconstructionQuality,
    'spatial_metadata': spatialMetadata,
    'created_by': createdBy,
    'created_by_name': createdByName,
    'created_at': createdAt?.toIso8601String(),
    'is_active': isActive,
    'corners': corners.map((e) => e.toJson()).toList(),
    'has_polygon': hasPolygon,
  };

  VirtualRoomModel copyWith({
    String? id,
    String? college,
    String? name,
    String? building,
    String? department,
    int? floorNumber,
    int? capacity,
    double? centerLat,
    double? centerLng,
    double? areaSqMeters,
    double? perimeterMeters,
    double? orientationDegrees,
    double? reconstructionQuality,
    Map<String, dynamic>? spatialMetadata,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    bool? isActive,
    List<RoomCornerModel>? corners,
    bool? hasPolygon,
  }) {
    return VirtualRoomModel(
      id: id ?? this.id,
      college: college ?? this.college,
      name: name ?? this.name,
      building: building ?? this.building,
      department: department ?? this.department,
      floorNumber: floorNumber ?? this.floorNumber,
      capacity: capacity ?? this.capacity,
      centerLat: centerLat ?? this.centerLat,
      centerLng: centerLng ?? this.centerLng,
      areaSqMeters: areaSqMeters ?? this.areaSqMeters,
      perimeterMeters: perimeterMeters ?? this.perimeterMeters,
      orientationDegrees: orientationDegrees ?? this.orientationDegrees,
      reconstructionQuality: reconstructionQuality ?? this.reconstructionQuality,
      spatialMetadata: spatialMetadata ?? this.spatialMetadata,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      corners: corners ?? this.corners,
      hasPolygon: hasPolygon ?? this.hasPolygon,
    );
  }
}
