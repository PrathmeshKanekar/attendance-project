/// Redesigned immutable state for the face verification pipeline.
///
/// Uses a single state class with [copyWith] for efficient updates,
/// rather than a hierarchy of subclasses that lose data on transitions.
library;

import 'models/face_alignment_state.dart';
import 'models/liveness_challenge.dart';

/// Phase of the face scan workflow.
enum FaceScanPhase {
  /// Initializing camera and ML Kit.
  initializing,

  /// Camera active — waiting for face alignment.
  aligning,

  /// Face aligned — running liveness challenges.
  liveness,

  /// Liveness passed — auto-capturing photo.
  capturing,

  /// Submitting to server for verification.
  submitting,

  /// Attendance marked successfully.
  success,

  /// An error occurred.
  error,
}

class FaceScanState {
  final FaceScanPhase        phase;
  final FaceAlignmentResult  alignment;
  final LivenessProgress     livenessProgress;
  final bool                 faceDetected;
  final int                  framesProcessed;

  /// How many consecutive frames the face has been aligned.
  /// Used to ensure stable alignment before starting liveness.
  final int                  alignedFrameCount;

  /// Captured photo bytes (null until capture).
  final dynamic              capturedImageBytes;

  /// Error message (null unless phase == error).
  final String?              errorMessage;

  /// Success timestamp.
  final String?              successTime;

  /// Anti-spoof confidence score (0.0 - 1.0).
  final double               antiSpoofScore;

  const FaceScanState({
    this.phase              = FaceScanPhase.initializing,
    this.alignment          = FaceAlignmentResult.noFace,
    required this.livenessProgress,
    this.faceDetected       = false,
    this.framesProcessed    = 0,
    this.alignedFrameCount  = 0,
    this.capturedImageBytes,
    this.errorMessage,
    this.successTime,
    this.antiSpoofScore     = 0.0,
  });

  factory FaceScanState.initial() {
    return FaceScanState(
      livenessProgress: LivenessProgress.create(challengeCount: 3),
    );
  }

  FaceScanState copyWith({
    FaceScanPhase?       phase,
    FaceAlignmentResult? alignment,
    LivenessProgress?    livenessProgress,
    bool?                faceDetected,
    int?                 framesProcessed,
    int?                 alignedFrameCount,
    dynamic              capturedImageBytes,
    String?              errorMessage,
    String?              successTime,
    double?              antiSpoofScore,
    bool                 clearCapturedImage = false,
    bool                 clearError = false,
  }) {
    return FaceScanState(
      phase:              phase             ?? this.phase,
      alignment:          alignment         ?? this.alignment,
      livenessProgress:   livenessProgress  ?? this.livenessProgress,
      faceDetected:       faceDetected      ?? this.faceDetected,
      framesProcessed:    framesProcessed   ?? this.framesProcessed,
      alignedFrameCount:  alignedFrameCount ?? this.alignedFrameCount,
      capturedImageBytes: clearCapturedImage ? null : (capturedImageBytes ?? this.capturedImageBytes),
      errorMessage:       clearError ? null : (errorMessage ?? this.errorMessage),
      successTime:        successTime       ?? this.successTime,
      antiSpoofScore:     antiSpoofScore    ?? this.antiSpoofScore,
    );
  }

  /// Minimum consecutive aligned frames before starting liveness.
  /// At ~6-7 fps processing rate, 5 frames ≈ ~750ms of stable alignment.
  static const int kMinAlignedFrames = 5;

  bool get isStablyAligned => alignedFrameCount >= kMinAlignedFrames;

  String get phaseLabel {
    switch (phase) {
      case FaceScanPhase.initializing:
        return 'Starting camera...';
      case FaceScanPhase.aligning:
        return alignment.guidance.instruction;
      case FaceScanPhase.liveness:
        return livenessProgress.currentChallenge?.instruction ?? 'Processing...';
      case FaceScanPhase.capturing:
        return 'Capturing photo...';
      case FaceScanPhase.submitting:
        return 'Verifying identity...';
      case FaceScanPhase.success:
        return 'Attendance marked!';
      case FaceScanPhase.error:
        return errorMessage ?? 'An error occurred.';
    }
  }
}
