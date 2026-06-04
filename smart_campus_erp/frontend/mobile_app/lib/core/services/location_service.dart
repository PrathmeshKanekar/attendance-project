import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'security_service.dart';

class LocationException implements Exception {
  final String message;
  final bool isServiceDisabled;
  final bool isPermissionDenied;
  final bool isPermissionPermanentlyDenied;
  final bool isSpoofed;

  LocationException(
    this.message, {
    this.isServiceDisabled = false,
    this.isPermissionDenied = false,
    this.isPermissionPermanentlyDenied = false,
    this.isSpoofed = false,
  });

  @override
  String toString() => message;
}

class LocationService {
  Position? _lastValidPosition;
  DateTime? _lastTimestamp;

  /// Get a highly secure, filtered GPS position for ATTENDANCE MARKING.
  ///
  /// Implements anti-location-spoofing, speed sanity checks, accuracy filtering,
  /// and device integrity validation.
  Future<Position> getCurrentPosition({
    LocationAccuracy desiredAccuracy = LocationAccuracy.bestForNavigation,
    int maxAttempts = 3,
    double maxAcceptableAccuracy = 25.0, // Tightened threshold
    Duration perAttemptTimeout = const Duration(seconds: 15),
  }) async {
    // ── 0. Anti-Spoofing: Device Integrity Verification ────────────────────
    final securityError = await SecurityService.checkDeviceSecurity();
    if (securityError != null) {
      throw LocationException(
        securityError,
        isSpoofed: true,
      );
    }

    // ── 1. Service check ──────────────────────────────────────────────────
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationException(
        'Location services are disabled. Please enable GPS in Settings.',
        isServiceDisabled: true,
      );
    }

    // ── 2. Permission check ───────────────────────────────────────────────
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationException(
          'Location permission denied. This app needs GPS to verify your '
          'physical presence in class.',
          isPermissionDenied: true,
        );
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationException(
        'Location permission is permanently denied. '
        'Please enable it in App Settings.',
        isPermissionPermanentlyDenied: true,
      );
    }

    // ── 3. Try last known position with age and integrity checks ───────────
    Position? bestPosition;
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        // Enforce anti-spoof checks on last known position
        if (lastKnown.isMocked) {
          throw LocationException(
            'Mock/Fake GPS detected. Disable any fake GPS apps and try again.',
            isSpoofed: true,
          );
        }
        
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (age.inSeconds < 60) {
          bestPosition = lastKnown;
          if (lastKnown.accuracy <= maxAcceptableAccuracy) {
            _updateTelemetryCache(lastKnown);
            return lastKnown;
          }
        }
      }
    } catch (e) {
      if (e is LocationException) rethrow;
    }

    // ── 4. High Accuracy Live GPS Capture ───
    String lastError = '';
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: desiredAccuracy,
            forceLocationManager: false, // use Fused Provider for best speed & accuracy
            timeLimit: perAttemptTimeout,
          ),
        );

        // A. Anti-Spoofing: Direct Mock Flag Check
        if (pos.isMocked) {
          throw LocationException(
            'Mock/Fake GPS detected. Disable any fake GPS apps and try again.',
            isSpoofed: true,
          );
        }

        // B. Anti-Spoofing: Movement Kinematics Anomaly Check
        if (_isKinematicAnomaly(pos)) {
          throw LocationException(
            'Suspicious GPS velocity or position jump detected. Spoofing suspected.',
            isSpoofed: true,
          );
        }

        if (bestPosition == null || pos.accuracy < bestPosition.accuracy) {
          bestPosition = pos;
        }

        if (pos.accuracy <= maxAcceptableAccuracy) {
          _updateTelemetryCache(pos);
          return pos;
        }

        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 700));
        }
      } on LocationException {
        rethrow;
      } catch (e) {
        lastError = e.toString();
        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 700));
        }
      }
    }

    // ── 5. Best-effort fallback within realistic threshold ──────────────────
    if (bestPosition != null) {
      // Reject if extremely noisy (>50m) to enforce boundaries
      if (bestPosition.accuracy > 50.0) {
        throw LocationException(
          'GPS signal is too weak (±${bestPosition.accuracy.toStringAsFixed(1)}m). '
          'Please stand near a window or move to an open area and try again.',
        );
      }
      _updateTelemetryCache(bestPosition);
      return bestPosition;
    }

    throw LocationException(
      'Could not acquire secure GPS location. '
      'Move near a window and ensure GPS is enabled. ($lastError)',
    );
  }

  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// Returns true if mock/fake GPS is currently active.
  Future<bool> isMockLocationActive() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
  accuracy: LocationAccuracy.high,
  timeLimit: const Duration(seconds: 4),
),
      );
      return pos.isMocked;
    } catch (_) {
      return false; 
    }
  }

  /// Kinematics engine to detect impossible GPS telemetry jumps
  bool _isKinematicAnomaly(Position pos) {
    if (_lastValidPosition == null || _lastTimestamp == null) return false;

    final timeDelta = DateTime.now().difference(_lastTimestamp!).inSeconds;
    if (timeDelta <= 0) return false;

    // Calculate straight-line distance between successive coordinates
    final distance = Geolocator.distanceBetween(
      _lastValidPosition!.latitude,
      _lastValidPosition!.longitude,
      pos.latitude,
      pos.longitude,
    );

    // Calculate real-world speed (meters per second)
    final calculatedSpeed = distance / timeDelta;

    // A student inside a college cannot travel faster than 15 m/s (~54 km/h) between classroom heartbeats.
    // Also, instantaneous jumps of more than 500 meters are rejected as drift/spoofing.
    if (calculatedSpeed > 15.0 && distance > 500.0) {
      debugPrint('Security: GPS jump anomaly detected! Speed: ${calculatedSpeed.toStringAsFixed(1)} m/s, Distance: ${distance.toStringAsFixed(1)}m');
      return true;
    }

    return false;
  }

  void _updateTelemetryCache(Position pos) {
    _lastValidPosition = pos;
    _lastTimestamp = DateTime.now();
  }
}