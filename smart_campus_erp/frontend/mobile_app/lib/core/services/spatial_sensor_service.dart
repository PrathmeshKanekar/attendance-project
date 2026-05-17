// spatial_sensor_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Unified sensor acquisition for GPS, IMU, compass, and barometer.
// Used by SpatialValidationService for attendance validation.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../../features/virtual_rooms/models/spatial_data.dart';

class SpatialSensorService {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<CompassEvent>? _compassSub;

  AccelerometerEvent? _lastAccel;
  GyroscopeEvent? _lastGyro;
  MagnetometerEvent? _lastMag;
  double _lastHeading = 0.0;

  void startListening() {
    _accelSub = accelerometerEventStream().listen((e) => _lastAccel = e);
    _gyroSub = gyroscopeEventStream().listen((e) => _lastGyro = e);
    _magSub = magnetometerEventStream().listen((e) => _lastMag = e);
    _compassSub = FlutterCompass.events?.listen((e) => _lastHeading = e.heading ?? 0.0);
  }

  void stopListening() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
    _compassSub?.cancel();
  }

  Future<SpatialData?> captureCurrentState() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      return SpatialData(
        latitude: pos.latitude,
        longitude: pos.longitude,
        altitude: pos.altitude,
        accuracy: pos.accuracy,
        heading: _lastHeading,
        accelerometer: {
          'x': _lastAccel?.x ?? 0.0,
          'y': _lastAccel?.y ?? 0.0,
          'z': _lastAccel?.z ?? 0.0,
        },
        gyroscope: {
          'x': _lastGyro?.x ?? 0.0,
          'y': _lastGyro?.y ?? 0.0,
          'z': _lastGyro?.z ?? 0.0,
        },
        magneticField: {
          'x': _lastMag?.x ?? 0.0,
          'y': _lastMag?.y ?? 0.0,
          'z': _lastMag?.z ?? 0.0,
        },
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  Stream<SpatialData> getSpatialDataStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings).map((pos) {
      return SpatialData(
        latitude: pos.latitude,
        longitude: pos.longitude,
        altitude: pos.altitude,
        accuracy: pos.accuracy,
        heading: _lastHeading,
        accelerometer: {
          'x': _lastAccel?.x ?? 0.0,
          'y': _lastAccel?.y ?? 0.0,
          'z': _lastAccel?.z ?? 0.0,
        },
        gyroscope: {
          'x': _lastGyro?.x ?? 0.0,
          'y': _lastGyro?.y ?? 0.0,
          'z': _lastGyro?.z ?? 0.0,
        },
        magneticField: {
          'x': _lastMag?.x ?? 0.0,
          'y': _lastMag?.y ?? 0.0,
          'z': _lastMag?.z ?? 0.0,
        },
        timestamp: DateTime.now(),
      );
    });
  }
}
