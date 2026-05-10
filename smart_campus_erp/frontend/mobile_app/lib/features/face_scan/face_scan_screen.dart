import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../core/network/api_client.dart';
import 'face_scan_state.dart';
import 'face_scan_params.dart';
import 'face_scan_notifier.dart';

class FaceScanScreen extends ConsumerStatefulWidget {
  final FaceScanParams params;
  const FaceScanScreen({super.key, required this.params});

  @override
  ConsumerState<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends ConsumerState<FaceScanScreen> {
  CameraController? _controller;
  FaceDetector? _faceDetector;
  bool _isProcessing = false;
  bool _facesDetected = false;
  bool _captureDone = false;
  CameraDescription? _frontCamera;
  int _lastProcessTime = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeCamera());
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      _frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        _frontCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      ref.read(faceScanNotifierProvider.notifier).setScanningReady();

      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      await _controller!.startImageStream(_onCameraFrame);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera error: $e')));
      }
    }
  }

  void _onCameraFrame(CameraImage image) async {
    if (_isProcessing || _faceDetector == null || _frontCamera == null || _captureDone) return;
    
    // Throttle frames to avoid CPU overload (approx 10 FPS)
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProcessTime < 100) return;
    _lastProcessTime = now;

    _isProcessing = true;
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector!.processImage(inputImage);
      
      if (mounted) {
        setState(() => _facesDetected = faces.isNotEmpty);
      }

      if (faces.isNotEmpty) {
        // Alignment check: ensure face is relatively centered and large enough
        final face = faces.first;
        final rect = face.boundingBox;
        
        // Simple heuristic: face should take up at least 30% of the width
        final faceWidthRatio = rect.width / image.width;
        if (faceWidthRatio > 0.3) {
          ref.read(faceScanNotifierProvider.notifier).processFaceDetection(face);
        }
      }

      final scanState = ref.read(faceScanNotifierProvider);
      if (scanState is FaceScanCapturing && !_captureDone) {
        _captureDone = true;
        // Small delay to ensure UI updates
        await Future.delayed(const Duration(milliseconds: 300));
        await _controller!.stopImageStream();
        
        final xfile = await _controller!.takePicture();
        final imgBytes = await xfile.readAsBytes();
        final b64 = base64Encode(imgBytes);

        await ref.read(faceScanNotifierProvider.notifier).submitAttendance(
          params: widget.params,
          faceImageB64: b64,
          api: ref.read(apiClientProvider),
        );
      }
    } catch (e) {
      debugPrint('Face detection error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _buildInputImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final camera = _frontCamera!;
      final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
      
      // On Android, the format is usually YUV_420_888 (raw 35)
      // On iOS, it's usually BGRA_8888 (raw 1111970369)
      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.yuv420;

      final planeData = image.planes.map(
        (Plane plane) {
          return InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            height: plane.height,
            width: plane.width,
          );
        },
      ).toList();

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageData,
      );
    } catch (e) {
      debugPrint('InputImage conversion error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _captureDone = true; // Prevent further processing
    _controller?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(faceScanNotifierProvider);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: Camera
          if (_controller != null && _controller!.value.isInitialized)
            CameraPreview(_controller!)
          else
            const Center(child: CircularProgressIndicator()),

          // Layer 2: Oval Cutout Overlay
          CustomPaint(
            painter: OvalCutoutPainter(facesDetected: _facesDetected),
          ),

          // Layer 3 & 4: Top instruction and step progress
          SafeArea(
            child: Column(
              children: [
                // Instruction banner
                Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Center(
                    child: Text(
                      _getInstructionText(scanState),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                // Progress tracker
                Container(
                  color: Colors.black45,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMiniStep('Location', Colors.green, true),
                      _buildMiniStep('Face', _facesDetected ? Colors.green : Colors.white70, true),
                      _buildMiniStep('Blinks', _getBlinkStepColor(scanState), true),
                      _buildMiniStep('Done', scanState is FaceScanSuccess ? Colors.green : Colors.white70, false),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Layer 5: Blink visual counters
          Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                final blinkCount = scanState is FaceScanBlinking ? scanState.count : (scanState is FaceScanCapturing ? 3 : 0);
                final isActive = index < blinkCount;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFF16A34A) : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: Icon(
                      isActive ? Icons.check : Icons.visibility_off,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                );
              }),
            ),
          ),

          // Layer 6: State overlays
          _buildStateOverlay(scanState),
        ],
      ),
    );
  }

  Widget _buildMiniStep(String label, Color color, bool showArrow) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        if (showArrow) ...[
          const SizedBox(width: 4),
          Icon(Icons.arrow_forward_ios, color: color.withOpacity(0.5), size: 10),
        ]
      ],
    );
  }

  Color _getBlinkStepColor(FaceScanState state) {
    if (state is FaceScanBlinking) return Colors.blue;
    if (state is FaceScanCapturing || state is FaceScanSuccess) return Colors.green;
    return Colors.white70;
  }

  String _getInstructionText(FaceScanState state) {
    if (state is FaceScanInitializing) return 'Starting camera...';
    if (state is FaceScanScanning) {
      return _facesDetected ? 'Face detected ✓ Now blink 3 times' : 'Position your face in the oval';
    }
    if (state is FaceScanBlinking) return 'Blink ${state.count}/3 — keep going...';
    if (state is FaceScanCapturing) return '3 blinks complete — hold still...';
    if (state is FaceScanVerifying) return 'Verifying your identity...';
    return 'Processing...';
  }

  Widget _buildStateOverlay(FaceScanState state) {
    if (state is FaceScanVerifying) {
      return Container(
        color: Colors.black54,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Verifying...', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      );
    }
    if (state is FaceScanSuccess) {
      return Container(
        color: const Color(0xFF16A34A),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 90),
              const SizedBox(height: 16),
              const Text('Attendance Marked!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Marked at: ${state.markedAt}', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF16A34A)),
                onPressed: () => context.go('/student/dashboard'),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }
    if (state is FaceScanFailed) {
      return Container(
        color: const Color(0xFFDC2626).withOpacity(0.9),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cancel, color: Colors.white, size: 90),
                const SizedBox(height: 16),
                const Text('Verification Failed', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(state.reason, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFDC2626)),
                      onPressed: () {
                        ref.read(faceScanNotifierProvider.notifier).reset();
                        _captureDone = false;
                        _controller!.startImageStream(_onCameraFrame);
                      },
                      child: const Text('Try Again'),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class OvalCutoutPainter extends CustomPainter {
  final bool facesDetected;
  OvalCutoutPainter({required this.facesDetected});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = Colors.black.withOpacity(0.6);

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.75,
      height: size.height * 0.50,
    );

    final ovalPath = Path()..addOval(ovalRect);
    final rectPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path.combine(PathOperation.difference, rectPath, ovalPath);

    canvas.drawPath(cutoutPath, backgroundPaint);

    final borderPaint = Paint()
      ..color = facesDetected ? const Color(0xFF16A34A) : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant OvalCutoutPainter oldDelegate) {
    return oldDelegate.facesDetected != facesDetected;
  }
}
