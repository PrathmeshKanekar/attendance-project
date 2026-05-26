import 'package:smart_campus_app/features/virtual_rooms/services/sensor_fusion_service.dart';

class AntiSpoofResult {
  final bool isSpoofed;
  final String reason;
  final double confidenceScore;

  const AntiSpoofResult({
    required this.isSpoofed,
    required this.reason,
    required this.confidenceScore,
  });
}

class AntiSpoofingService {
  /// Evaluates device raw sensor states against GPS readings to identify 
  /// location emulation, mock GPS tools, or telemetry injections.
  static AntiSpoofResult verifyLocationIntegrity({
    required double latitude,
    required double longitude,
    required double speedMetersPerSec,
    required double accuracyMeters,
    required bool isMockedFlag,
    required SensorVector3 accelerometer,
    required SensorVector3 gyroscope,
    required double motionVariance,
  }) {
    // 1. Hard Check: Device system mock provider detected
    if (isMockedFlag) {
      return const AntiSpoofResult(
        isSpoofed: true,
        reason: 'Developer Options Mock Location active on device level.',
        confidenceScore: 0.0,
      );
    }

    // 2. Telemetry Mismatch: Impossible GPS speeds with static accelerometer
    // If the student is theoretically moving at high speed (> 1.2 m/s), 
    // but the phone accelerometer shows completely stationary state (variance < 0.01),
    // this constitutes a high probability of virtual GPS coordinate injection.
    if (speedMetersPerSec > 1.2 && motionVariance < 0.01) {
      return const AntiSpoofResult(
        isSpoofed: true,
        reason: 'IMU telemetry mismatch. GPS coordinate injection suspected.',
        confidenceScore: 10.0,
      );
    }

    // 3. Sensor Drift: Impossible GPS accuracy thresholds
    if (accuracyMeters > 80.0) {
      return const AntiSpoofResult(
        isSpoofed: false,
        reason: 'GPS accuracy too low. Jittering coordinate state.',
        confidenceScore: 50.0,
      );
    }

    // 4. Stable verified signal
    double confidence = 100.0;
    if (accuracyMeters > 15.0) {
      confidence -= (accuracyMeters - 15.0) * 1.5;
    }
    if (motionVariance > 0.4) {
      confidence -= 10.0; // deduct slightly for heavy jitter/running
    }
    confidence = confidence.clamp(10.0, 100.0);

    return AntiSpoofResult(
      isSpoofed: false,
      reason: 'Secure signature verified.',
      confidenceScore: confidence,
    );
  }

  /// Prevents teleportation spoofing between consecutive coordinate reads
  static bool detectTeleportationJump({
    required double currentLat,
    required double currentLng,
    required double? lastLat,
    required double? lastLng,
    required DateTime currentTimestamp,
    required DateTime? lastTimestamp,
  }) {
    if (lastLat == null || lastLng == null || lastTimestamp == null) {
      return false;
    }

    final double timeDiffSeconds = currentTimestamp.difference(lastTimestamp).inSeconds.toDouble();
    if (timeDiffSeconds <= 0.5) return false;

    // Haversine distance in meters
    final double distMeters = _haversineDistance(currentLat, currentLng, lastLat, lastLng);
    
    // Physical human running speed limit (e.g. 15 m/s maximum velocity)
    final double speed = distMeters / timeDiffSeconds;
    if (speed > 15.0) {
      return true; // Impossible velocity jump detected
    }
    
    return false;
  }

  static double _haversineDistance(double lat1, double lng1, double lat2, double lng2) {
    const double r = 6371000.0;
    final double dLat = (lat2 - lat1) * 3.141592653589793 / 180.0;
    final double dLng = (lng2 - lng1) * 3.141592653589793 / 180.0;
    
    final double a = (mathSin(dLat / 2) * mathSin(dLat / 2)) +
        mathCos(lat1 * 3.141592653589793 / 180.0) *
        mathCos(lat2 * 3.141592653589793 / 180.0) *
        (mathSin(dLng / 2) * mathSin(dLng / 2));
    
    return 2 * r * mathAsin(mathSqrt(a));
  }

  // Quick approximations of trig functions for self-containment
  static double mathSin(double x) => x - (x * x * x / 6.0) + (x * x * x * x * x / 120.0);
  static double mathCos(double x) => 1.0 - (x * x / 2.0) + (x * x * x * x / 24.0);
  static double mathSqrt(double x) {
    if (x <= 0.0) return 0.0;
    double res = x;
    for (int i = 0; i < 6; i++) {
      res = 0.5 * (res + x / res);
    }
    return res;
  }
  static double mathAsin(double x) {
    if (x < -1.0) x = -1.0;
    if (x > 1.0) x = 1.0;
    return x + (x * x * x / 6.0) + (3.0 * x * x * x * x * x / 40.0);
  }
}
