import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';

// ─────────────────────────────────────────────────────────────────────────────
// KALMAN FILTER (1-D)
// ─────────────────────────────────────────────────────────────────────────────
class KalmanFilter {
  final double _q; // process noise
  final double _r; // measurement noise
  double _x = 0.0;
  double _p = 1.0;
  bool   _initialized = false;

  KalmanFilter({double q = 1e-6, double r = 1e-4}) : _q = q, _r = r;

  double filter(double z) {
    if (!_initialized) { _x = z; _p = 1.0; _initialized = true; return _x; }
    _p += _q;
    final k = _p / (_p + _r);
    _x += k * (z - _x);
    _p *= (1.0 - k);
    return _x;
  }

  void reset() { _initialized = false; _p = 1.0; }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA TYPES
// ─────────────────────────────────────────────────────────────────────────────
class SensorVector3 {
  final double x, y, z;
  const SensorVector3(this.x, this.y, this.z);
  static const SensorVector3 zero = SensorVector3(0, 0, 0);
  double get length => math.sqrt(x * x + y * y + z * z);
}

class FusedSensorReading {
  final double latitude;
  final double longitude;
  final double altitude;
  final double gpsAccuracy;
  final bool   isGpsUpdate;
  final double headingDegrees;
  final double compassDegrees;
  final String directionLabel;
  final SensorVector3 accelerometer;
  final SensorVector3 gyroscope;
  final double motionVariance;
  final bool   isStationary;
  final DateTime timestamp;

  FusedSensorReading({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.gpsAccuracy,
    required this.isGpsUpdate,
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
// SENSOR FUSION SERVICE — FIXED
// ─────────────────────────────────────────────────────────────────────────────
class SensorFusionService {
  // ── Kalman filters ────────────────────────────────────────────────────────
  // FIX: original used q=1e-5, r=1e-4 for lat/lng.
  // For indoor/classroom GPS (high noise, near-static device) we need:
  //   - Lower process noise q (we don't expect the room corner to MOVE)
  //   - Higher measurement noise r (GPS readings in a building are noisy)
  // This prevents the filter from drifting to incorrect values across samples.
  final KalmanFilter _latFilter     = KalmanFilter(q: 1e-7, r: 1e-3);
  final KalmanFilter _lngFilter     = KalmanFilter(q: 1e-7, r: 1e-3);
  final KalmanFilter _altFilter     = KalmanFilter(q: 1e-5, r: 1e-2);
  final KalmanFilter _headingFilter = KalmanFilter(q: 1e-3, r: 1e-1);

  // ── Stream subscriptions ──────────────────────────────────────────────────
  StreamSubscription<Position>?              _gpsSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>?        _gyroSub;
  StreamSubscription<CompassEvent>?          _compassSub;

  // ── Live values ───────────────────────────────────────────────────────────
  Position?      _lastGps;
  SensorVector3  _lastAccel = SensorVector3.zero;
  SensorVector3  _lastGyro  = SensorVector3.zero;
  double         _lastCompass = 0.0;

  // Track last filtered coordinates to avoid filter lock-in during sensor-only events
  double _lastFiltLat = 0.0;
  double _lastFiltLng = 0.0;
  double _lastFiltAlt = 0.0;

  // ── Motion variance window ────────────────────────────────────────────────
  final List<double> _accelWindow = [];
  static const int _windowSize = 30;

  // ── Output stream ─────────────────────────────────────────────────────────
  final StreamController<FusedSensorReading> _ctrl =
      StreamController<FusedSensorReading>.broadcast();
  Stream<FusedSensorReading> get fusedStream => _ctrl.stream;

  bool _active = false;
  bool get isActive => _active;

  DateTime? _trackingStartTime;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  // ─────────────────────────────────────────────────────────────────────────
  Future<void> startTracking() async {
    if (_active) return;
    _active = true;

    // FIX: Reset ALL state including Kalman filters so stale filtered values
    // from a previous corner don't contaminate the new corner's first reading.
    _lastGps    = null;
    _lastAccel  = SensorVector3.zero;
    _lastGyro   = SensorVector3.zero;
    _lastCompass = 0.0;
    _lastFiltLat = 0.0;
    _lastFiltLng = 0.0;
    _lastFiltAlt = 0.0;
    _accelWindow.clear();
    _latFilter.reset();
    _lngFilter.reset();
    _altFilter.reset();
    _headingFilter.reset();
    _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    _trackingStartTime = DateTime.now();

    // ── Permissions ───────────────────────────────────────────────────────
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _active = false;
      throw Exception('Location services are disabled. Enable GPS in device Settings.');
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        _active = false;
        throw Exception('Location permission denied. Room capture requires GPS access.');
      }
    }
    if (perm == LocationPermission.deniedForever) {
      _active = false;
      throw Exception(
        'Location permission is permanently denied. '
        'Enable it in App Settings > Permissions > Location.',
      );
    }

    // ── GPS Stream ────────────────────────────────────────────────────────
    // FIX: Use distanceFilter: 0 + timeLimit to ensure we get frequent updates
    // even when the device is stationary (GPS receivers still output position
    // updates even without movement — distanceFilter:0 doesn't suppress these).
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (pos) {
        // PROGRESSIVE ACCURACY WARMUP GATE:
        // Oppo/Realme/Vivo and indoor locations frequently start with 100m-400m accuracy.
        // During the first 8 seconds of tracking, allow coarse fixes up to 150m to let the
        // GPS warm up and feed the Kalman filter. Then tighten the limit to 60m.
        final elapsedSeconds = _trackingStartTime != null
            ? DateTime.now().difference(_trackingStartTime!).inSeconds
            : 0;
        final double maxAllowedAccuracy = elapsedSeconds <= 8 ? 150.0 : 60.0;

        if (pos.accuracy > maxAllowedAccuracy) {
          debugPrint('SF: Dropped high-error GPS fix (±${pos.accuracy.toStringAsFixed(1)}m | limit=${maxAllowedAccuracy.toStringAsFixed(0)}m)');
          return;
        }
        
        _lastGps = pos;
        _emit(isGpsUpdate: true);
      },
      onError: (err) => debugPrint('SF-GPS Error: $err'),
    );

    // ── Compass ───────────────────────────────────────────────────────────
    _compassSub = FlutterCompass.events?.listen(
      (e) { _lastCompass = e.heading ?? 0.0; _emit(isGpsUpdate: false); },
      onError: (err) => debugPrint('SF-Compass Error: $err'),
    );

    // ── Accelerometer ─────────────────────────────────────────────────────
    _accelSub = userAccelerometerEvents.listen((e) {
      _lastAccel = SensorVector3(e.x, e.y, e.z);
      _updateMotion(_lastAccel.length);
      _emit(isGpsUpdate: false);
    });

    // ── Gyroscope ─────────────────────────────────────────────────────────
    _gyroSub = gyroscopeEvents.listen((e) {
      _lastGyro = SensorVector3(e.x, e.y, e.z);
      _emit(isGpsUpdate: false);
    });
  }

