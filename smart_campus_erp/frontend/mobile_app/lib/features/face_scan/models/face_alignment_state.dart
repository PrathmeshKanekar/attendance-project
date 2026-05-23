/// Production-grade face alignment state model.
///
/// Defines all possible alignment conditions that the face analyzer
/// can detect, along with UI guidance metadata for each state.
library;

import 'package:flutter/material.dart';

/// Enumeration of all face alignment conditions.
enum FaceAlignmentStatus {
  noFace,
  tooFar,
  tooClose,
  offCenterLeft,
  offCenterRight,
  offCenterUp,
  offCenterDown,
  tiltedLeft,
  tiltedRight,
  tiltedUp,
  tiltedDown,
  eyesClosed,
  aligned,
}

/// UI guidance configuration for each alignment state.
class AlignmentGuidance {
  final String instruction;
  final Color  overlayColor;
  final IconData icon;

  const AlignmentGuidance({
    required this.instruction,
    required this.overlayColor,
    required this.icon,
  });
}

/// Maps each alignment status to user-facing guidance.
AlignmentGuidance getGuidance(FaceAlignmentStatus status) {
  switch (status) {
    case FaceAlignmentStatus.noFace:
      return const AlignmentGuidance(
        instruction: 'Position your face inside the oval',
        overlayColor: Color(0xFFEF4444),
        icon: Icons.face_retouching_off,
      );
    case FaceAlignmentStatus.tooFar:
      return const AlignmentGuidance(
        instruction: 'Move closer to the camera',
        overlayColor: Color(0xFFF59E0B),
        icon: Icons.zoom_in,
      );
    case FaceAlignmentStatus.tooClose:
      return const AlignmentGuidance(
        instruction: 'Move farther from the camera',
        overlayColor: Color(0xFFF59E0B),
        icon: Icons.zoom_out,
      );
    case FaceAlignmentStatus.offCenterLeft:
      return const AlignmentGuidance(
        instruction: 'Move your face to the right',
        overlayColor: Color(0xFFF59E0B),
        icon: Icons.arrow_forward,
      );
    case FaceAlignmentStatus.offCenterRight:
      return const AlignmentGuidance(
        instruction: 'Move your face to the left',
        overlayColor: Color(0xFFF59E0B),
        icon: Icons.arrow_back,
      );
    case FaceAlignmentStatus.offCenterUp:
      return const AlignmentGuidance(
        instruction: 'Move your face down',
        overlayColor: Color(0xFFF59E0B),
        icon: Icons.arrow_downward,
      );
    case FaceAlignmentStatus.offCenterDown:
      return const AlignmentGuidance(
        instruction: 'Move your face up',
        overlayColor: Color(0xFFF59E0B),
        icon: Icons.arrow_upward,
      );
    case FaceAlignmentStatus.tiltedLeft:
      return const AlignmentGuidance(
        instruction: 'Tilt your head to the right',
        overlayColor: Color(0xFFF59E0B),
        icon: Icons.rotate_right,
      );
    case FaceAlignmentStatus.tiltedRight:
      return const AlignmentGuidance(
        instruction: 'Tilt your head to the left',
        overlayColor: Color(0xFFF59E0B),
        icon: Icons.rotate_left,
      );
    case FaceAlignmentStatus.tiltedUp:
      return const AlignmentGuidance(
        instruction: 'Look straight at the camera',
        overlayColor: Color(0xFFF59E0B),
        icon: Icons.vertical_align_center,
      );
    case FaceAlignmentStatus.tiltedDown:
      return const AlignmentGuidance(
        instruction: 'Raise your chin slightly',
        overlayColor: Color(0xFFF59E0B),
        icon: Icons.vertical_align_top,
      );
    case FaceAlignmentStatus.eyesClosed:
      return const AlignmentGuidance(
        instruction: 'Open your eyes',
        overlayColor: Color(0xFFF59E0B),
        icon: Icons.visibility,
      );
    case FaceAlignmentStatus.aligned:
      return const AlignmentGuidance(
        instruction: 'Perfect! Hold steady...',
        overlayColor: Color(0xFF22C55E),
        icon: Icons.check_circle_outline,
      );
  }
}

/// Result of face alignment analysis for a single frame.
class FaceAlignmentResult {
  final FaceAlignmentStatus status;

  /// Normalized center offset (0.0 = perfectly centered, 1.0 = at edge).
  final double centerOffsetX;
  final double centerOffsetY;

  /// Normalized face size ratio relative to optimal (1.0 = ideal).
  final double sizeRatio;

  /// Head Euler angles from ML Kit.
  final double headYaw;
  final double headPitch;
  final double headRoll;

  /// Eye open probabilities.
  final double leftEyeOpen;
  final double rightEyeOpen;

  /// Overall alignment quality score (0.0 - 1.0).
  final double qualityScore;

  const FaceAlignmentResult({
    required this.status,
    this.centerOffsetX = 0.0,
    this.centerOffsetY = 0.0,
    this.sizeRatio     = 0.0,
    this.headYaw       = 0.0,
    this.headPitch     = 0.0,
    this.headRoll      = 0.0,
    this.leftEyeOpen   = 1.0,
    this.rightEyeOpen  = 1.0,
    this.qualityScore  = 0.0,
  });

  static const noFace = FaceAlignmentResult(
    status: FaceAlignmentStatus.noFace,
  );

  AlignmentGuidance get guidance => getGuidance(status);

  bool get isAligned => status == FaceAlignmentStatus.aligned;
}
