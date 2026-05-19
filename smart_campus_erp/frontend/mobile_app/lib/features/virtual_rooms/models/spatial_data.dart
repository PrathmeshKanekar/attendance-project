class SpatialData {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final double heading;
  final Map<String, double> accelerometer;
  final Map<String, double> gyroscope;
  final Map<String, double> magneticField;
  final DateTime timestamp;

  const SpatialData({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.heading,
    required this.accelerometer,
    required this.gyroscope,
    required this.magneticField,
    required this.timestamp,
  });

  factory SpatialData.fromJson(Map<String, dynamic> json) {
    return SpatialData(
      latitude: (json['latitude'] as num? ?? 0.0).toDouble(),
      longitude: (json['longitude'] as num? ?? 0.0).toDouble(),
      altitude: (json['altitude'] as num? ?? 0.0).toDouble(),
      accuracy: (json['accuracy'] as num? ?? 0.0).toDouble(),
      heading: (json['heading'] as num? ?? 0.0).toDouble(),
      accelerometer: Map<String, double>.from(json['accelerometer'] ?? {}),
      gyroscope: Map<String, double>.from(json['gyroscope'] ?? {}),
      magneticField: Map<String, double>.from(json['magnetic_field'] ?? {}),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'].toString())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'accuracy': accuracy,
    'heading': heading,
    'accelerometer': accelerometer,
    'gyroscope': gyroscope,
    'magnetic_field': magneticField,
    'timestamp': timestamp.toIso8601String(),
  };
}