  Future<void> stopTracking() async {
    _active = false;
    await _gpsSub?.cancel();
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _compassSub?.cancel();
    _gpsSub = _accelSub = _gyroSub = _compassSub = null;
  }

  void _updateMotion(double magnitude) {
    _accelWindow.add(magnitude);
    if (_accelWindow.length > _windowSize) _accelWindow.removeAt(0);
  }

  double get _variance {
    if (_accelWindow.isEmpty) return 0.0;
    final avg = _accelWindow.reduce((a, b) => a + b) / _accelWindow.length;
    return _accelWindow.map((x) => (x - avg) * (x - avg)).reduce((a, b) => a + b)
           / _accelWindow.length;
  }

  void _emit({required bool isGpsUpdate}) {
    final gps = _lastGps;
    if (gps == null || _ctrl.isClosed) return;

    final now = DateTime.now();
    // Always let GPS updates through; throttle sensor-only updates to 2 Hz
    if (!isGpsUpdate && now.difference(_lastEmit).inMilliseconds < 500) return;
    _lastEmit = now;

    // FIX: Apply Kalman filter ONLY on genuine GPS updates.
    // Running the filter on every compass/accel event re-filters the same
    // GPS coordinate hundreds of times per second, which causes the filter's
    // uncertainty estimate (_p) to collapse to near-zero, making it completely
    // ignore future real GPS measurements ("filter lock-in" bug).
    final double filtLat, filtLng, filtAlt;
    if (isGpsUpdate) {
      filtLat = _latFilter.filter(gps.latitude);
      filtLng = _lngFilter.filter(gps.longitude);
      filtAlt = _altFilter.filter(gps.altitude);
      _lastFiltLat = filtLat;
      _lastFiltLng = filtLng;
      _lastFiltAlt = filtAlt;
    } else {
      // For sensor-only updates, return the most recently filtered GPS value
      // without re-filtering (i.e. just re-emit with updated IMU data).
      filtLat = _lastFiltLat != 0.0 ? _lastFiltLat : gps.latitude;
      filtLng = _lastFiltLng != 0.0 ? _lastFiltLng : gps.longitude;
      filtAlt = _lastFiltAlt != 0.0 ? _lastFiltAlt : gps.altitude;
    }

    // Heading fusion: prefer compass; fall back to GPS heading
    double rawHeading = gps.heading.isNaN || gps.heading == 0.0
        ? _lastCompass
        : gps.heading;
    final filtHeading = _headingFilter.filter(rawHeading);

    final normalizedCompass = (_lastCompass + 360.0) % 360.0;
    final variance     = _variance;
    final isStationary = variance < 0.08; // tightened threshold

    _ctrl.add(FusedSensorReading(
      latitude:       filtLat,
      longitude:      filtLng,
      altitude:       filtAlt,
      gpsAccuracy:    gps.accuracy,
      isGpsUpdate:    isGpsUpdate,
      headingDegrees: (filtHeading + 360.0) % 360.0,
      compassDegrees: normalizedCompass,
      directionLabel: _dirLabel(normalizedCompass),
      accelerometer:  _lastAccel,
      gyroscope:      _lastGyro,
      motionVariance: variance,
      isStationary:   isStationary,
      timestamp:      now,
    ));
  }

  String _dirLabel(double deg) {
    const dirs = ['N','NE','E','SE','S','SW','W','NW','N'];
    return dirs[((deg + 22.5) / 45.0).floor().clamp(0, 8)];
  }
}
