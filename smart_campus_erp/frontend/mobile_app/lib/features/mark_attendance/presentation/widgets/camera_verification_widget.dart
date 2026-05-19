// presentation/widgets/camera_verification_widget.dart
// ─────────────────────────────────────────────────────────────────────────────
// Camera face recognition and liveness detection.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../cubit/attendance_cubit.dart';
import '../cubit/attendance_state.dart';
import 'package:smart_campus_app/core/constants/app_colors.dart';

class CameraVerificationWidget extends StatefulWidget {
  const CameraVerificationWidget({super.key});

  @override
  State<CameraVerificationWidget> createState() => _CameraVerificationWidgetState();
}

class _CameraVerificationWidgetState extends State<CameraVerificationWidget> {
  CameraController? _controller;
  FaceDetector? _faceDetector;
  bool _isBusy = false;
  
  // FIXED: Liveness Scan Blink Bug - Synchronous Local Instance Tracking Task 3
  int _blinkCount = 0;
  bool _eyesClosed = false;           
  DateTime? _blinkStartTime;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);
    
    _controller = CameraController(front, ResolutionPreset.medium, enableAudio: false);
    await _controller!.initialize();
    
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
      ),
    );

    _controller!.startImageStream(_processImage);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isBusy) return;
    _isBusy = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector!.processImage(inputImage);
      
      if (faces.isNotEmpty) {
        final face = faces.first;
        if (!mounted) return;
        final isGoodPosition = _validateFacePosition(face, image);
        
        if (isGoodPosition && mounted) {
          _checkBlink(face);
        }
      } else {
        if (mounted) {
          context.read<AttendanceCubit>().updateFaceGuidance("Face not detected", false);
        }
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      _isBusy = false;
    }
  }

  bool _validateFacePosition(Face face, CameraImage image) {
    if (!mounted) return false;
    final boundingBox = face.boundingBox;
    
    // 1. Check Face Size (Must be close enough)
    final faceWidthRatio = boundingBox.width / image.width;
    if (faceWidthRatio < 0.3) {
      context.read<AttendanceCubit>().updateFaceGuidance("Move closer to camera", false);
      return false;
    }

    // 2. Check Face Centering
    final centerX = boundingBox.center.dx;
    final centerY = boundingBox.center.dy;
    
    final relX = centerX / image.width;
    final relY = centerY / image.height;

    // Must be in the central 40% of the screen
    if (relX < 0.2 || relX > 0.8 || relY < 0.2 || relY > 0.8) {
      context.read<AttendanceCubit>().updateFaceGuidance("Center your face", false);
      return false;
    }

    context.read<AttendanceCubit>().updateFaceGuidance("Perfect! Now blink naturally", true);
    return true;
  }

  // FIXED: Liveness Scan Blink Bug - Synchronous Local Instance Tracking Task 3
  void _checkBlink(Face face) {
    final leftOpen  = face.leftEyeOpenProbability  ?? 1.0;
    final rightOpen = face.rightEyeOpenProbability ?? 1.0;

    const closedThresh = 0.30; // slightly more tolerant

    final eitherClosed = leftOpen < closedThresh || rightOpen < closedThresh;

    if (eitherClosed && !_eyesClosed) {
      // Blink START — eyes just closed
      _eyesClosed     = true;
      _blinkStartTime = DateTime.now();
      debugPrint("BLINK START: L=${leftOpen.toStringAsFixed(2)} R=${rightOpen.toStringAsFixed(2)}");
    } else if (!eitherClosed && _eyesClosed) {
      // Blink END — eyes reopened
      _eyesClosed = false;
      if (_blinkStartTime == null) return;
      
      final elapsed = DateTime.now().difference(_blinkStartTime!).inMilliseconds;

      // Valid blink: eyes were closed for a reasonable amount of time
      if (elapsed >= 50 && elapsed < 2000) {
        _blinkCount++;
        debugPrint("BLINK COUNTED: $_blinkCount (duration: ${elapsed}ms)");

        if (mounted) {
          setState(() {}); // refresh _BlinkIndicator count display
          context.read<AttendanceCubit>().onBlinkDetected(_blinkCount);
        }
      } else {
        debugPrint("BLINK IGNORED (duration: ${elapsed}ms)");
      }
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    try {
      final sensorOrientation = _controller!.description.sensorOrientation;
      InputImageRotation? rotation;
      if (Platform.isAndroid) {
        switch (sensorOrientation) {
          case 90:  rotation = InputImageRotation.rotation90deg; break;
          case 180: rotation = InputImageRotation.rotation180deg; break;
          case 270: rotation = InputImageRotation.rotation270deg; break;
          default:  rotation = InputImageRotation.rotation0deg; break;
        }
      }
      rotation ??= InputImageRotation.rotation0deg;

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint("Error in _inputImageFromCameraImage: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Container(
        height: 300,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(24)),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return BlocBuilder<AttendanceCubit, AttendanceState>(
      builder: (context, state) {
        return Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                // Camera Preview with Rounded Corners
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CameraPreview(_controller!),
                  ),
                ),
                
                // Futuristic Overlay
                _buildCameraOverlay(state),

                // Guidance Overlay
                if (state.currentStep == AttendanceStep.livenessDetection)
                  Positioned(
                    bottom: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: state.isFaceCentered ? AppColors.success : AppColors.warning,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        state.faceGuidance ?? "Align your face...",
                        style: TextStyle(
                          color: state.isFaceCentered ? Colors.white : Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                
                // Liveness Indicator (Blinks)
                Positioned(
                  top: 20,
                  right: 20,
                  child: _BlinkIndicator(count: state.blinkCount),
                ),

                // Centering Guide (Static Crosshair)
                if (state.currentStep == AttendanceStep.livenessDetection && !state.isFaceCentered)
                  Opacity(
                    opacity: 0.3,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 1),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.add, color: Colors.white, size: 40),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              state.currentStep == AttendanceStep.livenessDetection 
                  ? 'Blink detection helps us ensure you are a real person.'
                  : 'Step complete. Proceed to final submission.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            
            // FIXED: Student UI Button Gate - Button visible only when gpsValidation is success AND isInsideRoom is true Task 2
            if ((state.currentStep == AttendanceStep.finalSubmission || state.currentStep == AttendanceStep.faceMatch) &&
                state.stepStatuses[AttendanceStep.gpsValidation] == StepStatus.success &&
                state.isInsideRoom)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: ElevatedButton(
                  onPressed: state.stepStatuses[AttendanceStep.finalSubmission] == StepStatus.processing
                      ? null
                      : () => context.read<AttendanceCubit>().submitAttendance('dummy_embedding', {}),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                  child: state.stepStatuses[AttendanceStep.finalSubmission] == StepStatus.processing
                      ? const SizedBox(
                          height: 24, 
                          width: 24, 
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        )
                      : const Text('CONFIRM & MARK ATTENDANCE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCameraOverlay(AttendanceState state) {
    bool isLivenessSuccess = state.stepStatuses[AttendanceStep.livenessDetection] == StepStatus.success;

    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        border: Border.all(
          color: isLivenessSuccess 
              ? AppColors.success.withOpacity(0.8) 
              : (state.isFaceCentered ? AppColors.primaryLight : Colors.white24),
          width: 3,
        ),
        borderRadius: BorderRadius.circular(150),
        boxShadow: [
          if (isLivenessSuccess)
            BoxShadow(color: AppColors.success.withOpacity(0.2), blurRadius: 20, spreadRadius: 5),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isLivenessSuccess)
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user_rounded, color: AppColors.success, size: 70),
                SizedBox(height: 8),
                Text("VERIFIED", style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, letterSpacing: 2)),
              ],
            ),
          
          if (!isLivenessSuccess && state.isFaceCentered)
            const Positioned(
              left: 0,
              right: 0,
              child: _ScanLine(),
            ),
        ],
      ),
    );
  }
}

class _ScanLine extends StatefulWidget {
  const _ScanLine();

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 40 + (180 * _controller.value)),
          child: child,
        );
      },
      child: Center(
        child: Container(
          width: 200,
          height: 2,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryLight.withOpacity(0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlinkIndicator extends StatelessWidget {
  final int count;
  const _BlinkIndicator({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: count >= 3 ? AppColors.success : AppColors.primaryLight,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            count >= 3 ? Icons.check_circle_rounded : Icons.remove_red_eye_rounded, 
            color: count >= 3 ? AppColors.success : AppColors.primaryLight, 
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'BLINKS: $count / 3',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
