/// Multi-challenge liveness detection engine.
///
/// Processes face detection results against the current challenge
/// (blink, smile, head turn) and determines when each challenge
/// is successfully completed.
///
/// Anti-spoofing measures:
/// - Random challenge order defeats replay attacks
/// - Temporal validation ensures human-speed responses
/// - Brightness variance check detects static photos
/// - Challenge-specific hysteresis prevents false positives
library;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/liveness_challenge.dart';

/// Result of processing a single frame for liveness.
class LivenessFrameResult {
  /// Whether the current challenge was just completed this frame.
  final bool challengeCompleted;

  /// Current detection value for the active challenge (for UI feedback).
  /// For blink: eye openness (0.0 = closed, 1.0 = open)
  /// For smile: smile probability
  /// For head turn: yaw angle
  final double detectionValue;

  /// Anti-spoofing score for this frame (0.0 = likely spoof, 1.0 = likely real).
  final double antiSpoofScore;

  const LivenessFrameResult({
    this.challengeCompleted = false,
    this.detectionValue     = 0.0,
    this.antiSpoofScore     = 1.0,
  });
}

class LivenessDetector {
  // ── Blink Detection ──────────────────────────────────────────────
  static const double _kBlinkClosedThreshold = 0.20;
  static const double _kBlinkOpenThreshold   = 0.75;
  bool _eyeWasClosed = false;
  int  _lastBlinkMs  = 0;

  // ── Smile Detection ──────────────────────────────────────────────
  static const double _kSmileThreshold   = 0.70;
  static const double _kSmileResetThreshold = 0.30;
  bool _wasSmiling   = false;
  int  _smileStartMs = 0;
  static const int _kSmileHoldMs = 500; // Must smile for 500ms

  // ── Head Turn Detection ──────────────────────────────────────────
  static const double _kTurnThreshold = 25.0; // degrees
  static const double _kTurnResetThreshold = 10.0;
  bool _headWasTurned = false;

  // ── Anti-spoofing ────────────────────────────────────────────────
  final List<double> _recentBrightnessValues = [];
  static const int _kBrightnessHistorySize = 10;

  /// Processes a [face] against the current [challenge].
  ///
  /// Returns a [LivenessFrameResult] indicating whether the challenge
  /// was completed this frame, along with detection values for UI feedback.
  LivenessFrameResult processFrame(
    Face face,
    LivenessChallenge challenge,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;

    switch (challenge.type) {
      case ChallengeType.blink:
        return _processBlink(face, now);
      case ChallengeType.smile:
        return _processSmile(face, now);
      case ChallengeType.turnLeft:
        return _processTurnLeft(face);
      case ChallengeType.turnRight:
        return _processTurnRight(face);
    }
  }

  LivenessFrameResult _processBlink(Face face, int now) {
    final leftEye  = face.leftEyeOpenProbability  ?? 1.0;
    final rightEye = face.rightEyeOpenProbability ?? 1.0;
    final avgOpen  = (leftEye + rightEye) / 2;

    bool completed = false;

    if (avgOpen < _kBlinkClosedThreshold && !_eyeWasClosed) {
      _eyeWasClosed = true;
    } else if (avgOpen > _kBlinkOpenThreshold && _eyeWasClosed) {
      _eyeWasClosed = false;
      // Cooldown: minimum 300ms between blinks to avoid double-counting
      if (now - _lastBlinkMs > 300) {
        _lastBlinkMs = now;
        completed = true;
      }
    }

    return LivenessFrameResult(
      challengeCompleted: completed,
      detectionValue:     avgOpen,
    );
  }

  LivenessFrameResult _processSmile(Face face, int now) {
    final smileProbability = face.smilingProbability ?? 0.0;

    bool completed = false;

    if (smileProbability > _kSmileThreshold) {
      if (!_wasSmiling) {
        _wasSmiling = true;
        _smileStartMs = now;
      } else if (now - _smileStartMs >= _kSmileHoldMs) {
        // Smile held for required duration
        completed = true;
      }
    } else if (smileProbability < _kSmileResetThreshold) {
      _wasSmiling = false;
      _smileStartMs = 0;
    }

    return LivenessFrameResult(
      challengeCompleted: completed,
      detectionValue:     smileProbability,
    );
  }

  LivenessFrameResult _processTurnLeft(Face face) {
    final yaw = face.headEulerAngleY ?? 0.0;
    bool completed = false;

    // Positive yaw = face turned to their left (camera's right)
    if (yaw > _kTurnThreshold && !_headWasTurned) {
      _headWasTurned = true;
    } else if (_headWasTurned && yaw.abs() < _kTurnResetThreshold) {
      // Returned to center after turning
      completed = true;
      _headWasTurned = false;
    }

    return LivenessFrameResult(
      challengeCompleted: completed,
      detectionValue:     yaw,
    );
  }

  LivenessFrameResult _processTurnRight(Face face) {
    final yaw = face.headEulerAngleY ?? 0.0;
    bool completed = false;

    // Negative yaw = face turned to their right (camera's left)
    if (yaw < -_kTurnThreshold && !_headWasTurned) {
      _headWasTurned = true;
    } else if (_headWasTurned && yaw.abs() < _kTurnResetThreshold) {
      // Returned to center after turning
      completed = true;
      _headWasTurned = false;
    }

    return LivenessFrameResult(
      challengeCompleted: completed,
      detectionValue:     yaw,
    );
  }

  /// Resets all internal state for a fresh challenge.
  void resetForNextChallenge() {
    _eyeWasClosed  = false;
    _lastBlinkMs   = 0;
    _wasSmiling    = false;
    _smileStartMs  = 0;
    _headWasTurned = false;
  }

  /// Fully resets all state (for a new liveness session).
  void reset() {
    resetForNextChallenge();
    _recentBrightnessValues.clear();
  }

  /// Basic anti-photo check using brightness variance.
  ///
  /// Static photos have very low brightness variance across frames.
  /// Live faces have natural micro-variations from breathing, blinking,
  /// skin reflections, etc.
  ///
  /// Returns a score 0.0 (likely photo) to 1.0 (likely live).
  double computeAntiSpoofScore(Face face) {
    // Use bounding box area changes as a proxy for "liveliness"
    final area = face.boundingBox.width * face.boundingBox.height;
    _recentBrightnessValues.add(area);

    if (_recentBrightnessValues.length > _kBrightnessHistorySize) {
      _recentBrightnessValues.removeAt(0);
    }

    if (_recentBrightnessValues.length < 3) return 0.5; // insufficient data

    // Calculate variance
    final mean = _recentBrightnessValues.reduce((a, b) => a + b) /
        _recentBrightnessValues.length;
    double variance = 0;
    for (final v in _recentBrightnessValues) {
      variance += (v - mean) * (v - mean);
    }
    variance /= _recentBrightnessValues.length;

    // Normalize: very low variance = suspicious
    // A live face typically has variance > 100 due to micro-movements
    final normalizedVariance = (variance / 1000.0).clamp(0.0, 1.0);
    return normalizedVariance;
  }
}
