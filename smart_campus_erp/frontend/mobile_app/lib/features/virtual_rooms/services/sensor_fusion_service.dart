import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';

// ─────────────────────────────────────────────────────────────────────────────
// KALMAN FILTER ENGINE (1D Continuous State Filter)
// ─────────────────────────────────────────────────────────────────────────────
class KalmanFilter {
  final double _q; // Process noise covariance
  final double _r; // Measurement noise covariance
  double _x = 0.0; // Estimated value
  double _p = 1.0; // Estimation error covariance
  double _k = 0.0; // Kalman gain
  bool _initialized = false;

  KalmanFilter({double q = 1e-6, double r = 1e-4})
      : _q = q,
        _r = r;

  double filter(double measurement) {
    if (!_initialized) {
      _x = measurement;
      _p = 1.0;
      _initialized = true;
      return _x;
    }
    // Prediction Update
    _p = _p + _q;
    // Measurement Update
    _k = _p / (_p + _r);
    _x = _x + _k * (measurement - _x);
    _p = (1.0 - _k) * _p;
    return _x;
  }

  void reset() {
    _initialized = false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SENSOR VECTOR STRUCT
// ─────────────────────────────────────────────────────────────────────────────
class SensorVector3 {
  final double x;
  final double y;
  final double z;

  const SensorVector3(this.x, this.y, this.z);

  static const SensorVector3 zero = SensorVector3(0.0, 0.0, 0.0);

  double get length => math.sqrt(x * x + y * y + z * z);
}

// ─────────────────────────────────────────────────────────────────────────────
// SENSOR READINGS STRUCT
// ─────────────────────────────────────────────────────────────────────────────
class FusedSensorReading {
  final double latitude;
  final double longitude;
  final double altitude;
  final double gpsAccuracy;
  
  // Fused Orientation & Direction
  final double headingDegrees;
  final double compassDegrees;
  final String directionLabel;

  // Sensor Raw streams
  final SensorVector3 accelerometer;
  final SensorVector3 gyroscope;
  
  // Computed motion state
  final double motionVariance;
  final bool isStationary;
  final DateTime timestamp;

  FusedSensorReading({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.gpsAccuracy,
    required this.headingDegrees,
    required this.compassDegrees,
    required this.directionLabel,
    required this.accelerometer,
    required this.gyroscope,
    required this.motionVariance,
    required this.isStationary,
    required this.timestamp,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SENSOR FUSION SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class SensorFusionService {
  // Kalman filters for spatial coords
  final KalmanFilter _latFilter = KalmanFilter(q: 1e-8, r: 1e-6);
  final KalmanFilter _lngFilter = KalmanFilter(q: 1e-8, r: 1e-6);
  final KalmanFilter _altFilter = KalmanFilter(q: 1e-5, r: 1e-3);
  final KalmanFilter _headingFilter = KalmanFilter(q: 1e-3, r: 1e-1);

  // Raw streams subscriptions
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<CompassEvent>? _compassSub;

  // Current live values
  Position? _lastGps;
  SensorVector3 _lastAccel = SensorVector3.zero;
  SensorVector3 _lastGyro = SensorVector3.zero;
  double _lastCompassHeading = 0.0;
  
  // Motion Variance Window
  final List<double> _accelMagnitudeWindow = [];
  static const int _windowSize = 25;

  // Controller for fused output stream
  final StreamController<FusedSensorReading> _fusedController = 
      StreamController<FusedSensorReading>.broadcast();

  Stream<FusedSensorReading> get fusedStream => _fusedController.stream;

  bool _isActive = false;
  bool get isActive => _isActive;

  // Start aggregated high-precision tracking
  Future<void> startTracking() async {
    if (_isActive) return;
    _isActive = true;
    
    _latFilter.reset();
    _lngFilter.reset();
    _altFilter.reset();
    _headingFilter.reset();
    _accelMagnitudeWindow.clear();

    // ── 0. Ensure location service is enabled & permissions granted ──────
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _isActive = false;
      throw Exception(
        'Location services are disabled. Please enable GPS in your device Settings.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _isActive = false;
        throw Exception(
          'Location permission denied. Room capture requires GPS access.',
        );
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _isActive = false;
      throw Exception(
        'Location permission is permanently denied. '
        'Please enable it in App Settings > Permissions > Location.',
      );
    }

    // 1. Geolocator High Accuracy Stream Configuration
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
    _gpsSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (pos) {
        _lastGps = pos;
        _emitFusedReading();
      },
      onError: (err) => debugPrint('SF-GPS Error: $err'),
    );

    // 2. Compass Stream
    _compassSub = FlutterCompass.events?.listen(
      (event) {
        _lastCompassHeading = event.heading ?? 0.0;
        _emitFusedReading();
      },
      onError: (err) => debugPrint('SF-Compass Error: $err'),
    );

    // 3. Accelerometer (sensors_plus) for physical motion detection
    _accelSub = userAccelerometerEvents.listen((event) {
      _lastAccel = SensorVector3(event.x, event.y, event.z);
      _updateMotionState(_lastAccel.length);
      _emitFusedReading();
    });

    // 4. Gyroscope for jitter and orientation changes
    _gyroSub = gyroscopeEvents.listen((event) {
      _lastGyro = SensorVector3(event.x, event.y, event.z);
      _emitFusedReading();
    });
  }

  // Stop tracking streams cleanly
  Future<void> stopTracking() async {
    _isActive = false;
    await _gpsSub?.cancel();
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _compassSub?.cancel();
    _gpsSub = null;
    _accelSub = null;
    _gyroSub = null;
    _compassSub = null;
  }

  // Calculate motion variance to tell if phone is steady (ideal for capture)
  void _updateMotionState(double magnitude) {
    _accelMagnitudeWindow.add(magnitude);
    if (_accelMagnitudeWindow.length > _windowSize) {
      _accelMagnitudeWindow.removeAt(0);
    }
  }

  double get _computeVariance {
    if (_accelMagnitudeWindow.isEmpty) return 0.0;
    double avg = _accelMagnitudeWindow.reduce((a, b) => a + b) / _accelMagnitudeWindow.length;
    double sumOfSquares = _accelMagnitudeWindow.map((x) => (x - avg) * (x - avg)).reduce((a, b) => a + b);
    return sumOfSquares / _accelMagnitudeWindow.length;
  }

  // Emit fused telemetry
  void _emitFusedReading() {
    final gps = _lastGps;
    if (gps == null) return;

    // Apply Kalman coordinate filter
    final filteredLat = _latFilter.filter(gps.latitude);
    final filteredLng = _lngFilter.filter(gps.longitude);
    final filteredAlt = _altFilter.filter(gps.altitude);
    
    // Fuse GPS heading and Compass heading with wrapping logic
    double rawHeading = gps.heading;
    if (rawHeading == 0.0 || rawHeading.isNaN) {
      rawHeading = _lastCompassHeading;
    }
    
    // Normalize compass between 0 and 360
    double normalizedCompass = (_lastCompassHeading + 360.0) % 360.0;
    final filteredHeading = _headingFilter.filter(rawHeading);
    
    final variance = _computeVariance;
    final isStationary = variance < 0.15; // Jitter-free threshold

    final reading = FusedSensorReading(
      latitude: filteredLat,
      longitude: filteredLng,
      altitude: filteredAlt,
      gpsAccuracy: gps.accuracy,
      headingDegrees: (filteredHeading + 360.0) % 360.0,
      compassDegrees: normalizedCompass,
      directionLabel: _getDirectionLabel(normalizedCompass),
      accelerometer: _lastAccel,
      gyroscope: _lastGyro,
      motionVariance: variance,
      isStationary: isStationary,
      timestamp: DateTime.now(),
    );

    _fusedController.add(reading);
  }

  // Helper to map angles to cardinal directions
  String _getDirectionLabel(double degrees) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N'];
    int idx = ((degrees + 22.5) / 45.0).floor();
    return directions[idx];
  }
}
