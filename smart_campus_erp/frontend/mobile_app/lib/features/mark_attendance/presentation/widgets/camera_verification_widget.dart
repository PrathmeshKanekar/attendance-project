
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../cubit/attendance_cubit.dart';
import '../cubit/attendance_state.dart';
import '../../../../core/constants/app_colors.dart';

class CameraVerificationWidget extends StatefulWidget {
  const CameraVerificationWidget({super.key});

  @override
  State<CameraVerificationWidget> createState() => _CameraVerificationWidgetState();
}

class _CameraVerificationWidgetState extends State<CameraVerificationWidget> {
  CameraController? _controller;
  FaceDetector? _faceDetector;
  bool _isBusy = false;
  int _blinkCount = 0;
  bool _leftClosed = false;
  bool _rightClosed = false;

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
        _checkBlink(face);
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      _isBusy = false;
    }
  }

  void _checkBlink(Face face) {
    final leftOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightOpen = face.rightEyeOpenProbability ?? 1.0;

    // Hysteresis thresholding for more natural blink detection
    const closedThreshold = 0.25;
    const openThreshold = 0.45;
    
    // We consider a blink valid if EITHER eye closes significantly 
    // (helps with glasses, hair, or shadows)
    bool currentlyClosed = leftOpen < closedThreshold || rightOpen < closedThreshold;

    if (currentlyClosed && !_leftClosed && !_rightClosed) {
      _leftClosed = true;
      _rightClosed = true;
    } else if (!currentlyClosed && leftOpen > openThreshold && rightOpen > openThreshold && _leftClosed && _rightClosed) {
      _leftClosed = false;
      _rightClosed = false;
      _blinkCount++;
      context.read<AttendanceCubit>().onBlinkDetected(_blinkCount);
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
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
                
                // Liveness Indicator (Blinks)
                Positioned(
                  top: 20,
                  right: 20,
                  child: _BlinkIndicator(count: state.blinkCount),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              state.currentStep == AttendanceStep.livenessDetection 
                  ? 'Please blink 3 times to verify liveness'
                  : 'Identity Matched. Ready for submission.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            
            if (state.currentStep == AttendanceStep.finalSubmission)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: ElevatedButton(
                  onPressed: () => context.read<AttendanceCubit>().submitAttendance('dummy_embedding', {}),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('MARK ATTENDANCE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCameraOverlay(AttendanceState state) {
    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        border: Border.all(
          color: state.stepStatuses[AttendanceStep.livenessDetection] == StepStatus.success 
              ? AppColors.success.withOpacity(0.5) 
              : AppColors.primaryLight.withOpacity(0.3),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(150),
      ),
      child: state.stepStatuses[AttendanceStep.livenessDetection] == StepStatus.success 
          ? const Icon(Icons.verified_user_rounded, color: AppColors.success, size: 60)
          : null,
    );
  }
}

class _BlinkIndicator extends StatelessWidget {
  final int count;
  const _BlinkIndicator({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryLight.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.remove_red_eye_rounded, color: AppColors.primaryLight, size: 16),
          const SizedBox(width: 8),
          Text(
            'BLINKS: $count / 3',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
