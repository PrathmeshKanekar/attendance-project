import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/api_client.dart';
import 'providers/virtual_room_providers.dart';
import 'room_capture_overlay.dart';
import 'room_preview_widget.dart';
import 'services/gps_security_service.dart';
import 'dart:math' as math;

const double kMinRoomSize = 3.0;   // meters
const double kMaxRoomSize = 100.0; // meters

class AddEditRoomScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingRoom;

  const AddEditRoomScreen({Key? key, this.existingRoom}) : super(key: key);

  @override
  ConsumerState<AddEditRoomScreen> createState() => _AddEditRoomScreenState();
}

class _AddEditRoomScreenState extends ConsumerState<AddEditRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Steps: 0 = Details, 1 = GPS Lock, 2 = Preview, 3 = Certify
  int _currentStep = 0;

  // Controllers
  late final TextEditingController _nameController;
  late final TextEditingController _buildingController;
  late final TextEditingController _departmentController;
  late final TextEditingController _floorController;
  late final TextEditingController _capacityController;
  late final TextEditingController _roomNumberController;

  // Selections
  String? _selectedCollegeId;
  String? _selectedCollegeName;
  String? _selectedLocationMethod = 'gps'; // 'gps' or 'manual'

  // Dynamic Department Master state
  List<Map<String, dynamic>> _departments = [];
  bool _isLoadingDepartments = false;
  String? _departmentsError;
  String? _selectedDepartmentId;
  String? _selectedDepartmentName;

  // Geometry
  double _centerLat = 0.0;
  double _centerLng = 0.0;
  double _widthMeters = 10.0;
  double _lengthMeters = 12.0;
  double _rotationDegrees = 0.0;
  double _confidenceScore = 100.0;
  double _gpsAccuracy = 0.0;
  List<LatLng> _roomPolygonPoints = [];
  double _roomAreaSqm = 0.0;

  // Security & Calibration State
  bool _isSaving = false;
  bool _showCaptureOverlay = false;
  final GpsSecurityService _securityService = GpsSecurityService();
  List<GpsSecurityFlag> _detectedGpsFlags = [];
  double _gpsHealthScore = 100.0;
  bool _gpsIsCalibrated = false;

  // Checklist Validation Statuses
  bool _checkedSelfIntersection = true;
  bool _checkedAreaLimits = false;
  bool _checkedMinDistance = false;
  bool _checkedDuplicateName = false;
  bool _checkedDuplicateCode = false;
  bool _isCheckingDuplicates = false;

  // Conflicts list from server
  List<Map<String, dynamic>> _serverConflicts = [];
  bool _duplicateCheckDone = false;

  void _recomputePolygon() {
    if (_centerLat == 0.0 || _centerLng == 0.0) return;

    final center = LatLng(_centerLat, _centerLng);
    final halfWidthDeg  = (_widthMeters  / 2) / 111320;
    final halfLengthDeg = (_lengthMeters / 2) / 111320;

    // Apply rotation
    final angleRad = _rotationDegrees * (math.pi / 180);

    final corners = [
      _rotatePoint(center, -halfWidthDeg, -halfLengthDeg, angleRad),
      _rotatePoint(center,  halfWidthDeg, -halfLengthDeg, angleRad),
      _rotatePoint(center,  halfWidthDeg,  halfLengthDeg, angleRad),
      _rotatePoint(center, -halfWidthDeg,  halfLengthDeg, angleRad),
    ];

    _roomPolygonPoints = corners;
    _roomAreaSqm = _widthMeters * _lengthMeters;
  }

  LatLng _rotatePoint(LatLng center, double dx, double dy, double angleRad) {
    final rotatedX = dx * math.cos(angleRad) - dy * math.sin(angleRad);
    final rotatedY = dx * math.sin(angleRad) + dy * math.cos(angleRad);
    return LatLng(center.latitude + rotatedY, center.longitude + rotatedX);
  }

  @override
  void initState() {
    super.initState();
    _widthMeters = 10.0.clamp(kMinRoomSize, kMaxRoomSize);
    _lengthMeters = 12.0.clamp(kMinRoomSize, kMaxRoomSize);

    _nameController = TextEditingController(text: widget.existingRoom?['name']?.toString() ?? '');
    _buildingController = TextEditingController(text: widget.existingRoom?['building']?.toString() ?? '');
    _departmentController = TextEditingController(text: widget.existingRoom?['department']?.toString() ?? '');
    _floorController = TextEditingController(text: widget.existingRoom?['floor_number']?.toString() ?? '0');
    _capacityController = TextEditingController(text: widget.existingRoom?['capacity']?.toString() ?? '60');
    _roomNumberController = TextEditingController(text: widget.existingRoom?['room_number']?.toString() ?? '');

    if (widget.existingRoom != null) {
      _selectedCollegeId = widget.existingRoom!['college']?.toString();
      _selectedDepartmentName = widget.existingRoom!['department']?.toString();
      _centerLat = (widget.existingRoom!['center_lat'] as num? ?? 0.0).toDouble();
      _centerLng = (widget.existingRoom!['center_lng'] as num? ?? 0.0).toDouble();
      final spatial = widget.existingRoom!['spatial_metadata'] as Map<String, dynamic>? ?? {};
      _widthMeters = ((widget.existingRoom!['width_meters'] as num? ?? spatial['width_meters'] as num? ?? 10.0).toDouble()).clamp(kMinRoomSize, kMaxRoomSize);
      _lengthMeters = ((widget.existingRoom!['length_meters'] as num? ?? spatial['length_meters'] as num? ?? 12.0).toDouble()).clamp(kMinRoomSize, kMaxRoomSize);
      _rotationDegrees = (widget.existingRoom!['orientation_degrees'] as num? ?? spatial['rotation_degrees'] as num? ?? 0.0).toDouble();
      _confidenceScore = (widget.existingRoom!['reconstruction_quality'] as num? ?? spatial['confidence_score'] as num? ?? 100.0).toDouble();
      _gpsAccuracy = (widget.existingRoom!['gps_accuracy'] as num? ?? 5.0).toDouble();
      _gpsHealthScore = (widget.existingRoom!['gps_health_score'] as num? ?? 100.0).toDouble();
      _selectedLocationMethod = widget.existingRoom!['location_method']?.toString() ?? 'gps';
      _gpsIsCalibrated = _centerLat != 0.0;
    }

    _recomputePolygon();

    // Proactively read logged-in user profile, assign college, and fetch departments on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCollegeAndFetchDepartments();
    });
  }

  void _initCollegeAndFetchDepartments() {
    final authState = ref.read(authProvider);
    if (authState is AuthSuccess) {
      final user = authState.user;
      setState(() {
        _selectedCollegeId = user.collegeId;
        _selectedCollegeName = user.collegeName;
      });
      if (user.collegeId != null && user.collegeId!.isNotEmpty) {
        _fetchDepartments(user.collegeId!);
      }
    }
  }

  Future<void> _fetchDepartments(String collegeId) async {
    setState(() {
      _isLoadingDepartments = true;
      _departmentsError = null;
      _departments = [];
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/api/departments/', params: {'college_id': collegeId});
      final List<Map<String, dynamic>> parsedList = [];
      final data = res.data;
      if (data is List) {
        parsedList.addAll(List<Map<String, dynamic>>.from(data));
      } else if (data is Map && data.containsKey('results')) {
        parsedList.addAll(List<Map<String, dynamic>>.from(data['results'] as List));
      }

      setState(() {
        _departments = parsedList;
        _isLoadingDepartments = false;
        
        // Resolve ID for pre-selected department name when editing
        if (_selectedDepartmentName != null && _selectedDepartmentId == null && _departments.isNotEmpty) {
          final match = _departments.firstWhere(
            (d) => d['name']?.toString().trim().toLowerCase() == _selectedDepartmentName!.trim().toLowerCase(),
            orElse: () => {},
          );
          if (match.isNotEmpty) {
            _selectedDepartmentId = match['id']?.toString();
          }
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingDepartments = false;
        _departmentsError = 'Failed to load departments. Tap to retry.';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _buildingController.dispose();
    _departmentController.dispose();
    _floorController.dispose();
    _capacityController.dispose();
    _roomNumberController.dispose();
    super.dispose();
  }

  // WGS84 Corner Geodetic Matrix Generator
  List<Map<String, dynamic>> _generateBackendCorners() {
    final double latRad = _centerLat * math.pi / 180.0;
    const double metersPerDegreeLat = 110574.0;
    final double metersPerDegreeLng = 111320.0 * math.cos(latRad);
    
    final double rotationRad = _rotationDegrees * math.pi / 180.0;
    final cosRot = math.cos(rotationRad);
    final sinRot = math.sin(rotationRad);
    
    final hw = _widthMeters / 2.0;
    final hl = _lengthMeters / 2.0;
    
    final offsets = [
      math.Point(hw, hl),
      math.Point(hw, -hl),
      math.Point(-hw, -hl),
      math.Point(-hw, hl),
    ];
    
    return List.generate(4, (idx) {
      final p = offsets[idx];
      final dx = p.x * cosRot + p.y * sinRot;
      final dy = -p.x * sinRot + p.y * cosRot;
      
      final latOffset = dy / metersPerDegreeLat;
      final lngOffset = dx / metersPerDegreeLng;
      
      return {
        'lat': _centerLat + latOffset,
        'lng': _centerLng + lngOffset,
        'alt': 0.0,
        'heading': _rotationDegrees,
        'accuracy': _gpsAccuracy > 0 ? _gpsAccuracy : 5.0,
        'gyro_x': 0.0,
        'gyro_y': 0.0,
        'gyro_z': 0.0,
        'accel_x': 0.0,
        'accel_y': 0.0,
        'accel_z': 0.0,
        'direction_label': 'N',
      };
    });
  }

  // Server-side duplicate validation check
  Future<void> _checkServerDuplicates() async {
    setState(() {
      _isCheckingDuplicates = true;
      _serverConflicts = [];
    });

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post(
        '/api/virtual-rooms/duplicate-check/',
        data: {
          'department': _departmentController.text.trim(),
          'building': _buildingController.text.trim(),
          'floor': _floorController.text.trim(),
          'room_number': _roomNumberController.text.trim(),
          'room_name': _nameController.text.trim(),
          'center_lat': _centerLat,
          'center_lng': _centerLng,
        },
      );

      final data = res.data;
      if (data is Map && data['conflicts'] != null) {
        setState(() {
          _serverConflicts = List<Map<String, dynamic>>.from(data['conflicts']);
          _duplicateCheckDone = true;
          
          // Update checklist tags
          _checkedDuplicateName = !_serverConflicts.any((c) => c['check'] == 'name_match');
          _checkedDuplicateCode = !_serverConflicts.any((c) => c['check'] == 'metadata_match');
          _checkedMinDistance = !_serverConflicts.any((c) => c['check'] == 'coordinate_proximity');
        });
      }
    } catch (e) {
      debugPrint('Error performing server duplicate check: $e');
    } finally {
      setState(() => _isCheckingDuplicates = false);
    }
  }

  // Pre-save checklist conditions
  double _calculateRealTimeArea() {
    return _widthMeters * _lengthMeters;
  }

  bool _isFormValid() {
    if (_formKey.currentState == null) return false;
    return _formKey.currentState!.validate() &&
        _selectedDepartmentId != null &&
        _buildingController.text.isNotEmpty &&
        _nameController.text.isNotEmpty;
  }

  Future<void> _submitForm() async {
    final authState = ref.read(authProvider);
    if (authState is! AuthSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session not authenticated. Please log in again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final collegeId = authState.user.collegeId;
    if (collegeId == null || collegeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('College information not found. Please log out and log in again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_selectedDepartmentId == null || _departments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a valid department to save.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_isFormValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill out all identity and department fields first.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_gpsIsCalibrated || _centerLat == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please stabilize the room coordinates first (Step 2).'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final hasHardConflict = _serverConflicts.any((c) => c['severity'] == 'hard');
    if (hasHardConflict) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot create room due to hard conflict at this exact building location.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final corners = _generateBackendCorners();

    final payload = {
      'name': _nameController.text.trim(),
      'building': _buildingController.text.trim(),
      'department': _selectedDepartmentName ?? _departmentController.text.trim(),
      'floor_number': int.tryParse(_floorController.text) ?? 0,
      'capacity': int.tryParse(_capacityController.text) ?? 60,
      'room_number': _roomNumberController.text.trim(),
      'location_method': _selectedLocationMethod,
      'gps_accuracy': _gpsAccuracy,
      'gps_health_score': _gpsHealthScore,
      'width_meters': _widthMeters,
      'length_meters': _lengthMeters,
      'corner_coordinates': corners,
      'college': collegeId,
      'spatial_metadata': {
        'width_meters': _widthMeters,
        'length_meters': _lengthMeters,
        'rotation_degrees': _rotationDegrees,
        'confidence_score': _confidenceScore,
        'is_rotated_rectangle': true,
        'gps_security_flags_count': _detectedGpsFlags.length,
      }
    };

    final notifier = ref.read(virtualRoomsProvider.notifier);
    bool success = false;

    if (widget.existingRoom != null) {
      final id = widget.existingRoom!['id'].toString();
      success = await notifier.editRoom(id, payload);
    } else {
      success = await notifier.addRoom(payload);
    }

    setState(() => _isSaving = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existingRoom != null
                ? 'Virtual room certified & updated.'
                : 'Virtual room created successfully.'),
            backgroundColor: Colors.teal,
          ),
        );
        context.pop();
      } else {
        final state = ref.read(virtualRoomsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.error ?? 'Failed to save virtual room.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          AppLayout(
            title: widget.existingRoom != null ? 'Edit Virtual Room' : 'Create Virtual Room',
            child: Column(
              children: [
                // Horizontal Modern Custom Stepper Header
                _buildStepperHeader(theme, isDark),
                
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                    child: Form(
                      key: _formKey,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _buildCurrentStepView(theme, isDark),
                      ),
                    ),
                  ),
                ),
                
                // Stepper Action Navigation Panel
                _buildNavigationPanel(theme, isDark),
              ],
            ),
          ),

          // High-Precision Center Calibration Overlay Modal
          if (_showCaptureOverlay)
            Positioned.fill(
              child: RoomCaptureOverlay(
                onCancel: () => setState(() => _showCaptureOverlay = false),
                onCaptured: (reading) {
                  // Run client-side security anti-spoof checks
                  final rawPos = Position(
                    latitude: reading.latitude,
                    longitude: reading.longitude,
                    timestamp: DateTime.now(),
                    accuracy: reading.accuracy,
                    altitude: reading.altitude,
                    altitudeAccuracy: 0.0,
                    heading: reading.heading,
                    headingAccuracy: 0.0,
                    speed: 0.0,
                    speedAccuracy: 0.0,
                    isMocked: false, // Let GPS anti-spoof engine check
                  );

                  final secResult = _securityService.evaluatePosition(rawPos);

                  setState(() {
                    _centerLat = reading.latitude;
                    _centerLng = reading.longitude;
                    _rotationDegrees = reading.heading;
                    _gpsAccuracy = reading.accuracy;
                    _gpsHealthScore = secResult.healthScore;
                    _detectedGpsFlags = secResult.flags;
                    _confidenceScore = secResult.healthScore;
                    
                    _gpsIsCalibrated = true;
                    _showCaptureOverlay = false;
                  });

                  if (!secResult.isSecure) {
                    final warningMsg = secResult.flags.map((f) => f.description).join(', ');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('⚠️ Security Flags Detected: $warningMsg'),
                        backgroundColor: Colors.amber.shade900,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Room center stabilized & calibrated securely.'),
                        backgroundColor: Colors.teal,
                      ),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  // ── Custom Stepper Header ──────────────────────────────────────────────────
  Widget _buildStepperHeader(ThemeData theme, bool isDark) {
    final steps = ['Details', 'GPS Lock', 'Preview', 'Certify'];
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(steps.length, (idx) {
          final isActive = _currentStep == idx;
          final isCompleted = _currentStep > idx;
          
          return Expanded(
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? theme.primaryColor
                        : isCompleted
                            ? Colors.teal
                            : isDark
                                ? const Color(0xFF1E293B)
                                : Colors.grey.shade200,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 16.0)
                        : Text(
                            '${idx + 1}',
                            style: TextStyle(
                              color: isActive || isCompleted
                                  ? Colors.white
                                  : isDark
                                      ? Colors.white60
                                      : Colors.black54,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.0,
                              ),
                          ),
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    steps[idx],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive
                          ? theme.primaryColor
                          : isCompleted
                              ? Colors.teal
                              : isDark
                                  ? Colors.white38
                                  : Colors.black38,
                    ),
                  ),
                ),
                if (idx < steps.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 14.0,
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Render Step Views ──────────────────────────────────────────────────────
  Widget _buildCurrentStepView(ThemeData theme, bool isDark) {
    switch (_currentStep) {
      case 0:
        return _buildStepDetails(theme, isDark);
      case 1:
        return _buildStepGpsCapture(theme, isDark);
      case 2:
        return _buildStepPreview(theme, isDark);
      case 3:
        return _buildStepCertification(theme, isDark);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── STEP 1: Room Identity & Info Details ──────────────────────────────────
  Widget _buildStepDetails(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Room Identity & Spatial Parameters'),
        const SizedBox(height: 8.0),
        Text(
          'Provide unique room parameters for institutional attendance verification.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
        ),
        const SizedBox(height: 20.0),
        _buildFormCard(isDark, [
          // Department Searchable Dropdown from API
          _buildDepartmentDropdown(theme, isDark),
          const SizedBox(height: 16.0),

          // Room Name
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Room Name / Reference (e.g. LAB-304) *',
              prefixIcon: Icon(Icons.sensor_door_rounded),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Room name is required' : null,
          ),
          const SizedBox(height: 16.0),

          // Room Number
          TextFormField(
            controller: _roomNumberController,
            decoration: const InputDecoration(
              labelText: 'Official Room Number',
              prefixIcon: Icon(Icons.pin_rounded),
            ),
          ),
          const SizedBox(height: 16.0),

          // Building
          TextFormField(
            controller: _buildingController,
            decoration: const InputDecoration(
              labelText: 'Building / Wing Name *',
              prefixIcon: Icon(Icons.apartment_rounded),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Building name is required' : null,
          ),
          const SizedBox(height: 16.0),

          Row(
            children: [
              // Floor
              Expanded(
                child: TextFormField(
                  controller: _floorController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Floor Level',
                    prefixIcon: Icon(Icons.layers_rounded),
                  ),
                  validator: (v) => v == null || int.tryParse(v) == null ? 'Invalid floor' : null,
                ),
              ),
              const SizedBox(width: 16.0),

              // Capacity
              Expanded(
                child: TextFormField(
                  controller: _capacityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max Capacity',
                    prefixIcon: Icon(Icons.people_rounded),
                  ),
                  validator: (v) => v == null || int.tryParse(v) == null ? 'Invalid capacity' : null,
                ),
              ),
            ],
          ),
        ]),
      ],
    );
  }

  Widget _buildDepartmentDropdown(ThemeData theme, bool isDark) {
    if (_isLoadingDepartments) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal),
            ),
            const SizedBox(width: 12),
            Text('Fetching departments...', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    if (_departmentsError != null) {
      return Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.red.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _departmentsError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                if (_selectedCollegeId != null) {
                  _fetchDepartments(_selectedCollegeId!);
                } else {
                  _initCollegeAndFetchDepartments();
                }
              },
              icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.redAccent),
              label: const Text('Retry', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    if (_departments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.amber.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No departments found for your college.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Autocomplete<Map<String, dynamic>>(
      displayStringForOption: (d) => d['name']?.toString() ?? '',
      optionsBuilder: (textVal) {
        if (_departments.isEmpty) return const Iterable.empty();
        return _departments.where((d) => d['name']
            .toString()
            .toLowerCase()
            .contains(textVal.text.toLowerCase()));
      },
      onSelected: (d) {
        setState(() {
          _selectedDepartmentId = d['id']?.toString();
          _selectedDepartmentName = d['name']?.toString();
          _departmentController.text = d['name']?.toString() ?? '';
        });
      },
      fieldViewBuilder: (ctx, textCtrl, node, onSubmit) {
        if (textCtrl.text.isEmpty && _selectedDepartmentName != null) {
          textCtrl.text = _selectedDepartmentName!;
        }
        textCtrl.addListener(() {
          if (textCtrl.text != _selectedDepartmentName) {
            // Sync with current text choice
            final match = _departments.firstWhere(
              (d) => d['name']?.toString().trim().toLowerCase() == textCtrl.text.trim().toLowerCase(),
              orElse: () => {},
            );
            setState(() {
              if (match.isNotEmpty) {
                _selectedDepartmentId = match['id']?.toString();
                _selectedDepartmentName = match['name']?.toString();
                _departmentController.text = match['name']?.toString() ?? '';
              } else {
                _selectedDepartmentId = null;
                _selectedDepartmentName = null;
                _departmentController.text = '';
              }
            });
          }
        });
        return TextFormField(
          controller: textCtrl,
          focusNode: node,
          decoration: const InputDecoration(
            labelText: 'Department Master *',
            prefixIcon: Icon(Icons.work_rounded),
            suffixIcon: Icon(Icons.arrow_drop_down_rounded),
          ),
          validator: (v) {
            if (_selectedDepartmentId == null) {
              return 'Department is required';
            }
            return null;
          },
        );
      },
    );
  }

  // ── STEP 3: GPS Calibration and Stabilization ──────────────────────────────
  Widget _buildStepGpsCapture(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'GPS Lock & Anti-Spoof Stabilization'),
        const SizedBox(height: 8.0),
        Text(
          'Stand in the absolute center of the physical room to calibrate spatial boundaries.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
        ),
        const SizedBox(height: 20.0),
        
        _buildFormCard(isDark, [
          // Select Location Method
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('GPS LOCK'),
                  selected: _selectedLocationMethod == 'gps',
                  onSelected: (val) {
                    setState(() => _selectedLocationMethod = 'gps');
                  },
                ),
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: ChoiceChip(
                  label: const Text('MANUAL ENT.'),
                  selected: _selectedLocationMethod == 'manual',
                  onSelected: (val) {
                    setState(() => _selectedLocationMethod = 'manual');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24.0),

          if (_selectedLocationMethod == 'gps') ...[
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.teal.shade50,
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(
                  color: _gpsIsCalibrated ? Colors.teal : theme.primaryColor.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _gpsIsCalibrated ? Icons.verified_user_rounded : Icons.radar_rounded,
                        color: _gpsIsCalibrated ? Colors.teal : Colors.orangeAccent,
                        size: 28.0,
                      ),
                      const SizedBox(width: 12.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _gpsIsCalibrated ? 'Coordinates Calibrated' : 'GPS Calibration Required',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _gpsIsCalibrated ? Colors.teal : theme.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              _gpsIsCalibrated
                                  ? 'Lat: ${_centerLat.toStringAsFixed(6)} / Lng: ${_centerLng.toStringAsFixed(6)}'
                                  : 'Capture stabilized telemetry from physical device sensors.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16.0),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _showCaptureOverlay = true),
                    icon: const Icon(Icons.gps_fixed_rounded, size: 18.0),
                    label: Text(_gpsIsCalibrated ? 'RE-CALIBRATE ROOM CENTER' : 'CALIBRATE ROOM CENTER'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 44.0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16.0),

            // Telemetry Security Health Report Card
            if (_gpsIsCalibrated) ...[
              const SizedBox(height: 12.0),
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Telemetry Security Report',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _gpsHealthScore >= 80 ? Colors.teal.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          child: Text(
                            'Score: ${_gpsHealthScore.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: _gpsHealthScore >= 80 ? Colors.teal : Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12.0),
                    _buildSecurityCheckRow('Mock location checks', _detectedGpsFlags.isEmpty),
                    _buildSecurityCheckRow('Accuracy verification (±${_gpsAccuracy.toStringAsFixed(1)}m)', _gpsAccuracy < 35.0),
                    _buildSecurityCheckRow('Jump protection telemetry', !_detectedGpsFlags.any((f) => f.flagType == 'coordinate_jump')),
                    _buildSecurityCheckRow('Oscillation shielding', !_detectedGpsFlags.any((f) => f.flagType == 'rapid_oscillation')),
                  ],
                ),
              ),
            ],
          ] else ...[
            // Manual coordinate fields
            TextFormField(
              initialValue: _centerLat.toString(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Manual Center Latitude *',
                prefixIcon: Icon(Icons.map_rounded),
              ),
              onChanged: (v) {
                _centerLat = double.tryParse(v) ?? 0.0;
                _gpsIsCalibrated = _centerLat != 0.0 && _centerLng != 0.0;
              },
            ),
            const SizedBox(height: 16.0),
            TextFormField(
              initialValue: _centerLng.toString(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Manual Center Longitude *',
                prefixIcon: Icon(Icons.explore_rounded),
              ),
              onChanged: (v) {
                _centerLng = double.tryParse(v) ?? 0.0;
                _gpsIsCalibrated = _centerLat != 0.0 && _centerLng != 0.0;
              },
            ),
          ],
        ]),
      ],
    );
  }

  Widget _buildSecurityCheckRow(String label, bool isPass) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            isPass ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
            color: isPass ? Colors.teal : Colors.amber,
            size: 18.0,
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13.0),
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP 3: Live Map Boundary Preview ──────────────────────────────────────
  Widget _buildStepPreview(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Interactive Boundary & Dimensions'),
        const SizedBox(height: 8.0),
        Text(
          'Tune geofence borders dynamically. Drag sliders below to match the physical room dimensions.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
        ),
        const SizedBox(height: 16.0),

        RoomPreviewWidget(
          centerLat: _centerLat,
          centerLng: _centerLng,
          widthMeters: _widthMeters,
          lengthMeters: _lengthMeters,
          rotationDegrees: _rotationDegrees,
          confidenceScore: _confidenceScore,
          roomPolygonPoints: _roomPolygonPoints,
          onGeometryChanged: (newLat, newLng, newWidth, newLength, newRotation) {
            setState(() {
              _centerLat = newLat;
              _centerLng = newLng;
              _widthMeters = newWidth.clamp(kMinRoomSize, kMaxRoomSize);
              _lengthMeters = newLength.clamp(kMinRoomSize, kMaxRoomSize);
              _rotationDegrees = newRotation;
              _recomputePolygon();
            });
          },
        ),
        const SizedBox(height: 20.0),

        _buildFormCard(isDark, [
          const Text(
            'Interactive Tuning Controls',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12.0),
          
          // Width tune slider
          Row(
            children: [
              const SizedBox(width: 70, child: Text('Width (m)')),
              Expanded(
                child: Slider(
                  value: _widthMeters.clamp(kMinRoomSize, kMaxRoomSize),
                  min: kMinRoomSize,
                  max: kMaxRoomSize,
                  divisions: 97,
                  onChanged: (val) {
                    setState(() {
                      _widthMeters = val.clamp(kMinRoomSize, kMaxRoomSize);
                      _recomputePolygon();
                    });
                  },
                ),
              ),
              Text('${_widthMeters.toStringAsFixed(1)}m'),
            ],
          ),

          // Length tune slider
          Row(
            children: [
              const SizedBox(width: 70, child: Text('Length (m)')),
              Expanded(
                child: Slider(
                  value: _lengthMeters.clamp(kMinRoomSize, kMaxRoomSize),
                  min: kMinRoomSize,
                  max: kMaxRoomSize,
                  divisions: 97,
                  onChanged: (val) {
                    setState(() {
                      _lengthMeters = val.clamp(kMinRoomSize, kMaxRoomSize);
                      _recomputePolygon();
                    });
                  },
                ),
              ),
              Text('${_lengthMeters.toStringAsFixed(1)}m'),
            ],
          ),

          // Yaw / orientation tuning
          Row(
            children: [
              const SizedBox(width: 70, child: Text('Yaw (deg)')),
              Expanded(
                child: Slider(
                  value: _rotationDegrees.clamp(0.0, 360.0),
                  min: 0.0,
                  max: 360.0,
                  onChanged: (val) {
                    setState(() {
                      _rotationDegrees = val.clamp(0.0, 360.0);
                      _recomputePolygon();
                    });
                  },
                ),
              ),
              Text('${_rotationDegrees.toStringAsFixed(0)}°'),
            ],
          ),
          const SizedBox(height: 16.0),

          // Live readout below sliders
          Center(
            child: Text(
              'Width: ${_widthMeters.toStringAsFixed(1)} m   '
              'Length: ${_lengthMeters.toStringAsFixed(1)} m   '
              'Area: ${_roomAreaSqm.toStringAsFixed(1)} m²',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.0,
                color: Colors.teal,
              ),
            ),
          ),
        ]),
      ],
    );
  }

  // ── STEP 5: Certification & Checklist Checklist ───────────────────────────
  Widget _buildStepCertification(ThemeData theme, bool isDark) {
    final computedArea = _calculateRealTimeArea();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(theme, 'Validation Checklist & Certification'),
        const SizedBox(height: 8.0),
        Text(
          'Ensure the virtual room meets all physical and digital safety properties before activation.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
        ),
        const SizedBox(height: 20.0),

        _buildFormCard(isDark, [
          const Text(
            'Spatial & Physical Validation',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0),
          ),
          const SizedBox(height: 12.0),

          _buildChecklistRow(
            'Self-Intersection Checks',
            _checkedSelfIntersection,
            'No twisted borders detected',
          ),
          _buildChecklistRow(
            'Indoor Area Constraints',
            computedArea >= 9.0 && computedArea <= 1200.0,
            'Calculated Area: ${computedArea.toStringAsFixed(1)} m² (Required: 9–1200 m²)',
          ),
          _buildChecklistRow(
            'Coarse GPS Precision Check',
            _gpsAccuracy <= 35.0 || _selectedLocationMethod == 'manual',
            'GPS Accuracy: ±${_gpsAccuracy.toStringAsFixed(1)}m (Required: <= 35.0m)',
          ),

          const Divider(height: 24.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tenant Conflict Auditing',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0),
              ),
              if (_isCheckingDuplicates)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal),
                )
              else
                IconButton(
                  icon: const Icon(Icons.sync_rounded, color: Colors.teal),
                  onPressed: _checkServerDuplicates,
                  tooltip: 'Force scan conflicts',
                ),
            ],
          ),
          const SizedBox(height: 12.0),

          if (!_duplicateCheckDone)
            ElevatedButton(
              onPressed: _checkServerDuplicates,
              style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor),
              child: const Text('RUN CONFLICT & DUPLICATE CHECKS'),
            )
          else ...[
            _buildChecklistRow(
              'Unique Name Constraint',
              _checkedDuplicateName,
              _checkedDuplicateName ? 'No naming conflicts' : 'Room name match detected',
            ),
            _buildChecklistRow(
              'Location Metadata Constraint',
              _checkedDuplicateCode,
              _checkedDuplicateCode ? 'No duplicate room codes' : 'Room already defined at this physical spot',
            ),
            _buildChecklistRow(
              'Co-Location Proximity Shield',
              _checkedMinDistance,
              _checkedMinDistance ? 'No nearby room overlap conflict' : 'Nearby room overlap within 3m detected',
            ),
          ],

          if (_serverConflicts.isNotEmpty) ...[
            const SizedBox(height: 16.0),
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18.0),
                      SizedBox(width: 8.0),
                      Text(
                        'CRITICAL DATABASE CONFLICTS DETECTED',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  ..._serverConflicts.map((c) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text(
                      '• ${c['message']}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12.0),
                    ),
                  )),
                ],
              ),
            ),
          ],
        ]),
      ],
    );
  }

  Widget _buildChecklistRow(String title, bool isChecked, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isChecked ? Icons.check_circle_rounded : Icons.cancel_outlined,
            color: isChecked ? Colors.teal : Colors.redAccent,
            size: 20.0,
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.0),
                ),
                const SizedBox(height: 2.0),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11.0),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Navigation Control Panel ───────────────────────────────────────────────
  Widget _buildNavigationPanel(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: () {
                setState(() => _currentStep--);
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
              ),
              child: const Text('BACK'),
            )
          else
            const SizedBox.shrink(),
          
          ElevatedButton(
            onPressed: () {
              if (_currentStep == 3) {
                if (_isSaving) return;
                _submitForm();
              } else {
                // Stepper Validation gates
                if (_currentStep == 0 && !_isFormValid()) {
                  return;
                }
                if (_currentStep == 1 && !_gpsIsCalibrated) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please calibrate coordinates first.')),
                  );
                  return;
                }

                // If moving into step 3, trigger conflict scanner automatically
                if (_currentStep == 2) {
                  _checkServerDuplicates();
                }

                setState(() => _currentStep++);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _currentStep == 3 ? Colors.teal.shade700 : theme.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(_currentStep == 3 ? 'CERTIFY & SAVE' : 'CONTINUE'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.primaryColor,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildFormCard(bool isDark, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24.0),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.grey.shade100,
                  blurRadius: 16.0,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}