import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/services/device_service.dart';
import 'providers/student_providers.dart';

class FaceScanScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> session;
  final double               lat;
  final double               lng;
  final double               altitude;

  const FaceScanScreen({
    super.key,
    required this.session,
    required this.lat,
    required this.lng,
    required this.altitude,
  });

  @override
  ConsumerState<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends ConsumerState<FaceScanScreen> {
  CameraController? _controller;
  FaceDetector?     _faceDetector;
  XFile?            _capturedImage;
  Uint8List?        _capturedImageBytes;
  bool              _isInitializing = true;
  bool              _isSubmitting   = false;
  bool              _isProcessingFrame = false;
  String?           _initError;

  // Blink state
  int               _blinkCount = 0;
  bool              _eyeWasClosed = false;
  bool              _livenessPassed = false;
  bool              _faceDetected = false;

  // Sensors
  double            _compassHeading = 0.0;
  double            _maxAcceleration = 0.0;
  StreamSubscription? _compassSub;
  StreamSubscription? _accelSub;

  final _deviceService   = DeviceService();

  @override
  void initState() {
    super.initState();
    // CRITICAL FIX: Guard against empty session
    if (widget.session.isEmpty) {
      _initError = 'Session data not found.';
      _isInitializing = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  @override
  void dispose() {
    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream();
    }
    _controller?.dispose();
    _faceDetector?.close();
    _compassSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _isInitializing = false;
        _initError = 'Camera permission denied. Please allow camera access in settings.';
      });
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _isInitializing = false;
          _initError = 'No cameras found on this device.';
        });
        return;
      }

      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      // Initialize Face Detector
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      // Start Image Stream for Liveness Check
      await _controller!.startImageStream(_processCameraFrame);

      // Start Sensors
      _compassSub = FlutterCompass.events?.listen((event) {
        _compassHeading = event.heading ?? 0.0;
      });
      _accelSub = accelerometerEventStream().listen((event) {
        final accel = (event.x * event.x + event.y * event.y + event.z * event.z);
        if (accel > _maxAcceleration) _maxAcceleration = accel;
      });

      if (mounted) {
        setState(() => _isInitializing = false);
      }
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _initError = 'Failed to initialize camera: $e';
      });
    }
  }

  void _processCameraFrame(CameraImage image) async {
    if (_isProcessingFrame || _faceDetector == null || _capturedImage != null) return;
    _isProcessingFrame = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector!.processImage(inputImage);

      if (faces.isEmpty) {
        if (mounted && _faceDetected) {
          setState(() => _faceDetected = false);
        }
        return;
      }

      final face = faces.first;
      if (mounted && !_faceDetected) {
        setState(() => _faceDetected = true);
      }

      // Blink Detection Logic
      final leftEyeOpenProb = face.leftEyeOpenProbability ?? 1.0;
      final rightEyeOpenProb = face.rightEyeOpenProbability ?? 1.0;
      final avgOpen = (leftEyeOpenProb + rightEyeOpenProb) / 2;

      // Thresholds: < 0.25 is closed, > 0.70 is open
      if (avgOpen < 0.25 && !_eyeWasClosed) {
        _eyeWasClosed = true;
      } else if (avgOpen > 0.70 && _eyeWasClosed) {
        _eyeWasClosed = false;
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _blinkCount++;
                if (_blinkCount >= 3) {
                  _livenessPassed = true;
                }
              });
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error processing frame: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    final camera = _controller!.description;
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationValue = sensorOrientation;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationValue = (rotationValue + 180) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationValue);
    }
    if (rotation == null) {
      return null;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.yuv_420_888) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

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

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (!_livenessPassed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please blink at least 3 times first.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    try {
      // Stop stream before taking picture
      await _controller!.stopImageStream();

      final xfile = await _controller!.takePicture();
      final bytes = await xfile.readAsBytes();
      setState(() {
        _capturedImage = xfile;
        _capturedImageBytes = bytes;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content        : Text('Capture failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _submitAttendance() async {
    if (_capturedImageBytes == null) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final b64 = base64Encode(_capturedImageBytes!);
      final devId = await _deviceService.getDeviceId();
      final api = ref.read(apiClientProvider);

      final res = await api.post('/api/attendance/mark/', data: {
        'session_id'    : widget.session['id'],
        'lat'           : widget.lat,
        'lng'           : widget.lng,
        'altitude'      : widget.altitude,
        'device_id'     : devId,
        'face_image_b64': b64,
        'blink_count'   : _blinkCount,
        'compass_direction': _compassHeading,
        'device_movement': _maxAcceleration > 15.0 ? 'moving' : 'stable',
      });

      if (mounted) {
        ref.invalidate(studentActiveSessionsProvider);
        ref.invalidate(studentAttendanceSummaryProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content        : Text(res.data['message'] ?? 'Attendance marked successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
        context.go('/student/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content        : Text(e.toString().contains('"error"') ? 'Geofence / Verification Failed' : e.toString()),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark Attendance — Face Scan',
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
            Text(
              'Step 2: Liveness & Verification',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          if (_isInitializing)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_initError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _initError!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (_capturedImage == null)
            SizedBox.expand(child: CameraPreview(_controller!))
          else
            SizedBox.expand(
              child: Image.memory(
                _capturedImageBytes!,
                fit: BoxFit.cover,
              ),
            ),

          if (_capturedImage == null && !_isInitializing && _initError == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 220,
                    height: 280,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withOpacity(0.70),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(120),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _livenessPassed
                          ? 'Liveness verified ✓\nClick capture to continue'
                          : _faceDetected
                              ? 'Blinks: $_blinkCount / 3\nKeep blinking...'
                              : 'Blink exactly 3 times\nPosition face inside the oval',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Liveness Progress Dots
          if (_capturedImage == null && !_isInitializing && _initError == null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  final isActive = index < _blinkCount;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? AppColors.success : Colors.white24,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  );
                }),
              ),
            ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                24, 20, 24,
                MediaQuery.of(context).padding.bottom + 20,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: _capturedImage == null
                  ? _buildCaptureButton()
                  : _buildConfirmButtons(),
            ),
          ),

          if (_isSubmitting)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Marking attendance...\nThis may take a few seconds.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton() {
    return Center(
      child: GestureDetector(
        onTap: _capturePhoto,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _livenessPassed ? Colors.white : Colors.white24,
            border: Border.all(
              color: _livenessPassed ? Colors.white30 : Colors.white10,
              width: 4,
            ),
          ),
          child: Icon(
            Icons.camera_alt_rounded,
            size: 36,
            color: _livenessPassed ? AppColors.primary : Colors.white30,
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              setState(() {
                _capturedImage = null;
                _capturedImageBytes = null;
                _blinkCount = 0;
                _eyeWasClosed = false;
                _livenessPassed = false;
              });
              // Restart stream
              await _controller?.startImageStream(_processCameraFrame);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retake'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _submitAttendance,
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Submit & Mark'),
          ),
        ),
      ],
    );
  }
}
