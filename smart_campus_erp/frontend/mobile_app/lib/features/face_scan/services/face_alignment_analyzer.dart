/// Production-grade face alignment analyzer.
///
/// Validates that the detected face is:
/// - Centered within the guide oval
/// - At the correct distance (size ratio)
/// - Not tilted or rotated excessively
/// - Eyes are open (for liveness readiness)
///
/// All thresholds are tuned for front-camera selfie-style capture
/// on mobile devices.
library;

import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/face_alignment_state.dart';

class FaceAlignmentAnalyzer {
  FaceAlignmentAnalyzer._();

  // ── Thresholds ─────────────────────────────────────────────────────

  /// Maximum allowed offset from frame center (as fraction of frame dimension).
  /// 0.15 = face center must be within 15% of frame center.
  static const double _kMaxCenterOffsetX = 0.18;
  static const double _kMaxCenterOffsetY = 0.18;

  /// Face bounding box height as fraction of frame height.
  /// Too small = too far, too large = too close.
  static const double _kMinFaceRatio = 0.20; // minimum 20% of frame
  static const double _kMaxFaceRatio = 0.55; // maximum 55% of frame
  static const double _kIdealFaceRatio = 0.35; // ideal ~35% of frame

  /// Maximum allowed head rotation in degrees.
  static const double _kMaxYaw   = 18.0; // left-right rotation
  static const double _kMaxPitch = 18.0; // up-down rotation
  static const double _kMaxRoll  = 15.0; // head tilt

  /// Minimum eye-open probability to consider "awake/ready".
  static const double _kMinEyeOpen = 0.40;

  // ── Public API ─────────────────────────────────────────────────────

  /// Analyzes face alignment within a frame of [imageSize].
  ///
  /// Returns a [FaceAlignmentResult] describing the current alignment state,
  /// offsets, angles, and a composite quality score.
  ///
  /// The [face] parameter must come from ML Kit with `enableClassification: true`
  /// so that eye probabilities are available.
  static FaceAlignmentResult analyze(Face face, Size imageSize) {
    // ── Extract measurements ──
    final bbox = face.boundingBox;
    final faceCenterX = bbox.left + bbox.width / 2;
    final faceCenterY = bbox.top + bbox.height / 2;
    final frameCenterX = imageSize.width / 2;
    final frameCenterY = imageSize.height / 2;

    // Normalized center offset (-1.0 to 1.0)
    final offsetX = (faceCenterX - frameCenterX) / (imageSize.width / 2);
    final offsetY = (faceCenterY - frameCenterY) / (imageSize.height / 2);

    // Face size relative to frame
    final faceRatio = bbox.height / imageSize.height;
    final sizeRatio = faceRatio / _kIdealFaceRatio; // 1.0 = ideal

    // Head angles (ML Kit provides these when enableTracking is true)
    final yaw   = face.headEulerAngleY ?? 0.0; // left-right
    final pitch  = face.headEulerAngleX ?? 0.0; // up-down
    final roll  = face.headEulerAngleZ ?? 0.0; // tilt

    // Eye openness
    final leftEye  = face.leftEyeOpenProbability  ?? 1.0;
    final rightEye = face.rightEyeOpenProbability ?? 1.0;

    // ── Priority-ordered checks ──
    // Most critical issues first (size → position → rotation → eyes)

    FaceAlignmentStatus status;

    // 1. Size check
    if (faceRatio < _kMinFaceRatio) {
      status = FaceAlignmentStatus.tooFar;
    } else if (faceRatio > _kMaxFaceRatio) {
      status = FaceAlignmentStatus.tooClose;
    }
    // 2. Center check
    else if (offsetX < -_kMaxCenterOffsetX) {
      // Face is to the left in camera coordinates.
      // On front camera (mirrored), this appears as right to the user.
      status = FaceAlignmentStatus.offCenterRight;
    } else if (offsetX > _kMaxCenterOffsetX) {
      status = FaceAlignmentStatus.offCenterLeft;
    } else if (offsetY < -_kMaxCenterOffsetY) {
      status = FaceAlignmentStatus.offCenterUp;
    } else if (offsetY > _kMaxCenterOffsetY) {
      status = FaceAlignmentStatus.offCenterDown;
    }
    // 3. Rotation check
    else if (yaw < -_kMaxYaw) {
      status = FaceAlignmentStatus.tiltedRight;
    } else if (yaw > _kMaxYaw) {
      status = FaceAlignmentStatus.tiltedLeft;
    } else if (pitch < -_kMaxPitch) {
      status = FaceAlignmentStatus.tiltedDown;
    } else if (pitch > _kMaxPitch) {
      status = FaceAlignmentStatus.tiltedUp;
    } else if (roll.abs() > _kMaxRoll) {
      // Head is tilted sideways
      status = roll > 0
          ? FaceAlignmentStatus.tiltedLeft
          : FaceAlignmentStatus.tiltedRight;
    }
    // 4. Eye check — only block alignment, don't block during blink challenges
    else if (leftEye < _kMinEyeOpen && rightEye < _kMinEyeOpen) {
      status = FaceAlignmentStatus.eyesClosed;
    }
    // All checks passed
    else {
      status = FaceAlignmentStatus.aligned;
    }

    // ── Quality score ──
    // Composite 0.0–1.0 score based on all factors
    final centerScore = 1.0 - (offsetX.abs() + offsetY.abs()) / 2.0;
    final sizeScore   = 1.0 - (sizeRatio - 1.0).abs().clamp(0.0, 1.0);
    final angleScore  = 1.0 - ((yaw.abs() / 45.0) + (pitch.abs() / 45.0) + (roll.abs() / 45.0)) / 3.0;
    final eyeScore    = ((leftEye + rightEye) / 2.0).clamp(0.0, 1.0);

    final quality = (centerScore * 0.30 +
                     sizeScore   * 0.30 +
                     angleScore  * 0.25 +
                     eyeScore    * 0.15)
        .clamp(0.0, 1.0);

    return FaceAlignmentResult(
      status:       status,
      centerOffsetX: offsetX,
      centerOffsetY: offsetY,
      sizeRatio:    sizeRatio,
      headYaw:      yaw,
      headPitch:    pitch,
      headRoll:     roll,
      leftEyeOpen:  leftEye,
      rightEyeOpen: rightEye,
      qualityScore: quality,
    );
  }
}
