import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// GPS Anti-Spoof Security Service for Virtual Room Creation.
///
/// Performs client-side detection of:
/// 1. Mock location apps (Android isMocked flag)
/// 2. Implausible accuracy values (< 0.3m = fake)
/// 3. Impossible coordinate jumps (> 500m/s)
/// 4. Rapid coordinate oscillation (> 5m change, > 3x/second)
/// 5. Suspicious coordinates (null island, ocean zones)

class GpsSecurityFlag {
  final String flagType;
  final String description;
  final Map<String, dynamic> detail;
  final DateTime timestamp;

  const GpsSecurityFlag({
    required this.flagType,
    required this.description,
    required this.detail,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'flag_type': flagType,
    'description': description,
    'detail': detail,
    'timestamp': timestamp.toIso8601String(),
  };
}

class GpsSecurityResult {
  final bool isSecure;
  final List<GpsSecurityFlag> flags;
  final double healthScore; // 0.0 to 100.0

  const GpsSecurityResult({
    required this.isSecure,
    required this.flags,
    required this.healthScore,
  });
}

class GpsSecurityService {
  final List<_TimestampedPosition> _positionHistory = [];
  final List<GpsSecurityFlag> _activeFlags = [];

  static const int _maxHistorySize = 20;
  static const double _minPlausibleAccuracy = 0.3; // meters
  static const double _maxSpeedMs = 500.0; // m/s — impossible for walking
  static const double _oscillationThresholdMeters = 5.0;
  static const int _oscillationMaxPerSecond = 3;

  List<GpsSecurityFlag> get activeFlags => List.unmodifiable(_activeFlags);

  /// Run all security checks against a new GPS position.
  /// Returns a security result with pass/fail and detected flags.
  GpsSecurityResult evaluatePosition(Position position) {
    _activeFlags.clear();
    final now = DateTime.now();

    // 1. Mock location detection
    if (position.isMocked) {
      _activeFlags.add(GpsSecurityFlag(
        flagType: 'mock_location',
        description: 'Mock location provider detected',
        detail: {'isMocked': true},
        timestamp: now,
      ));
    }

    // 2. Implausible accuracy check
    if (position.accuracy < _minPlausibleAccuracy && position.accuracy > 0) {
      _activeFlags.add(GpsSecurityFlag(
        flagType: 'fake_gps',
        description: 'Implausibly precise GPS accuracy detected',
        detail: {'accuracy': position.accuracy, 'threshold': _minPlausibleAccuracy},
        timestamp: now,
      ));
    }

    // 3. Suspicious coordinates check (null island, extreme values)
    if (_isSuspiciousCoordinate(position.latitude, position.longitude)) {
      _activeFlags.add(GpsSecurityFlag(
        flagType: 'suspicious_coordinates',
        description: 'Coordinates are in a known invalid zone',
        detail: {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
        timestamp: now,
      ));
    }

    // 4. Speed check — impossible coordinate jump
    if (_positionHistory.isNotEmpty) {
      final last = _positionHistory.last;
      final distanceMeters = Geolocator.distanceBetween(
        last.position.latitude,
        last.position.longitude,
        position.latitude,
        position.longitude,
      );
      final timeDiffSeconds = now.difference(last.timestamp).inMilliseconds / 1000.0;

      if (timeDiffSeconds > 0.1) {
        final speedMs = distanceMeters / timeDiffSeconds;
        if (speedMs > _maxSpeedMs) {
          _activeFlags.add(GpsSecurityFlag(
            flagType: 'coordinate_jump',
            description: 'Impossible coordinate jump detected',
            detail: {
              'speed_ms': speedMs,
              'distance_meters': distanceMeters,
              'time_seconds': timeDiffSeconds,
              'threshold_ms': _maxSpeedMs,
            },
            timestamp: now,
          ));
        }
      }
    }

    // 5. Oscillation check — rapid back-and-forth movement
    if (_positionHistory.length >= 3) {
      final oneSecondAgo = now.subtract(const Duration(seconds: 1));
      final recentPositions = _positionHistory
          .where((p) => p.timestamp.isAfter(oneSecondAgo))
          .toList();

      int oscillationCount = 0;
      for (int i = 1; i < recentPositions.length; i++) {
        final dist = Geolocator.distanceBetween(
          recentPositions[i - 1].position.latitude,
          recentPositions[i - 1].position.longitude,
          recentPositions[i].position.latitude,
          recentPositions[i].position.longitude,
        );
        if (dist > _oscillationThresholdMeters) {
          oscillationCount++;
        }
      }

      if (oscillationCount >= _oscillationMaxPerSecond) {
        _activeFlags.add(GpsSecurityFlag(
          flagType: 'rapid_oscillation',
          description: 'Rapid coordinate oscillation detected',
          detail: {
            'oscillations_per_second': oscillationCount,
            'threshold': _oscillationMaxPerSecond,
          },
          timestamp: now,
        ));
      }
    }

    // Add to history
    _positionHistory.add(_TimestampedPosition(position: position, timestamp: now));
    if (_positionHistory.length > _maxHistorySize) {
      _positionHistory.removeAt(0);
    }

    // Calculate health score
    final healthScore = _calculateHealthScore(position);

    final hasHardFlag = _activeFlags.any((f) =>
        f.flagType == 'mock_location' || f.flagType == 'fake_gps');

    return GpsSecurityResult(
      isSecure: _activeFlags.isEmpty,
      flags: List.unmodifiable(_activeFlags),
      healthScore: hasHardFlag ? 0.0 : healthScore,
    );
  }

  bool _isSuspiciousCoordinate(double lat, double lng) {
    // Null island
    if (lat.abs() < 0.01 && lng.abs() < 0.01) return true;
    // Outside valid ranges
    if (lat.abs() > 90.0 || lng.abs() > 180.0) return true;
    // North/South pole (impossible for a building)
    if (lat.abs() > 85.0) return true;
    return false;
  }

  double _calculateHealthScore(Position position) {
    double score = 100.0;

    // Accuracy penalty
    if (position.accuracy > 15.0) {
      score -= (position.accuracy - 15.0) * 2.0;
    }

    // Mock penalty
    if (position.isMocked) {
      score = 0.0;
    }

    // Flag penalty
    score -= _activeFlags.length * 15.0;

    return score.clamp(0.0, 100.0);
  }

  /// Reset all state — call when starting a new capture session.
  void reset() {
    _positionHistory.clear();
    _activeFlags.clear();
  }
}

class _TimestampedPosition {
  final Position position;
  final DateTime timestamp;

  const _TimestampedPosition({required this.position, required this.timestamp});
}
