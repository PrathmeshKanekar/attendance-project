// data/models/corner_data.dart
// ─────────────────────────────────────────────────────────────────────────────
// Represents one captured physical corner of the classroom.
// ─────────────────────────────────────────────────────────────────────────────

class CornerData {
  final double lat;
  final double lng;
  final double alt;
  final double accuracy;
  final double altitudeAccuracy;
  final double heading;
  final double pitch;
  final double roll;
  final double yaw;

  // Raw sensor snapshots
  final Map<String, double>? accelerometer;
  final Map<String, double>? gyroscope;
  final Map<String, double>? magneticField;
  final double? barometricPressure;

  const CornerData({
    required this.lat,
    required this.lng,
    required this.alt,
    required this.accuracy,
    this.altitudeAccuracy = 5.0,
    required this.heading,
    this.pitch = 0.0,
    this.roll  = 0.0,
    this.yaw   = 0.0,
    this.accelerometer,
    this.gyroscope,
    this.magneticField,
    this.barometricPressure,
  });

  Map<String, dynamic> toJson() => {
    'lat':               lat,
    'lng':               lng,
    'alt':               alt,
    'accuracy':          accuracy,
    'altitude_accuracy': altitudeAccuracy,
    'heading':           heading,
    'pitch':             pitch,
    'roll':              roll,
    'yaw':               yaw,
    if (accelerometer != null)     'accelerometer':      accelerometer,
    if (gyroscope != null)         'gyroscope':          gyroscope,
    if (magneticField != null)     'magnetic_field':     magneticField,
    if (barometricPressure != null) 'barometric_pressure': barometricPressure,
  };

  factory CornerData.fromJson(Map<String, dynamic> json) => CornerData(
    lat:               (json['lat']     as num).toDouble(),
    lng:               (json['lng']     as num).toDouble(),
    alt:               (json['alt']     as num? ?? json['altitude'] as num? ?? 0).toDouble(),
    accuracy:          (json['accuracy'] as num? ?? 10).toDouble(),
    altitudeAccuracy:  (json['altitude_accuracy'] as num? ?? 5).toDouble(),
    heading:           (json['heading'] as num? ?? 0).toDouble(),
    pitch:             (json['pitch']   as num? ?? 0).toDouble(),
    roll:              (json['roll']    as num? ?? 0).toDouble(),
    yaw:               (json['yaw']     as num? ?? 0).toDouble(),
    accelerometer:     _parseXYZ(json['accelerometer']),
    gyroscope:         _parseXYZ(json['gyroscope']),
    magneticField:     _parseXYZ(json['magnetic_field']),
    barometricPressure: (json['barometric_pressure'] as num?)?.toDouble(),
  );

  static Map<String, double>? _parseXYZ(dynamic raw) {
    if (raw == null) return null;
    final m = Map<String, dynamic>.from(raw as Map);
    return {
      'x': (m['x'] as num? ?? 0).toDouble(),
      'y': (m['y'] as num? ?? 0).toDouble(),
      'z': (m['z'] as num? ?? 0).toDouble(),
    };
  }

  CornerAccuracy get accuracyRating {
    if (accuracy <= 5)  return CornerAccuracy.excellent;
    if (accuracy <= 10) return CornerAccuracy.good;
    if (accuracy <= 20) return CornerAccuracy.fair;
    return CornerAccuracy.poor;
  }

  @override
  String toString() =>
      'Corner(lat:${lat.toStringAsFixed(7)}, '
      'lng:${lng.toStringAsFixed(7)}, '
      'alt:${alt.toStringAsFixed(2)}m, '
      'acc:${accuracy.toStringAsFixed(1)}m)';
}

enum CornerAccuracy { excellent, good, fair, poor }
