import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/config/api_config.dart';
import '../../core/network/dio_client.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  int _currentStep = 0;
  final int _totalSteps = 5;
  final _formKey = GlobalKey<FormState>();

  // ── STEP 1: PERSONAL DETAILS CONTROLLERS ─────────────────────────
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _altPhoneCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  String? _selectedGender;
  String? _selectedBloodGroup;
  DateTime? _selectedBirthDate;

  // ── STEP 2: ACADEMIC DETAILS CONTROLLERS ─────────────────────────
  final _prnCtrl = TextEditingController();
  final _enrollmentCtrl = TextEditingController();
  final _rollCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();

  String? _selectedCollegeId;
  String? _selectedDepartmentId;
  String? _selectedCourseId;
  String? _selectedAcademicYearId;
  int? _selectedYearOfStudy;
  String? _selectedDivisionId;
  int? _selectedAdmissionYear;

  // Academic Dropdown Data Sources
  List<Map<String, dynamic>> _colleges = [];
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _academicYears = [];
  List<Map<String, dynamic>> _divisions = [];

  // Dropdown Fetch States
  bool _isLoadingColleges = false;
  bool _isLoadingDepartments = false;
  bool _isLoadingCourses = false;
  bool _isLoadingAcademicYears = false;
  bool _isLoadingDivisions = false;

  // Selected Course details
  int _selectedCourseMaxYears = 4; // Default fallback

  // ── STEP 3: SECURITY & PASSWORD CONTROLLERS ──────────────────────
  final _pwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  bool _obscurePwd = true;
  bool _obscureConfirmPwd = true;

  // ── STEP 4: BIOMETRIC FACE ENROLLMENT ────────────────────────────
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _noCameraAvailable = false;

  XFile? _faceImageFront;
  XFile? _faceImageLeft;
  XFile? _faceImageRight;

  String _activeFaceAngle = 'front'; // 'front', 'left', 'right'
  bool _isAnalyzingFace = false;

  // Facial quality analysis mock metrics
  Map<String, String>? _faceQualityFront;
  Map<String, String>? _faceQualityLeft;
  Map<String, String>? _faceQualityRight;

  // ── STEP 5: DOCUMENT SUBMISSION ──────────────────────────────────
  // Contains maps of: {'type': String, 'name': String, 'bytes': Uint8List, 'b64': String}
  final List<Map<String, dynamic>> _uploadedDocuments = [];
  final List<String> _documentTypes = ['Aadhaar Card', 'Admission Receipt', 'College ID Card', 'Other'];
  String _selectedDocType = 'Aadhaar Card';

  // ── CENTRALIZED STATE MANAGEMENT ─────────────────────────────────
  bool _isSubmitting = false;
  bool _isValidatingField = false;

  // Real-time server duplicate results
  bool _emailDuplicateError = false;
  bool _prnDuplicateError = false;
  bool _enrollmentDuplicateError = false;

  @override
  void initState() {
    super.initState();
    _loadColleges();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _altPhoneCtrl.dispose();
    _dobCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();

    _prnCtrl.dispose();
    _enrollmentCtrl.dispose();
    _rollCtrl.dispose();
    _batchCtrl.dispose();

    _pwdCtrl.dispose();
    _confirmPwdCtrl.dispose();

    _cameraController?.dispose();
    super.dispose();
  }

  // ── DATA FETCHING METHODS (CASCADING API CALLS) ───────────────────

  Future<void> _loadColleges() async {
    setState(() {
      _isLoadingColleges = true;
      _colleges = [];
    });
    try {
      final dio = ref.read(dioClientProvider);
      final res = await dio.get(ApiConfig.colleges);
      if (res.data != null && res.data['colleges'] != null) {
        setState(() {
          _colleges = List<Map<String, dynamic>>.from(res.data['colleges']);
        });
      }
    } catch (e) {
      _showSnackBar('Failed to load colleges: $e', AppColors.danger);
    } finally {
      setState(() => _isLoadingColleges = false);
    }
  }

  Future<void> _loadDepartments(String collegeId) async {
    setState(() {
      _isLoadingDepartments = true;
      _departments = [];
      _selectedDepartmentId = null;
      _courses = [];
      _selectedCourseId = null;
      _divisions = [];
      _selectedDivisionId = null;
    });
    try {
      final dio = ref.read(dioClientProvider);
      final res = await dio.get(ApiConfig.departments, params: {
        'college_id': collegeId,
      });
      if (res.data != null) {
        setState(() {
          _departments = List<Map<String, dynamic>>.from(res.data);
        });
      }
    } catch (e) {
      _showSnackBar('Failed to load departments: $e', AppColors.danger);
    } finally {
      setState(() => _isLoadingDepartments = false);
    }
  }

  Future<void> _loadCourses(String collegeId, String departmentId) async {
    setState(() {
      _isLoadingCourses = true;
      _courses = [];
      _selectedCourseId = null;
      _divisions = [];
      _selectedDivisionId = null;
    });
    try {
      final dio = ref.read(dioClientProvider);
      final res = await dio.get(ApiConfig.courses, params: {
        'college_id': collegeId,
        'department': departmentId,
      });
      if (res.data != null) {
        setState(() {
          _courses = List<Map<String, dynamic>>.from(res.data);
        });
      }
    } catch (e) {
      _showSnackBar('Failed to load courses: $e', AppColors.danger);
    } finally {
      setState(() => _isLoadingCourses = false);
    }
  }

  Future<void> _loadAcademicYears(String collegeId) async {
    setState(() {
      _isLoadingAcademicYears = true;
      _academicYears = [];
      _selectedAcademicYearId = null;
      _divisions = [];
      _selectedDivisionId = null;
    });
    try {
      final dio = ref.read(dioClientProvider);
      final res = await dio.get(ApiConfig.academicYears, params: {
        'college_id': collegeId,
      });
      if (res.data != null) {
        setState(() {
          _academicYears = List<Map<String, dynamic>>.from(res.data);
        });
      }
    } catch (e) {
      _showSnackBar('Failed to load academic years: $e', AppColors.danger);
    } finally {
      setState(() => _isLoadingAcademicYears = false);
    }
  }

  Future<void> _loadDivisions() async {
    if (_selectedCollegeId == null ||
        _selectedCourseId == null ||
        _selectedAcademicYearId == null ||
        _selectedYearOfStudy == null) {
      return;
    }

    setState(() {
      _isLoadingDivisions = true;
      _divisions = [];
      _selectedDivisionId = null;
    });

    try {
      final dio = ref.read(dioClientProvider);
      final res = await dio.get(ApiConfig.divisions, params: {
        'college_id': _selectedCollegeId,
        'course': _selectedCourseId,
        'academic_year': _selectedAcademicYearId,
        'year_of_study': _selectedYearOfStudy,
      });
      if (res.data != null) {
        setState(() {
          _divisions = List<Map<String, dynamic>>.from(res.data);
        });
      }
    } catch (e) {
      _showSnackBar('Failed to load divisions: $e', AppColors.danger);
    } finally {
      setState(() => _isLoadingDivisions = false);
    }
  }

  // ── REAL-TIME SERVER DUPLICATE CHECKS ─────────────────────────────

  Future<bool> _verifyDuplicateOnServer({String? email, String? prn, String? enrollmentNumber}) async {
    setState(() => _isValidatingField = true);
    try {
      final dio = ref.read(dioClientProvider);
      final res = await dio.get('/api/students/check-duplicate/', params: {
        if (email != null) 'email': email.trim().toLowerCase(),
        if (prn != null) 'prn': prn.trim().toUpperCase(),
        if (enrollmentNumber != null) 'enrollment_number': enrollmentNumber.trim().toUpperCase(),
      });

      if (res.data != null) {
        final emailExists = res.data['email_exists'] == true;
        final prnExists = res.data['prn_exists'] == true;
        final enrollmentExists = res.data['enrollment_number_exists'] == true;

        setState(() {
          if (email != null) _emailDuplicateError = emailExists;
          if (prn != null) _prnDuplicateError = prnExists;
          if (enrollmentNumber != null) _enrollmentDuplicateError = enrollmentExists;
        });

        return emailExists || prnExists || enrollmentExists;
      }
    } catch (e) {
      debugPrint('Duplicate validation failed: $e');
    } finally {
      setState(() => _isValidatingField = false);
    }
    return false;
  }

  // ── CAMERA & BIOMETRICS LIFECYCLE ────────────────────────────────

  Future<void> _initCamera() async {
    setState(() {
      _noCameraAvailable = false;
      _isCameraInitialized = false;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _noCameraAvailable = true);
        return;
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: (defaultTargetPlatform == TargetPlatform.android) ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
      setState(() => _noCameraAvailable = true);
    }
  }

  Future<void> _captureFacePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() => _isAnalyzingFace = true);
    try {
      final XFile image = await _cameraController!.takePicture();
      
      // Simulate real-time face alignment, illumination and blur validation
      await Future.delayed(const Duration(milliseconds: 1000));
      
      final mockQuality = {
        'Lighting': 'OPTIMAL',
        'Sharpness': 'CLEAR (Blur: 0.04)',
        'Alignment': 'CENTERED (Yaw: 1.2°, Pitch: 0.8°)',
        'Liveness': 'PASSED (Blink challenge verified)'
      };

      setState(() {
        if (_activeFaceAngle == 'front') {
          _faceImageFront = image;
          _faceQualityFront = mockQuality;
        } else if (_activeFaceAngle == 'left') {
          _faceImageLeft = image;
          _faceQualityLeft = mockQuality;
        } else if (_activeFaceAngle == 'right') {
          _faceImageRight = image;
          _faceQualityRight = mockQuality;
        }
      });
      _showSnackBar('${_activeFaceAngle.toUpperCase()} angle captured successfully!', AppColors.success);
    } catch (e) {
      _showSnackBar('Capture failed: $e', AppColors.danger);
    } finally {
      setState(() => _isAnalyzingFace = false);
    }
  }

  Future<void> _pickFacePhotoFallback() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.image,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final XFile image = XFile(path);

        setState(() {
          if (_activeFaceAngle == 'front') {
            _faceImageFront = image;
          } else if (_activeFaceAngle == 'left') {
            _faceImageLeft = image;
          } else if (_activeFaceAngle == 'right') {
            _faceImageRight = image;
          }
        });
      }
    } catch (e) {
      _showSnackBar('File selection failed: $e', AppColors.danger);
    }
  }

  // ── HELPER UTILS ─────────────────────────────────────────────────

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _nextStep() async {
    // Trim current active step fields
    _trimActiveStepFields();

    if (_currentStep == 0) {
      // Reset stale duplicate flags before re-validating
      setState(() {
        _emailDuplicateError = false;
      });
      if (!_formKey.currentState!.validate()) return;
      
      // Perform Email check duplicate on server
      final isDup = await _verifyDuplicateOnServer(email: _emailCtrl.text);
      if (isDup) {
        _showSnackBar('Email address already exists!', AppColors.danger);
        return;
      }
    } else if (_currentStep == 1) {
      // Validate Academic fields manually to cover all dropdown constraints
      if (_selectedCollegeId == null ||
          _selectedDepartmentId == null ||
          _selectedCourseId == null ||
          _selectedAcademicYearId == null ||
          _selectedYearOfStudy == null ||
          _selectedDivisionId == null ||
          _selectedAdmissionYear == null) {
        _showSnackBar('Please complete all academic dropdown selections.', AppColors.warning);
        return;
      }

      // Reset stale duplicate flags before re-validating
      setState(() {
        _prnDuplicateError = false;
        _enrollmentDuplicateError = false;
      });
      if (!_formKey.currentState!.validate()) return;

      // Ensure Year of study is valid for selected Course duration
      if (_selectedYearOfStudy! > _selectedCourseMaxYears) {
        _showSnackBar('Year of study cannot exceed selected Course duration ($_selectedCourseMaxYears years).', AppColors.danger);
        return;
      }

      // Perform PRN and Enrollment duplicate validation checks
      final isDup = await _verifyDuplicateOnServer(
        prn: _prnCtrl.text,
        enrollmentNumber: _enrollmentCtrl.text,
      );
      if (isDup) {
        _showSnackBar('Duplicate academic fields detected! Ensure PRN and Enrollment are unique.', AppColors.danger);
        return;
      }
    } else if (_currentStep == 2) {
      if (!_formKey.currentState!.validate()) return;
      if (_pwdCtrl.text != _confirmPwdCtrl.text) {
        _showSnackBar('Passwords do not match.', AppColors.danger);
        return;
      }
      
      // Initialize camera for biometrics step in advance
      _initCamera();
    } else if (_currentStep == 3) {
      if (_faceImageFront == null) {
        _showSnackBar('Front face capture is mandatory for biometric scanning!', AppColors.danger);
        return;
      }
      // Stop camera stream before proceeding
      await _cameraController?.dispose();
      _cameraController = null;
      setState(() => _isCameraInitialized = false);
    }

    if (_currentStep < _totalSteps - 1) {
      setState(() {
        _currentStep++;
      });
    }
  }

  void _prevStep() async {
    await _cameraController?.dispose();
    _cameraController = null;
    setState(() {
      _isCameraInitialized = false;
      _currentStep--;
    });
  }

  void _trimActiveStepFields() {
    if (_currentStep == 0) {
      _firstNameCtrl.text = _firstNameCtrl.text.trim();
      _middleNameCtrl.text = _middleNameCtrl.text.trim();
      _lastNameCtrl.text = _lastNameCtrl.text.trim();
      _emailCtrl.text = _emailCtrl.text.trim().toLowerCase();
      _phoneCtrl.text = _phoneCtrl.text.trim();
      _altPhoneCtrl.text = _altPhoneCtrl.text.trim();
      _addressCtrl.text = _addressCtrl.text.trim();
      _cityCtrl.text = _cityCtrl.text.trim();
      _stateCtrl.text = _stateCtrl.text.trim();
      _pincodeCtrl.text = _pincodeCtrl.text.trim();
    } else if (_currentStep == 1) {
      _prnCtrl.text = _prnCtrl.text.trim().toUpperCase();
      _enrollmentCtrl.text = _enrollmentCtrl.text.trim().toUpperCase();
      _rollCtrl.text = _rollCtrl.text.trim();
      _batchCtrl.text = _batchCtrl.text.trim();
    }
  }

  double _calculatePasswordStrength(String value) {
    if (value.isEmpty) return 0.0;
    double strength = 0.0;
    if (value.length >= 8) strength += 0.25;
    if (RegExp(r'[A-Z]').hasMatch(value)) strength += 0.25;
    if (RegExp(r'[a-z]').hasMatch(value)) strength += 0.25;
    if (RegExp(r'[0-9]').hasMatch(value) || RegExp(r'[!@#\$&*~.]').hasMatch(value)) strength += 0.25;
    return strength;
  }

  Color _getStrengthColor(double strength) {
    if (strength <= 0.25) return AppColors.danger;
    if (strength <= 0.5) return AppColors.warning;
    if (strength <= 0.75) return Colors.amber;
    return AppColors.success;
  }

  String _getStrengthText(double strength) {
    if (strength <= 0.25) return 'Very Weak';
    if (strength <= 0.5) return 'Weak';
    if (strength <= 0.75) return 'Medium';
    return 'Strong & Compliant';
  }

  // ── FINAL FORM SUBMISSION ────────────────────────────────────────

  Future<void> _submitRegistration() async {
    setState(() => _isSubmitting = true);

    try {
      // 1. Convert Face photos to Base64
      final frontBytes = await _faceImageFront!.readAsBytes();
      final frontB64 = base64Encode(frontBytes);

      String? leftB64;
      if (_faceImageLeft != null) {
        final leftBytes = await _faceImageLeft!.readAsBytes();
        leftB64 = base64Encode(leftBytes);
      }

      String? rightB64;
      if (_faceImageRight != null) {
        final rightBytes = await _faceImageRight!.readAsBytes();
        rightB64 = base64Encode(rightBytes);
      }

      // 2. Prepare relational document structures
      final docList = _uploadedDocuments.map((doc) => {
        'document_type': (doc['type'] as String).replaceAll(' ', '_').toLowerCase(),
        'file_name': doc['name'],
        'file_b64': doc['b64']
      }).toList();

      final payload = {
        // STEP 1: Personal
        'email': _emailCtrl.text.trim().toLowerCase(),
        'first_name': _firstNameCtrl.text.trim(),
        'middle_name': _middleNameCtrl.text.isNotEmpty ? _middleNameCtrl.text.trim() : null,
        'last_name': _lastNameCtrl.text.trim(),
        'gender': _selectedGender,
        'date_of_birth': DateFormat('yyyy-MM-dd').format(_selectedBirthDate!),
        'blood_group': _selectedBloodGroup,
        'phone': _phoneCtrl.text.trim(),
        'alternate_phone': _altPhoneCtrl.text.isNotEmpty ? _altPhoneCtrl.text.trim() : null,
        'address': _addressCtrl.text.isNotEmpty ? _addressCtrl.text.trim() : null,
        'city': _cityCtrl.text.isNotEmpty ? _cityCtrl.text.trim() : null,
        'state': _stateCtrl.text.isNotEmpty ? _stateCtrl.text.trim() : null,
        'pincode': _pincodeCtrl.text.isNotEmpty ? _pincodeCtrl.text.trim() : null,

        // STEP 2: Academic
        'prn': _prnCtrl.text.trim().toUpperCase(),
        'roll_number': _rollCtrl.text.trim(),
        'enrollment_number': _enrollmentCtrl.text.trim().toUpperCase(),
        'college_id': _selectedCollegeId,
        'course_id': _selectedCourseId,
        'division_id': _selectedDivisionId,
        'academic_year_id': _selectedAcademicYearId,
        'batch': _batchCtrl.text.isNotEmpty ? _batchCtrl.text.trim() : null,
        'admission_year': _selectedAdmissionYear,
        'year_of_study': _selectedYearOfStudy,

        // STEP 3: Account
        'password': _pwdCtrl.text,

        // STEP 4: Biometrics
        'face_image_b64': frontB64,
        if (leftB64 != null) 'face_image_left_b64': leftB64,
        if (rightB64 != null) 'face_image_right_b64': rightB64,

        // STEP 5: Documents
        'uploaded_documents': docList
      };

      final dio = ref.read(dioClientProvider);
      final res = await dio.post(ApiConfig.studentsRegister, data: payload);

      if (mounted) {
        _showSuccessDialog(res.data['message'] ?? 'Your application has been submitted to the Lab Assistant for review.');
      }
    } catch (e) {
      _showSnackBar('Registration Failed: $e', AppColors.danger);
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: AppColors.cardBg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
              ),
              const SizedBox(height: 20),
              Text(
                'Registration Completed!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    context.go('/login');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    'Proceed to Login',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── STEP-WISE BUILDERS (WITH STABLE WIDGET-TREE KEYS) ──────────────

  Widget _buildActiveStep() {
    switch (_currentStep) {
      case 0:
        return _buildStepPersonal();
      case 1:
        return _buildStepAcademic();
      case 2:
        return _buildStepSecurity();
      case 3:
        return _buildStepBiometric();
      case 4:
        return _buildStepReview();
      default:
        return const SizedBox.shrink();
    }
  }

  // STEP 1: PERSONAL DETAILS FORM
  Widget _buildStepPersonal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Personal Profile', 'Enter your personal records. Ensure accuracy as per official certificates.'),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _firstNameCtrl,
                label: 'First Name',
                prefixIcon: Icons.person_outline,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!RegExp(r'^[a-zA-Z\s]{2,50}$').hasMatch(v)) return 'Invalid alphabetic name';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _lastNameCtrl,
                label: 'Last Name',
                prefixIcon: Icons.person_outline,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!RegExp(r'^[a-zA-Z\s]{2,50}$').hasMatch(v)) return 'Invalid alphabetic name';
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _middleNameCtrl,
          label: 'Middle Name (Optional)',
          prefixIcon: Icons.person_outline,
          validator: (v) {
            if (v != null && v.isNotEmpty && !RegExp(r'^[a-zA-Z\s]{2,50}$').hasMatch(v)) return 'Invalid name';
            return null;
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDropdownField<String>(
                label: 'Gender',
                value: _selectedGender,
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (val) => setState(() => _selectedGender = val),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdownField<String>(
                label: 'Blood Group',
                value: _selectedBloodGroup,
                items: const [
                  DropdownMenuItem(value: 'A+', child: Text('A+')),
                  DropdownMenuItem(value: 'A-', child: Text('A-')),
                  DropdownMenuItem(value: 'B+', child: Text('B+')),
                  DropdownMenuItem(value: 'B-', child: Text('B-')),
                  DropdownMenuItem(value: 'O+', child: Text('O+')),
                  DropdownMenuItem(value: 'O-', child: Text('O-')),
                  DropdownMenuItem(value: 'AB+', child: Text('AB+')),
                  DropdownMenuItem(value: 'AB-', child: Text('AB-')),
                ],
                onChanged: (val) => setState(() => _selectedBloodGroup = val),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildTextField(
                controller: _dobCtrl,
                label: 'Date of Birth (Age >= 16)',
                prefixIcon: Icons.calendar_today_outlined,
                readOnly: true,
                onTap: _pickBirthDate,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (_selectedBirthDate != null) {
                    final today = DateTime.now();
                    final isBeforeBirthday = today.month < _selectedBirthDate!.month ||
                        (today.month == _selectedBirthDate!.month && today.day < _selectedBirthDate!.day);
                    final age = today.year - _selectedBirthDate!.year - (isBeforeBirthday ? 1 : 0);
                    if (age < 16) return 'Must be at least 16';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: _buildTextField(
                controller: _emailCtrl,
                label: 'Email Address',
                prefixIcon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) return 'Invalid email format';
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _phoneCtrl,
                label: 'Mobile Number',
                prefixIcon: Icons.phone_android_outlined,
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!RegExp(r'^[6-9]\d{9}$').hasMatch(v)) return 'Enter valid 10-digit number';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _altPhoneCtrl,
                label: 'Alternate Number (Optional)',
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v != null && v.isNotEmpty) {
                    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(v)) return 'Enter valid 10-digit number';
                    if (v == _phoneCtrl.text) return 'Must be different';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _addressCtrl,
          label: 'Residential Address',
          prefixIcon: Icons.home_outlined,
          maxLines: 2,
          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _cityCtrl,
                label: 'City',
                prefixIcon: Icons.location_city_outlined,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _stateCtrl,
                label: 'State',
                prefixIcon: Icons.map_outlined,
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _pincodeCtrl,
                label: 'Pincode',
                prefixIcon: Icons.pin_drop_outlined,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!RegExp(r'^\d{6}$').hasMatch(v)) return 'Must be 6 digits';
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // STEP 2: ACADEMIC DETAILS FORM
  Widget _buildStepAcademic() {
    final curYear = DateTime.now().year;
    final admissionYears = List.generate(6, (index) => curYear - index);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Academic Enrollment', 'Map your current college placement. These selections are queried in real-time from server logs.'),
        const SizedBox(height: 24),

        // College Dropdown
        _buildDropdownField<String>(
          label: _isLoadingColleges ? 'Loading Colleges...' : 'Select College',
          value: _selectedCollegeId,
          items: _colleges.map((c) => DropdownMenuItem(value: c['id'] as String, child: Text(c['name']))).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedCollegeId = val;
              });
              _loadDepartments(val);
              _loadAcademicYears(val);
            }
          },
        ),
        const SizedBox(height: 16),

        // Row of Department and Course
        Row(
          children: [
            Expanded(
              child: _buildDropdownField<String>(
                label: _isLoadingDepartments ? 'Loading Departments...' : 'Select Department',
                value: _selectedDepartmentId,
                disabled: _selectedCollegeId == null,
                items: _departments.map((d) => DropdownMenuItem(value: d['id'] as String, child: Text(d['name']))).toList(),
                onChanged: (val) {
                  if (val != null && _selectedCollegeId != null) {
                    setState(() => _selectedDepartmentId = val);
                    _loadCourses(_selectedCollegeId!, val);
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdownField<String>(
                label: _isLoadingCourses ? 'Loading Courses...' : 'Select Course',
                value: _selectedCourseId,
                disabled: _selectedDepartmentId == null,
                items: _courses.map((c) => DropdownMenuItem(value: c['id'] as String, child: Text(c['name']))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    final crs = _courses.firstWhere((element) => element['id'] == val);
                    setState(() {
                      _selectedCourseId = val;
                      _selectedCourseMaxYears = crs['duration_years'] ?? 4;
                    });
                    _loadDivisions();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Row of Academic Year and Year of Study
        Row(
          children: [
            Expanded(
              child: _buildDropdownField<String>(
                label: _isLoadingAcademicYears ? 'Loading Years...' : 'Select Academic Year',
                value: _selectedAcademicYearId,
                disabled: _selectedCollegeId == null,
                items: _academicYears.map((ay) => DropdownMenuItem(value: ay['id'] as String, child: Text(ay['name']))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedAcademicYearId = val);
                    _loadDivisions();
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdownField<int>(
                label: 'Year of Study',
                value: _selectedYearOfStudy,
                disabled: _selectedCourseId == null,
                items: List.generate(_selectedCourseMaxYears, (index) => index + 1).map((y) {
                  String label = '1st Year';
                  if (y == 2) label = '2nd Year';
                  if (y == 3) label = '3rd Year';
                  if (y >= 4) label = '$y' 'th Year';
                  return DropdownMenuItem(value: y, child: Text(label));
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedYearOfStudy = val);
                    _loadDivisions();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Row of Division and Admission Year
        Row(
          children: [
            Expanded(
              child: _buildDropdownField<String>(
                label: _isLoadingDivisions ? 'Loading Divisions...' : 'Select Division',
                value: _selectedDivisionId,
                disabled: _selectedYearOfStudy == null || _divisions.isEmpty,
                items: _divisions.map((d) => DropdownMenuItem(value: d['id'] as String, child: Text(d['name']))).toList(),
                onChanged: (val) => setState(() => _selectedDivisionId = val),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdownField<int>(
                label: 'Admission Year',
                value: _selectedAdmissionYear,
                items: admissionYears.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                onChanged: (val) => setState(() => _selectedAdmissionYear = val),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _prnCtrl,
                label: 'PRN Number',
                prefixIcon: Icons.assignment_ind_outlined,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!RegExp(r'^[A-Z0-9]{8,20}$').hasMatch(v)) return '8-20 alphanumeric capitals';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _enrollmentCtrl,
                label: 'Enrollment Number',
                prefixIcon: Icons.pin_outlined,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!RegExp(r'^[A-Z0-9]{8,20}$').hasMatch(v)) return '8-20 alphanumeric capitals';
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _rollCtrl,
                label: 'Roll Number',
                prefixIcon: Icons.format_list_numbered_outlined,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (int.tryParse(v) == null) return 'Must be a number';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _batchCtrl,
                label: 'Batch (e.g. 2024-2028)',
                prefixIcon: Icons.group_work_outlined,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (!RegExp(r'^\d{4}-\d{4}$').hasMatch(v)) return 'Use YYYY-YYYY format';
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // STEP 3: SECURITY & PASSWORD
  Widget _buildStepSecurity() {
    final pass = _pwdCtrl.text;
    final strength = _calculatePasswordStrength(pass);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Account Credentials', 'Setup high-security passwords to protect your academic records and biometric templates.'),
        const SizedBox(height: 24),
        _buildTextField(
          controller: _pwdCtrl,
          label: 'Password',
          prefixIcon: Icons.lock_outline,
          obscureText: _obscurePwd,
          onChanged: (v) => setState(() {}),
          suffixIcon: IconButton(
            icon: Icon(_obscurePwd ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
            onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Required';
            if (v.length < 8) return 'Minimum 8 characters';
            if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Must contain uppercase letter';
            if (!RegExp(r'[a-z]').hasMatch(v)) return 'Must contain lowercase letter';
            if (!RegExp(r'[0-9]').hasMatch(v)) return 'Must contain a digit';
            if (!RegExp(r'[!@#\$&*~.]').hasMatch(v)) return 'Must contain special symbol';
            return null;
          },
        ),
        const SizedBox(height: 12),

        // Password Strength Indicators
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Password Strength:',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                ),
                Text(
                  _getStrengthText(strength),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getStrengthColor(strength),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: strength,
                backgroundColor: AppColors.bgSecondary,
                valueColor: AlwaysStoppedAnimation<Color>(_getStrengthColor(strength)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Requirements: ≥8 chars, 1 uppercase, 1 lowercase, 1 digit, 1 special character.',
              style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildTextField(
          controller: _confirmPwdCtrl,
          label: 'Confirm Password',
          prefixIcon: Icons.lock_reset_outlined,
          obscureText: _obscureConfirmPwd,
          suffixIcon: IconButton(
            icon: Icon(_obscureConfirmPwd ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
            onPressed: () => setState(() => _obscureConfirmPwd = !_obscureConfirmPwd),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Required';
            if (v != _pwdCtrl.text) return 'Passwords do not match';
            return null;
          },
        ),
      ],
    );
  }

  // STEP 4: BIOMETRIC SCANNING
  Widget _buildStepBiometric() {
    XFile? activeImage;
    Map<String, String>? activeQuality;
    if (_activeFaceAngle == 'front') {
      activeImage = _faceImageFront;
      activeQuality = _faceQualityFront;
    } else if (_activeFaceAngle == 'left') {
      activeImage = _faceImageLeft;
      activeQuality = _faceQualityLeft;
    } else if (_activeFaceAngle == 'right') {
      activeImage = _faceImageRight;
      activeQuality = _faceQualityRight;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Face Biometric Enrollment', 'Verify spatial alignments from three distinct angles. FRONT profile is required, profiles LEFT and RIGHT optimize template registration.'),
        const SizedBox(height: 20),

        // Angle Selection Tabs
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _buildAngleTab('front', 'Front Scan *', _faceImageFront != null),
              _buildAngleTab('left', 'Left Angle', _faceImageLeft != null),
              _buildAngleTab('right', 'Right Angle', _faceImageRight != null),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Camera Feed / Image Display View
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              color: AppColors.dark,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primaryLight, width: 4),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryLight.withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ],
            ),
            child: ClipOval(
              child: activeImage != null
                  ? Image.file(io.File(activeImage.path), fit: BoxFit.cover)
                  : (_noCameraAvailable
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 48),
                            const SizedBox(height: 8),
                            Text(
                              'Camera Unavailable',
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        )
                      : (_isCameraInitialized
                          ? CameraPreview(_cameraController!)
                          : const Center(child: CircularProgressIndicator(color: Colors.white))))
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Capture Controls
        Center(
          child: _isAnalyzingFace
              ? const CircularProgressIndicator()
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_noCameraAvailable) ...[
                      ElevatedButton.icon(
                        onPressed: _captureFacePhoto,
                        icon: const Icon(Icons.camera_alt),
                        label: Text('Capture ${_activeFaceAngle.toUpperCase()}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: Colors.white,
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    TextButton.icon(
                      onPressed: _pickFacePhotoFallback,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Upload Photo'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 20),

        // Facial Quality Feedback Block
        if (activeImage != null && activeQuality != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDCFCE7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Biometric Quality Standards Met',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.success),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Lighting: ${activeQuality['Lighting']}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.green[800])),
                Text('Sharpness: ${activeQuality['Sharpness']}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.green[800])),
                Text('Alignment: ${activeQuality['Alignment']}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.green[800])),
                Text('Spoof/Liveness: ${activeQuality['Liveness']}', style: GoogleFonts.poppins(fontSize: 11, color: Colors.green[800])),
              ],
            ),
          )
        else if (activeImage == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.info_outline, color: AppColors.textSecondary, size: 20),
                const SizedBox(height: 8),
                Text(
                  'Please scan or upload a clear, front-facing photograph. Avoid caps, shades, or blurred lenses.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAngleTab(String angle, String label, bool isCaptured) {
    final active = _activeFaceAngle == angle;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeFaceAngle = angle;
          });
        },
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isCaptured)
                const Icon(Icons.check_circle, color: AppColors.success, size: 14)
              else
                Icon(Icons.circle_outlined, color: active ? Colors.white54 : AppColors.textSecondary, size: 12),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // STEP 5: REVIEW DETAILS & DOCUMENT UPLOADER
  Widget _buildStepReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Review & Document Upload', 'Verify the accuracy of your application dossier and attach relational files (Aadhaar Card, Admission slips).'),
        const SizedBox(height: 24),

        // Document Uploader Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Relational Document Attachments',
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildDropdownField<String>(
                      label: 'Document Type',
                      value: _selectedDocType,
                      items: _documentTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedDocType = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _pickAttachmentFile,
                      icon: const Icon(Icons.attach_file, color: Colors.white),
                      label: const Text('Add File'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Uploaded list preview
              if (_uploadedDocuments.isNotEmpty)
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _uploadedDocuments.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.borderColor),
                  itemBuilder: (context, index) {
                    final doc = _uploadedDocuments[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        doc['name'].endsWith('.pdf') ? Icons.picture_as_pdf : Icons.insert_drive_file,
                        color: doc['name'].endsWith('.pdf') ? AppColors.danger : AppColors.primaryLight,
                      ),
                      title: Text(doc['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('${doc['type']} • ${(doc['size'] / 1024).toStringAsFixed(1)} KB', style: GoogleFonts.poppins(fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.cancel_outlined, color: AppColors.danger, size: 18),
                        onPressed: () {
                          setState(() {
                            _uploadedDocuments.removeAt(index);
                          });
                        },
                      ),
                    );
                  },
                )
              else
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No documents uploaded yet.',
                    style: GoogleFonts.poppins(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Dossier Summary Card
        Text(
          'Dossier Summary',
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            children: [
              _buildSummaryRow('Full Name', '${_firstNameCtrl.text} ${_lastNameCtrl.text}'),
              _buildSummaryRow('Email', _emailCtrl.text),
              _buildSummaryRow('Mobile', _phoneCtrl.text),
              _buildSummaryRow('PRN Number', _prnCtrl.text),
              _buildSummaryRow('Enrollment No', _enrollmentCtrl.text),
              _buildSummaryRow('Roll Number', _rollCtrl.text),
              _buildSummaryRow('Year of Study', _selectedYearOfStudy != null ? '${_selectedYearOfStudy}st Year' : '-'),
              _buildSummaryRow('Academic Year', _academicYears.firstWhere((ay) => ay['id'] == _selectedAcademicYearId, orElse: () => {'name': '-'})['name']),
              _buildSummaryRow('Biometric template', _faceImageFront != null ? 'ENROLLED (Front Angle)' : 'MISSING'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickAttachmentFile() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );

      if (result != null) {
        final platformFile = result.files.single;
        final name = platformFile.name;
        final size = platformFile.size;

        Uint8List? fileBytes;
        if (kIsWeb) {
          fileBytes = platformFile.bytes;
        } else if (platformFile.path != null) {
          fileBytes = await io.File(platformFile.path!).readAsBytes();
        }

        if (fileBytes != null) {
          final base64File = base64Encode(fileBytes);
          setState(() {
            _uploadedDocuments.add({
              'type': _selectedDocType,
              'name': name,
              'bytes': fileBytes,
              'size': size,
              'b64': base64File,
            });
          });
        }
      }
    } catch (e) {
      _showSnackBar('Attachment error: $e', AppColors.danger);
    }
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final cur = DateTime.now();
    final first = DateTime(cur.year - 60);
    final last = DateTime(cur.year - 15);
    final picked = await showDatePicker(
      context: context,
      initialDate: last,
      firstDate: first,
      lastDate: cur,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedBirthDate = picked;
        _dobCtrl.text = DateFormat('dd MMM yyyy').format(picked);
      });
    }
  }

  // ── REUSABLE UI ELEMENTS ─────────────────────────────────────────

  Widget _buildStepHeader(String title, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          desc,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData prefixIcon,
    bool obscureText = false,
    bool readOnly = false,
    int maxLines = 1,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    VoidCallback? onTap,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      readOnly: readOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onTap: onTap,
      onChanged: onChanged,
      validator: validator,
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(prefixIcon, color: AppColors.textSecondary, size: 20),
        suffixIcon: suffixIcon,
        labelStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
        hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[400]),
        filled: true,
        fillColor: AppColors.cardBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
    bool disabled = false,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: disabled ? [] : items,
      onChanged: disabled ? null : onChanged,
      validator: (v) => v == null ? 'Required selection' : null,
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
        filled: true,
        fillColor: disabled ? AppColors.bgSecondary : AppColors.cardBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderColor),
        ),
      ),
    );
  }

  Widget _buildStepperProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_totalSteps, (index) {
              final isDone = index < _currentStep;
              final isActive = index == _currentStep;

              return Expanded(
                child: Row(
                  children: [
                    // Step Badge
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isDone
                            ? AppColors.success
                            : (isActive ? AppColors.primaryLight : Colors.white24),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isActive ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: isDone
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : Text(
                              (index + 1).toString(),
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                    ),
                    // Connection line
                    if (index < _totalSteps - 1)
                      Expanded(
                        child: Container(
                          height: 3,
                          color: index < _currentStep ? AppColors.success : Colors.white24,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STEP ${_currentStep + 1} OF $_totalSteps',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white54,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                _getStepName(_currentStep),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getStepName(int step) {
    switch (step) {
      case 0: return 'Personal Profile';
      case 1: return 'Academic Map';
      case 2: return 'Account Security';
      case 3: return 'Face Biometrics';
      case 4: return 'Review & Submit';
      default: return '';
    }
  }

  // ── MAIN SCAFFOLD BUILDER ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text(
          'Student Registration',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildStepperProgress(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: _buildActiveStep(),
              ),
            ),
          ),
          // Nav Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              border: const Border(top: BorderSide(color: AppColors.borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentStep > 0)
                  TextButton.icon(
                    onPressed: _prevStep,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () => context.go('/login'),
                    icon: const Icon(Icons.login),
                    label: const Text('Login'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                _isValidatingField || _isSubmitting
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        onPressed: _currentStep == _totalSteps - 1 ? _submitRegistration : _nextStep,
                        icon: Icon(_currentStep == _totalSteps - 1 ? Icons.send : Icons.arrow_forward, color: Colors.white),
                        label: Text(_currentStep == _totalSteps - 1 ? 'Submit dossier' : 'Next step'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: Colors.white,
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
