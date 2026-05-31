import 'package:geolocator/geolocator.dart';
import 'dart:async';

class LocationException implements Exception {
  final String message;
  final bool isServiceDisabled;
  final bool isPermissionDenied;
  final bool isPermissionPermanentlyDenied;

  LocationException(
    this.message, {
    this.isServiceDisabled = false,
    this.isPermissionDenied = false,
    this.isPermissionPermanentlyDenied = false,
  });

  @override
  String toString() => message;
}

class LocationService {
  /// Get a GPS position for ATTENDANCE MARKING.
  ///
  /// Two-phase strategy for fast indoor results:
  /// Phase 1: Fast Fused Location (WiFi + cell) — returns in 1-3s indoors.
  /// Phase 2: GPS chip attempts — for better accuracy if Phase 1 was poor.
  /// Always returns best position found, even if accuracy is poor.
  /// Backend geo_utils handles poor accuracy with tiered slack.
  Future<Position> getCurrentPosition({
    LocationAccuracy desiredAccuracy = LocationAccuracy.bestForNavigation,
    int maxAttempts = 3,
    double maxAcceptableAccuracy = 50.0,
    Duration perAttemptTimeout = const Duration(seconds: 30),
  }) async {
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

    // ── 3. Try last known position as instant fallback ────────────────────
    // If a recent cached location exists, use it as starting candidate.
    // This makes attendance marking near-instant when GPS was recently active.
    Position? bestPosition;
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && !lastKnown.isMocked) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (age.inSeconds < 120) {
          // Recent enough — use as fallback
          bestPosition = lastKnown;
          // If last known is already accurate enough, return immediately
          if (lastKnown.accuracy <= maxAcceptableAccuracy) {
            return lastKnown;
          }
        }
      }
    } catch (_) {
      // Last known position is optional — ignore errors
    }

    // ── 4. Phase 1: Fast Fused Location (WiFi + cell, returns in 1-3s) ───
    // Use LocationAccuracy.high which uses Fused Location Provider.
    // This returns quickly indoors and gives a reasonable position.
    try {
      final fastPos = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          forceLocationManager: false, // use Fused Location Provider
          timeLimit: const Duration(seconds: 8), // fast timeout
        ),
      ).timeout(const Duration(seconds: 10));

      if (!fastPos.isMocked) {
        if (bestPosition == null || fastPos.accuracy < bestPosition.accuracy) {
          bestPosition = fastPos;
        }
        // If accuracy is acceptable, return now — don't wait for GPS chip
        if (fastPos.accuracy <= maxAcceptableAccuracy) {
          return fastPos;
        }
      }
    } catch (_) {
      // Phase 1 failed — continue to Phase 2
    }

    // ── 5. Phase 2: Best-effort GPS chip attempts ─────────────────────────
    // Only run if Phase 1 didn't give good enough accuracy.
    String lastError = '';
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            forceLocationManager: false,
            timeLimit: perAttemptTimeout,
          ),
        );

        if (pos.isMocked) {
          throw LocationException(
            'Mock/Fake GPS detected. Disable any fake GPS apps and try again.',
          );
        }

        if (bestPosition == null || pos.accuracy < bestPosition.accuracy) {
          bestPosition = pos;
        }

        if (pos.accuracy <= maxAcceptableAccuracy) {
          return pos;
        }

        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(seconds: 1));
        }
      } on LocationException {
        rethrow;
      } catch (e) {
        lastError = e.toString();
        if (attempt < maxAttempts) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    // ── 6. Return best we got, even if accuracy is poor ───────────────────
    // The backend geo_utils now handles poor accuracy correctly with tiered slack.
    if (bestPosition != null) {
      return bestPosition;
    }

    throw LocationException(
      'Could not acquire GPS location after $maxAttempts attempts. '
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
  /// Tries to get a single GPS fix and checks if it is mocked.
  Future<bool> isMockLocationActive() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      return pos.isMocked;
    } catch (_) {
      return false; // If we can't get position, assume not mocked
    }
  }
}