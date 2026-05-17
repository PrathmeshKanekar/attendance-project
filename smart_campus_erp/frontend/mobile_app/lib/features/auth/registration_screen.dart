import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import '../../core/constants/app_colors.dart';
import '../../core/config/api_config.dart';
import '../../core/network/dio_client.dart';
import '../../core/widgets/stat_card.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _fNameCtrl = TextEditingController();
  final _lNameCtrl = TextEditingController();
  final _prnCtrl = TextEditingController();
  final _rollCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();

  String? _selectedCollegeId;
  String? _selectedDivisionId;
  List<Map<String, dynamic>> _colleges = [];
  List<Map<String, dynamic>> _divisions = [];
  bool _isLoadingData = true;
  bool _isSubmitting = false;

  XFile? _faceImage;
  CameraController? _cameraController;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final api = ref.read(dioClientProvider);
      final collRes = await api.get(ApiConfig.colleges);

      setState(() {
        if (collRes.data is Map && collRes.data['colleges'] != null) {
          _colleges = List<Map<String, dynamic>>.from(collRes.data['colleges']);
        }
        _isLoadingData = false;
      });
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('SocketException') || msg.contains('connection error')) {
          msg = 'Backend unreachable. Please check your server IP in settings.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $msg'), backgroundColor: AppColors.danger),
        );
      }
      setState(() => _isLoadingData = false);
    }
  }

  Future<void> _loadDivisions(String collegeId) async {
    setState(() {
      _divisions = [];
      _selectedDivisionId = null;
    });
    
    try {
      final api = ref.read(dioClientProvider);
      // We pass college_id to filter divisions publicly
      final divRes = await api.get(ApiConfig.divisions, params: {
        'college_id': collegeId,
      });

      setState(() {
        if (divRes.data is List) {
          _divisions = List<Map<String, dynamic>>.from(divRes.data);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading divisions: $e')),
        );
      }
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(front, ResolutionPreset.medium, enableAudio: false);
    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _takePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    final image = await _cameraController!.takePicture();
    setState(() {
      _faceImage = image;
    });
    await _cameraController!.dispose();
    _cameraController = null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_faceImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture your face photo for verification.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final bytes = await _faceImage!.readAsBytes();
      final base64Image = base64Encode(bytes);

      final api = ref.read(dioClientProvider);
      final res = await api.post(ApiConfig.studentsRegister, data: {
        'email': _emailCtrl.text.trim(),
        'password': _pwdCtrl.text,
        'first_name': _fNameCtrl.text.trim(),
        'last_name': _lNameCtrl.text.trim(),
        'college_id': _selectedCollegeId,
        'division_id': _selectedDivisionId,
        'prn': _prnCtrl.text.trim().toUpperCase(),
        'roll_number': _rollCtrl.text.trim(),
        'year_of_study': int.tryParse(_yearCtrl.text) ?? 1,
        'face_image_b64': base64Image,
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Registration Success'),
            content: Text(res.data['message'] ?? 'Please wait for admin approval.'),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  context.go('/login');
                },
                child: const Text('Back to Login'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _fNameCtrl.dispose();
    _lNameCtrl.dispose();
    _prnCtrl.dispose();
    _rollCtrl.dispose();
    _yearCtrl.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Registration'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create Your Account',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Fill in your details and capture a clear face photo for the smart attendance system.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),

              // Face Capture Section
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        color: AppColors.bgSecondary,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primaryLight, width: 2),
                        image: _faceImage != null
                            ? DecorationImage(
                                image: kIsWeb 
                                  ? NetworkImage(_faceImage!.path) as ImageProvider
                                  : FileImage(io.File(_faceImage!.path)), 
                                fit: BoxFit.cover
                              )
                            : null,
                      ),
                      child: _faceImage == null
                          ? (_cameraController != null && _cameraController!.value.isInitialized
                              ? ClipOval(child: CameraPreview(_cameraController!))
                              : const Icon(Icons.face, size: 80, color: AppColors.textSecondary))
                          : null,
                    ),
                    const SizedBox(height: 16),
                    if (_faceImage == null && _cameraController == null)
                      ElevatedButton.icon(
                        onPressed: _initCamera,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Capture Face photo'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryLight),
                      )
                    else if (_cameraController != null)
                      ElevatedButton.icon(
                        onPressed: _takePhoto,
                        icon: const Icon(Icons.camera),
                        label: const Text('Snap Photo'),
                      )
                    else
                      TextButton.icon(
                        onPressed: () => setState(() => _faceImage = null),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retake Photo'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              TextFormField(
                controller: _fNameCtrl,
                decoration: const InputDecoration(labelText: 'First Name', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lNameCtrl,
                decoration: const InputDecoration(labelText: 'Last Name', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.email_outlined)),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v!.contains('@') ? null : 'Invalid email',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pwdCtrl,
                decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                obscureText: true,
                validator: (v) => v!.length >= 6 ? null : 'Min 6 characters',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCollegeId,
                decoration: const InputDecoration(labelText: 'Select College', prefixIcon: Icon(Icons.school_outlined)),
                items: _colleges.map((c) => DropdownMenuItem(value: c['id'] as String, child: Text(c['name']))).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedCollegeId = v);
                    _loadDivisions(v);
                  }
                },
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDivisionId,
                decoration: const InputDecoration(labelText: 'Select Division', prefixIcon: Icon(Icons.groups_outlined)),
                items: _divisions.map((d) => DropdownMenuItem(
                  value: d['id'] as String, 
                  child: Text('${d['name']} (Year ${d['year_of_study']})')
                )).toList(),
                onChanged: (v) => setState(() => _selectedDivisionId = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _prnCtrl,
                      decoration: const InputDecoration(labelText: 'PRN', hintText: 'DEC2024001'),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _rollCtrl,
                      decoration: const InputDecoration(labelText: 'Roll No'),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _yearCtrl,
                decoration: const InputDecoration(labelText: 'Year of Study (1-4)'),
                keyboardType: TextInputType.number,
                validator: (v) => (int.tryParse(v ?? '') != null) ? null : 'Required (Number)',
              ),
              const SizedBox(height: 32),

              _isSubmitting
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.primary,
                      ),
                      child: const Text('REGISTER NOW', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Already have an account? Login'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
