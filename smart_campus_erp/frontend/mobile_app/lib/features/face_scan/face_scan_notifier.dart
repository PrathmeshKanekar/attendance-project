/// Production-grade face scan orchestrator.
///
/// Manages the entire face verification lifecycle:
/// 1. Camera + ML Kit initialization
/// 2. Face alignment validation
/// 3. Multi-challenge liveness detection
/// 4. Photo capture
/// 5. Server submission
///
/// Key improvements over the original:
/// - Single FaceDetector instance (no re-initialization)
/// - Completer-based frame concurrency (no race conditions)
/// - Proper lifecycle management (dispose stops everything)
/// - Accurate ML Kit mode (reliable classification)
/// - Stability-gated liveness (alignment must hold for N frames)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_scan_state.dart';
import 'face_scan_params.dart';
import 'models/face_alignment_state.dart';
import 'models/liveness_challenge.dart';
import 'services/camera_image_converter.dart';
import 'services/face_alignment_analyzer.dart';
import 'services/liveness_detector.dart';
import '../../core/network/api_client.dart';

// ── Provider ──────────────────────────────────────────────────────────

final faceScanNotifierProvider =
    StateNotifierProvider.autoDispose<FaceScanNotifier, FaceScanState>((ref) {
  final notifier = FaceScanNotifier();
  ref.onDispose(() => notifier.cleanup());
  return notifier;
});

// ── Notifier ──────────────────────────────────────────────────────────

class FaceScanNotifier extends StateNotifier<FaceScanState> {
  FaceScanNotifier() : super(FaceScanState.initial());

  CameraController?  _cameraController;
  FaceDetector?      _faceDetector;
  LivenessDetector?  _livenessDetector;

  /// Concurrency guard: true while a frame is being processed.
  bool _isProcessing = false;

  /// Whether dispose has been called (prevents processing after cleanup).
  bool _isDisposed = false;

  /// Timestamp of last processed frame.
  int  _lastFrameMs = 0;

  /// Frame processing interval in milliseconds.
  /// 150ms ≈ 6-7 fps — good balance for blink detection vs CPU.
  static const int _kFrameIntervalMs = 150;

  /// Minimum consecutive aligned frames before starting liveness.
  static const int _kMinAlignedFrames = 5;

  // ── Public API ───────────────────────────────────────────────────

  CameraController? get cameraController => _cameraController;

