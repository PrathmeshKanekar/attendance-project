// data/models/spatial_data.dart
// ─────────────────────────────────────────────────────────────────────────────
// Represents student GPS and device posture spatial snapshot.
// ─────────────────────────────────────────────────────────────────────────────

class SpatialData {
  final double latitude;
  final double longitude;
  final double altitude;
  final double heading;
  final double accuracy;
  
  // Optional sensor forensics for anti-spoofing
  final Map<String, double>? accelerometer;
  final Map<String, double>? gyroscope;
  final Map<String, double>? magneticField;
  final DateTime? timestamp;

  const SpatialData({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.heading,
    required this.accuracy,
    this.accelerometer,
    this.gyroscope,
    this.magneticField,
    this.timestamp,
  });

  factory SpatialData.fromJson(Map<String, dynamic> json) {
    return SpatialData(
      latitude: (json['lat'] ?? 0).toDouble(),
      longitude: (json['lng'] ?? 0).toDouble(),
      altitude: (json['alt'] ?? 0).toDouble(),
      heading: (json['heading'] ?? 0).toDouble(),
      accuracy: (json['accuracy'] ?? 0).toDouble(),
      accelerometer: json['accelerometer'] != null 
          ? Map<String, double>.from(json['accelerometer']) 
          : null,
      gyroscope: json['gyroscope'] != null 
          ? Map<String, double>.from(json['gyroscope']) 
          : null,
      magneticField: json['magnetic_field'] != null 
          ? Map<String, double>.from(json['magnetic_field']) 
          : null,
      timestamp: json['timestamp'] != null 
          ? DateTime.parse(json['timestamp']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lng': longitude,
    'alt': altitude,
    'heading': heading,
    'accuracy': accuracy,
    if (accelerometer != null) 'accelerometer': accelerometer,
    if (gyroscope != null) 'gyroscope': gyroscope,
    if (magneticField != null) 'magnetic_field': magneticField,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
  };
}
