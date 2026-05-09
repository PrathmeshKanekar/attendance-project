import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_colors.dart';
import 'face_register_provider.dart';

class FaceRegisterCameraScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> student;

  const FaceRegisterCameraScreen({super.key, required this.student});

  @override
  ConsumerState<FaceRegisterCameraScreen> createState() =>
      _FaceRegisterCameraScreenState();
}

class _FaceRegisterCameraScreenState
    extends ConsumerState<FaceRegisterCameraScreen> {

  CameraController? _controller;
  XFile?            _capturedImage;
  Uint8List?        _capturedImageBytes;
  bool              _isInitializing = true;
  String?           _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  @override
  void dispose() {
    _controller?.dispose();
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

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
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

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
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

  Future<void> _registerFace() async {
    if (_capturedImageBytes == null) return;

    final b64    = base64Encode(_capturedImageBytes!);
    final id     = widget.student['student_id']?.toString() ?? '';

    await ref.read(faceRegisterProvider.notifier).registerFace(
      studentId    : id,
      faceImageB64 : b64,
    );

    final state = ref.read(faceRegisterProvider);

    if (!mounted) return;

    if (state is FaceRegisterSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content        : Text(state.message),
          backgroundColor: AppColors.success,
        ),
      );
      ref.invalidate(faceListProvider);
      Navigator.of(context).pop(true);
    } else if (state is FaceRegisterError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content        : Text(state.message),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final registerState = ref.watch(faceRegisterProvider);
    final isRegistering = registerState is FaceRegisterLoading;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar         : AppBar(
        backgroundColor: Colors.black,
        iconTheme      : const IconThemeData(color: Colors.white),
        title          : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Register Face',
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
            Text(
              widget.student['name']?.toString() ?? '',
              style: const TextStyle(
                color   : Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          if (_isInitializing)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          else if (_initError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child  : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white54,
                      size : 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _initError!,
                      style    : const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (_capturedImage == null)
            SizedBox.expand(
              child: CameraPreview(_controller!),
            )
          else
            SizedBox.expand(
              child: Image.memory(
                _capturedImageBytes!,
                fit: BoxFit.cover,
              ),
            ),

          Positioned(
            top  : 0,
            left : 0,
            right: 0,
            child: Container(
              padding  : const EdgeInsets.fromLTRB(16, 10, 16, 10),
              color    : Colors.black.withOpacity(0.55),
              child    : Row(
                children: [
                  CircleAvatar(
                    radius         : 20,
                    backgroundColor: AppColors.primaryLight.withOpacity(0.30),
                    child          : Text(
                      _initials(widget.student['name']?.toString() ?? ''),
                      style: const TextStyle(
                        color : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.student['name']?.toString() ?? '',
                          style: const TextStyle(
                            color     : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize  : 14,
                          ),
                        ),
                        Text(
                          'PRN: ${widget.student['prn']} · '
                          'Roll: ${widget.student['roll_number']}',
                          style: const TextStyle(
                            color  : Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color       : widget.student['face_registered'] == true
                          ? AppColors.success.withOpacity(0.30)
                          : AppColors.warning.withOpacity(0.30),
                      borderRadius: BorderRadius.circular(8),
                      border      : Border.all(
                        color: widget.student['face_registered'] == true
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                    child: Text(
                      widget.student['face_registered'] == true
                          ? '✓ Updating'
                          : '⚠ Not Registered',
                      style: TextStyle(
                        color    : widget.student['face_registered'] == true
                            ? AppColors.success
                            : AppColors.warning,
                        fontSize : 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_capturedImage == null && !_isInitializing && _initError == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width : 220,
                    height: 280,
                    decoration: BoxDecoration(
                      border      : Border.all(
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
                      color       : Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Position student face inside the oval\nEnsure good lighting · Look straight at camera',
                      textAlign: TextAlign.center,
                      style    : TextStyle(
                        color  : Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Positioned(
            bottom: 0,
            left  : 0,
            right : 0,
            child : Container(
              padding: EdgeInsets.fromLTRB(
                24, 20, 24,
                MediaQuery.of(context).padding.bottom + 20,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin : Alignment.bottomCenter,
                  end   : Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: _capturedImage == null
                  ? _buildCaptureButton()
                  : _buildConfirmButtons(isRegistering),
            ),
          ),

          if (isRegistering)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Registering face...\nThis may take a few seconds.',
                      textAlign: TextAlign.center,
                      style    : TextStyle(color: Colors.white, fontSize: 15),
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
          width : 72,
          height: 72,
          decoration: BoxDecoration(
            shape : BoxShape.circle,
            color : Colors.white,
            border: Border.all(color: Colors.white30, width: 4),
          ),
          child: const Icon(
            Icons.camera_alt_rounded,
            size : 36,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmButtons(bool isLoading) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style    : OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side           : const BorderSide(color: Colors.white54),
              minimumSize    : const Size(0, 52),
              shape          : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: isLoading
                ? null
                : () => setState(() {
                      _capturedImage = null;
                      _capturedImageBytes = null;
                      ref.read(faceRegisterProvider.notifier).reset();
                    }),
            icon : const Icon(Icons.refresh_rounded),
            label: const Text('Retake'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex  : 2,
          child : ElevatedButton.icon(
            style    : ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize    : const Size(0, 52),
              shape          : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: isLoading ? null : _registerFace,
            icon : const Icon(Icons.check_circle_rounded),
            label: const Text('Register Face'),
          ),
        ),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