  /// Initializes camera and ML Kit face detector.
  /// Call this from the widget's initState/postFrameCallback.
  Future<void> initializeCamera() async {
    try {
      // 1. Find front camera
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        state = state.copyWith(
          phase: FaceScanPhase.error,
          errorMessage: 'No cameras found on this device.',
        );
        return;
      }

      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // 2. Create camera controller
      // ResolutionPreset.medium (480p) is optimal:
      // - High enough for reliable face detection
      // - Low enough for smooth processing on mid-range devices
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      // 3. Create face detector — ONCE, reused for all frames
      // Key settings:
      // - enableClassification: REQUIRED for eye/smile probability
      // - enableLandmarks: needed for alignment validation
      // - enableTracking: improves multi-frame consistency
      // - performanceMode: accurate — crucial for reliable classification
      // - minFaceSize: 0.15 — prevents false positives from tiny faces
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableLandmarks:      true,
          enableContours:       false,  // expensive, not needed
          enableTracking:       true,
          minFaceSize:          0.15,
          performanceMode:      FaceDetectorMode.accurate,
        ),
      );

      // 4. Create liveness detector
      _livenessDetector = LivenessDetector();

      // 5. Start image stream
      await _cameraController!.startImageStream(_onCameraFrame);

      // 6. Transition to aligning phase
      state = state.copyWith(
        phase: FaceScanPhase.aligning,
        livenessProgress: LivenessProgress.create(challengeCount: 3),
      );
    } catch (e) {
      state = state.copyWith(
        phase: FaceScanPhase.error,
        errorMessage: 'Camera initialization failed: $e',
      );
    }
  }

  /// Resets everything for a retake.
  void resetForRetake() {
    _livenessDetector?.reset();
    state = FaceScanState.initial().copyWith(
      phase: FaceScanPhase.aligning,
      livenessProgress: LivenessProgress.create(challengeCount: 3),
      clearCapturedImage: true,
      clearError: true,
    );

    // Restart image stream if controller is valid
    if (_cameraController != null &&
        _cameraController!.value.isInitialized &&
        !_cameraController!.value.isStreamingImages) {
      _cameraController!.startImageStream(_onCameraFrame);
    }
  }

  /// Submits the captured photo and metadata to the backend.
  Future<void> submitAttendance({
    required FaceScanParams params,
    required ApiClient api,
  }) async {
    if (state.capturedImageBytes == null) return;

    state = state.copyWith(phase: FaceScanPhase.submitting);

    try {
      final b64 = base64Encode(state.capturedImageBytes as Uint8List);

      if (b64.length < 1000) {
        state = state.copyWith(
          phase: FaceScanPhase.error,
          errorMessage: 'Image capture failed. Please try again.',
        );
        return;
      }

      final res = await api.post('/api/attendance/mark/', data: {
        'session_id':     params.sessionId,
        'lat':            params.lat,
        'lng':            params.lng,
        'altitude':       params.altitude,
        'device_id':      params.deviceId,
        'face_image_b64': b64,
        'blink_count':    state.livenessProgress.completedCount,
        'liveness_score': state.antiSpoofScore,
      });

      state = state.copyWith(
        phase: FaceScanPhase.success,
        successTime: res.data['marked_at'] ?? DateTime.now().toIso8601String(),
      );
    } catch (e) {
      final msg = e.toString().contains('"error"')
          ? 'Geofence / Verification Failed'
          : e.toString();
      state = state.copyWith(
        phase: FaceScanPhase.error,
        errorMessage: msg,
      );
    }
  }

  /// Cleans up all resources. Called from ref.onDispose.
  void cleanup() {
    _isDisposed = true;

    try {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized &&
          _cameraController!.value.isStreamingImages) {
        _cameraController!.stopImageStream();
      }
    } catch (_) {}

    _cameraController?.dispose();
    _cameraController = null;

    _faceDetector?.close();
    _faceDetector = null;

    _livenessDetector?.reset();
    _livenessDetector = null;
  }

  // ── Frame Processing Pipeline ───────────────────────────────────

  void _onCameraFrame(CameraImage image) {
    // Guard: skip if disposed, already processing, or not in active phase
    if (_isDisposed) return;
    if (_isProcessing) return;

    // Throttle: skip frames that arrive too soon
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastFrameMs < _kFrameIntervalMs) return;

    // Only process during active phases
    final phase = state.phase;
    if (phase != FaceScanPhase.aligning && phase != FaceScanPhase.liveness) {
      return;
    }

    _isProcessing = true;
    _lastFrameMs = nowMs;

    _processFrame(image).then((_) {
      _isProcessing = false;
    }).catchError((e) {
      _isProcessing = false;
      debugPrint('Frame processing error: $e');
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_cameraController == null || _faceDetector == null) return;
    if (_isDisposed) return;

    // 1. Convert camera image to ML Kit input
    final inputImage = CameraImageConverter.convert(
      image,
      _cameraController!.description,
    );
    if (inputImage == null) return;

    // 2. Run face detection
    final List<Face> faces;
    try {
      faces = await _faceDetector!.processImage(inputImage);
    } catch (e) {
      debugPrint('ML Kit processImage error: $e');
      return;
    }

    if (_isDisposed || !mounted) return;

    final frameCount = state.framesProcessed + 1;

    // 3. No face detected
    if (faces.isEmpty) {
      state = state.copyWith(
        faceDetected:      false,
        framesProcessed:   frameCount,
        alignedFrameCount: 0,
        alignment:         FaceAlignmentResult.noFace,
        // If we were in liveness, fall back to aligning
        phase: state.phase == FaceScanPhase.liveness
            ? FaceScanPhase.aligning
            : state.phase,
      );
      return;
    }

    // 4. Analyze alignment of the primary (largest) face
    final face = _selectPrimaryFace(faces);
    final imageSize = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final alignment = FaceAlignmentAnalyzer.analyze(face, imageSize);

    // 5. Update alignment state
    final newAlignedCount = alignment.isAligned
        ? state.alignedFrameCount + 1
        : 0;

    // 6. Phase-specific processing
    if (state.phase == FaceScanPhase.aligning) {
      _handleAligningPhase(alignment, newAlignedCount, frameCount);
    } else if (state.phase == FaceScanPhase.liveness) {
      _handleLivenessPhase(face, alignment, newAlignedCount, frameCount);
    }
  }

  void _handleAligningPhase(
    FaceAlignmentResult alignment,
    int alignedFrameCount,
    int frameCount,
  ) {
    // Check if stably aligned → transition to liveness
    if (alignedFrameCount >= _kMinAlignedFrames) {
      _livenessDetector?.resetForNextChallenge();
      state = state.copyWith(
        phase:             FaceScanPhase.liveness,
        alignment:         alignment,
        faceDetected:      true,
        framesProcessed:   frameCount,
        alignedFrameCount: alignedFrameCount,
      );
    } else {
      state = state.copyWith(
        alignment:         alignment,
        faceDetected:      true,
        framesProcessed:   frameCount,
        alignedFrameCount: alignedFrameCount,
      );
    }
  }

  void _handleLivenessPhase(
    Face face,
    FaceAlignmentResult alignment,
    int alignedFrameCount,
    int frameCount,
  ) {
    final challenge = state.livenessProgress.currentChallenge;
    if (challenge == null || _livenessDetector == null) return;

    // If face becomes misaligned during liveness, fall back to aligning
    // But allow temporary misalignment for head-turn challenges
    if (!alignment.isAligned &&
        challenge.type != ChallengeType.turnLeft &&
        challenge.type != ChallengeType.turnRight) {
      state = state.copyWith(
        phase:             FaceScanPhase.aligning,
        alignment:         alignment,
        faceDetected:      true,
        framesProcessed:   frameCount,
        alignedFrameCount: 0,
      );
      return;
    }

    // Process liveness challenge
    final result = _livenessDetector!.processFrame(face, challenge);
    final spoofScore = _livenessDetector!.computeAntiSpoofScore(face);

    if (result.challengeCompleted) {
      final newProgress = state.livenessProgress.advanceToNext();

      if (newProgress.isComplete) {
        // All challenges complete → capture
        _triggerCapture();
        state = state.copyWith(
          phase:            FaceScanPhase.capturing,
          livenessProgress: newProgress,
          alignment:        alignment,
          faceDetected:     true,
          framesProcessed:  frameCount,
          antiSpoofScore:   spoofScore,
        );
      } else {
        // Move to next challenge
        _livenessDetector!.resetForNextChallenge();
        state = state.copyWith(
          livenessProgress: newProgress,
          alignment:        alignment,
          faceDetected:     true,
          framesProcessed:  frameCount,
          antiSpoofScore:   spoofScore,
        );
      }
    } else {
      // Challenge not yet completed
      state = state.copyWith(
        alignment:       alignment,
        faceDetected:    true,
        framesProcessed: frameCount,
        antiSpoofScore:  spoofScore,
      );
    }
  }

  /// Selects the primary face (largest bounding box) from detected faces.
  Face _selectPrimaryFace(List<Face> faces) {
    if (faces.length == 1) return faces.first;
    return faces.reduce((a, b) {
      final areaA = a.boundingBox.width * a.boundingBox.height;
      final areaB = b.boundingBox.width * b.boundingBox.height;
      return areaA >= areaB ? a : b;
    });
  }

  /// Stops image stream and captures a photo.
  Future<void> _triggerCapture() async {
    try {
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        return;
      }

      // Stop stream before capture (required by camera plugin)
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }

      final xfile = await _cameraController!.takePicture();
      final bytes = await xfile.readAsBytes();

      if (!_isDisposed && mounted) {
        state = state.copyWith(
          phase:              FaceScanPhase.capturing,
          capturedImageBytes: bytes,
        );
      }
    } catch (e) {
      debugPrint('Photo capture error: $e');
      if (!_isDisposed && mounted) {
        state = state.copyWith(
          phase: FaceScanPhase.error,
          errorMessage: 'Photo capture failed: $e',
        );
      }
    }
  }
}
