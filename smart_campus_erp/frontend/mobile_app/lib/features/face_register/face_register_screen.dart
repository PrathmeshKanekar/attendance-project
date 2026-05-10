import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import '../../core/network/api_client.dart';

class StudentModel {
  final String id;
  final String fullName;
  final String prn;
  final String division;
  final bool faceRegistered;

  const StudentModel({
    required this.id,
    required this.fullName,
    required this.prn,
    required this.division,
    required this.faceRegistered,
  });
}

class FaceRegisterScreen extends ConsumerStatefulWidget {
  final StudentModel student;
  const FaceRegisterScreen({super.key, required this.student});

  @override
  ConsumerState<FaceRegisterScreen> createState() => _FaceRegisterScreenState();
}

class _FaceRegisterScreenState extends ConsumerState<FaceRegisterScreen> {
  CameraController? _cameraController;
  XFile? _capturedImage;
  bool _isRegistering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeCamera());
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(backCamera, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  Future<void> _registerFace() async {
    if (_capturedImage == null) return;
    setState(() => _isRegistering = true);
    final bytes = await File(_capturedImage!.path).readAsBytes();
    final b64 = base64Encode(bytes);
    final api = ref.read(apiClientProvider);

    try {
      await api.post('/api/face/register/', data: {
        'student_id': widget.student.id,
        'face_image_b64': b64,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Face registered successfully!')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $_error')));
      }
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Register Face — ${widget.student.fullName}'),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Section 1: Info Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.blueAccent,
                          child: Text(
                            widget.student.fullName.isNotEmpty ? widget.student.fullName[0].toUpperCase() : 'S',
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.student.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              Text('PRN: ${widget.student.prn}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              Text('Division: ${widget.student.division}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.student.faceRegistered ? Colors.green[50] : Colors.orange[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.student.faceRegistered ? 'Face Registered ✓' : 'Not Registered',
                            style: TextStyle(
                              color: widget.student.faceRegistered ? Colors.green : Colors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Section 2: Camera or preview
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: Colors.black12,
                      width: double.infinity,
                      child: _capturedImage == null
                          ? (_cameraController != null && _cameraController!.value.isInitialized
                              ? CameraPreview(_cameraController!)
                              : const Center(child: CircularProgressIndicator()))
                          : Image.file(File(_capturedImage!.path), fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Actions Button
                if (widget.student.faceRegistered)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'Face profile is already registered and locked.',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else if (_capturedImage == null)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                      onPressed: () async {
                        if (_cameraController != null && _cameraController!.value.isInitialized) {
                          try {
                            final file = await _cameraController!.takePicture();
                            setState(() => _capturedImage = file);
                          } catch (_) {}
                        }
                      },
                      child: const Text('Capture Photo'),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _capturedImage = null),
                          child: const Text('Retake'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          onPressed: _registerFace,
                          child: const Text('Use This & Register'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (_isRegistering)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Registering face...', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
