import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
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

class LocationMethod {
  static const String mapClick    = 'map_click';
  static const String walkCorner  = 'walk_corner';
  static const String manual      = 'manual';
  static const String coordArea   = 'coord_area';
}

class VirtualRoomFormState {
  String name = '';
  String building = '';
  String department = '';
  String floorNumber = '0';
  String capacity = '60';
  String roomNumber = '';
  String locationMethod = LocationMethod.mapClick;

  double centerLat = 0.0;
  double centerLng = 0.0;
  double widthMeters = 10.0;
  double lengthMeters = 12.0;
  double rotationDegrees = 0.0;
  double gpsAccuracy = 5.0;
  double gpsHealthScore = 100.0;
  double confidenceScore = 100.0;

  List<LatLng> corners = []; // exactly 4 corners
  double areaSqm = 0.0;
  double perimeterMeters = 0.0;
  double orientationDegrees = 0.0;
}

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

  // Dynamic Department Master state
  List<Map<String, dynamic>> _departments = [];
  bool _isLoadingDepartments = false;
  String? _departmentsError;
  String? _selectedDepartmentId;
  String? _selectedDepartmentName;

  // Geometry & Form State
  final VirtualRoomFormState _formState = VirtualRoomFormState();
  late final List<TextEditingController> _manualCoordsControllers;
  late final TextEditingController _method4LatController;
  late final TextEditingController _method4LngController;
  late final TextEditingController _method4AreaController;
  LatLng? _userLocationForMap;

  // Walk corner capture state
  int? _capturingCornerIndex;
  int _walkReadingsCount = 0;
  final List<Position> _walkPositions = [];

  // Security & Calibration State
  bool _isSaving = false;
  bool _showCaptureOverlay = false;
  final GpsSecurityService _securityService = GpsSecurityService();
  List<GpsSecurityFlag> _detectedGpsFlags = [];
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

  void _computePolygonMetrics() {
    if (_formState.corners.length != 4) {
      _formState.areaSqm = 0.0;
      _formState.perimeterMeters = 0.0;
      return;
    }

    // 1. Centroid calculation
    double sumLat = 0.0;
    double sumLng = 0.0;
    for (var pt in _formState.corners) {
      sumLat += pt.latitude;
      sumLng += pt.longitude;
    }
    _formState.centerLat = sumLat / 4.0;
    _formState.centerLng = sumLng / 4.0;

    // 2. Sort clockwise around centroid to prevent self-intersection
    final cx = _formState.centerLat;
    final cy = _formState.centerLng;
    _formState.corners.sort((a, b) {
      final angleA = math.atan2(a.latitude - cx, a.longitude - cy);
      final angleB = math.atan2(b.latitude - cx, b.longitude - cy);
      return angleB.compareTo(angleA);
    });

    // 3. Local Cartesian Projection
    final double latRad = cx * math.pi / 180.0;
    const double metersPerDegreeLat = 110574.0;
    final double metersPerDegreeLng = 111320.0 * math.cos(latRad);

    final localPts = _formState.corners.map((p) {
      final x = (p.longitude - cy) * metersPerDegreeLng;
      final y = (p.latitude - cx) * metersPerDegreeLat;
      return math.Point(x, y);
    }).toList();

    // 4. Shoelace Formula for Area
    double shoelaceSum = 0.0;
    for (int i = 0; i < 4; i++) {
      final nextIdx = (i + 1) % 4;
      shoelaceSum += (localPts[i].x * localPts[nextIdx].y) - (localPts[nextIdx].x * localPts[i].y);
    }
    _formState.areaSqm = (shoelaceSum.abs()) / 2.0;

    // 5. Perimeter & Side lengths
    double perimeter = 0.0;
    final wallLengths = <double>[];
    for (int i = 0; i < 4; i++) {
      final nextIdx = (i + 1) % 4;
      final dx = localPts[nextIdx].x - localPts[i].x;
      final dy = localPts[nextIdx].y - localPts[i].y;
      final len = math.sqrt(dx * dx + dy * dy);
      wallLengths.add(len);
      perimeter += len;
    }
    _formState.perimeterMeters = perimeter;

    // Approximated side lengths
    _formState.widthMeters = (wallLengths[0] + wallLengths[2]) / 2.0;
    _formState.lengthMeters = (wallLengths[1] + wallLengths[3]) / 2.0;

    // 6. Orientation (angle of longest side)
    double maxLen = -1.0;
    int longestWallIdx = 0;
    for (int i = 0; i < 4; i++) {
      if (wallLengths[i] > maxLen) {
        maxLen = wallLengths[i];
        longestWallIdx = i;
      }
    }
    final p1 = localPts[longestWallIdx];
    final p2 = localPts[(longestWallIdx + 1) % 4];
    final radians = math.atan2(p2.x - p1.x, p2.y - p1.y);
    _formState.orientationDegrees = (radians * 180.0 / math.pi + 360.0) % 360.0;
    _formState.rotationDegrees = _formState.orientationDegrees;

    // 7. Quality metrics (convex check & GPS signal check)
    bool isConvex = true;
    bool? firstSign;
    for (int i = 0; i < 4; i++) {
      final p0 = localPts[i];
      final p1 = localPts[(i + 1) % 4];
      final p2 = localPts[(i + 2) % 4];
      final cross = (p1.x - p0.x) * (p2.y - p1.y) - (p1.y - p0.y) * (p2.x - p1.x);
      if (firstSign == null) {
        firstSign = cross > 0;
      } else {
        if ((cross > 0) != firstSign) {
          isConvex = false;
          break;
        }
      }
    }
    double quality = 100.0;
    if (!isConvex) quality -= 30.0;
    if (_formState.gpsAccuracy > 5.0) {
      quality -= (_formState.gpsAccuracy - 5.0) * 2.0;
    }
    _formState.confidenceScore = quality.clamp(10.0, 100.0);
  }

  void _regenerateRotatedRectangleCorners() {
    if (_formState.centerLat == 0.0 || _formState.centerLng == 0.0) return;

    final double latRad = _formState.centerLat * math.pi / 180.0;
    const double metersPerDegreeLat = 110574.0;
    final double metersPerDegreeLng = 111320.0 * math.cos(latRad);
    
    final double rotationRad = _formState.rotationDegrees * math.pi / 180.0;
    final cosRot = math.cos(rotationRad);
    final sinRot = math.sin(rotationRad);
    
    final hw = _formState.widthMeters / 2.0;
    final hl = _formState.lengthMeters / 2.0;
    
    final offsets = [
      math.Point(hw, hl),
      math.Point(hw, -hl),
      math.Point(-hw, -hl),
      math.Point(-hw, hl),
    ];
    
    _formState.corners = offsets.map((p) {
      final dx = p.x * cosRot + p.y * sinRot;
      final dy = -p.x * sinRot + p.y * cosRot;
      
      final latOffset = dy / metersPerDegreeLat;
      final lngOffset = dx / metersPerDegreeLng;
      
      return LatLng(_formState.centerLat + latOffset, _formState.centerLng + lngOffset);
    }).toList();
  }

  void _loadUserLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          _userLocationForMap = LatLng(pos.latitude, pos.longitude);
          if (_formState.centerLat == 0.0) {
            _formState.centerLat = pos.latitude;
            _formState.centerLng = pos.longitude;
          }
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _formState.widthMeters = 10.0.clamp(kMinRoomSize, kMaxRoomSize);
    _formState.lengthMeters = 12.0.clamp(kMinRoomSize, kMaxRoomSize);

    _nameController = TextEditingController(text: widget.existingRoom?['name']?.toString() ?? '');
    _buildingController = TextEditingController(text: widget.existingRoom?['building']?.toString() ?? '');
    _departmentController = TextEditingController(text: widget.existingRoom?['department']?.toString() ?? '');
    _floorController = TextEditingController(text: widget.existingRoom?['floor_number']?.toString() ?? '0');
    _capacityController = TextEditingController(text: widget.existingRoom?['capacity']?.toString() ?? '60');
    _roomNumberController = TextEditingController(text: widget.existingRoom?['room_number']?.toString() ?? '');

    if (widget.existingRoom != null) {
      _selectedCollegeId = widget.existingRoom!['college']?.toString();
      _selectedDepartmentName = widget.existingRoom!['department']?.toString();
      _formState.centerLat = (widget.existingRoom!['center_lat'] as num? ?? 0.0).toDouble();
      _formState.centerLng = (widget.existingRoom!['center_lng'] as num? ?? 0.0).toDouble();
      final spatial = widget.existingRoom!['spatial_metadata'] as Map<String, dynamic>? ?? {};
      _formState.widthMeters = ((widget.existingRoom!['width_meters'] as num? ?? spatial['width_meters'] as num? ?? 10.0).toDouble()).clamp(kMinRoomSize, kMaxRoomSize);
      _formState.lengthMeters = ((widget.existingRoom!['length_meters'] as num? ?? spatial['length_meters'] as num? ?? 12.0).toDouble()).clamp(kMinRoomSize, kMaxRoomSize);
      _formState.rotationDegrees = (widget.existingRoom!['orientation_degrees'] as num? ?? spatial['rotation_degrees'] as num? ?? 0.0).toDouble();
      _formState.confidenceScore = (widget.existingRoom!['reconstruction_quality'] as num? ?? spatial['confidence_score'] as num? ?? 100.0).toDouble();
      _formState.gpsAccuracy = (widget.existingRoom!['gps_accuracy'] as num? ?? 5.0).toDouble();
      _formState.gpsHealthScore = (widget.existingRoom!['gps_health_score'] as num? ?? 100.0).toDouble();
      
      final rawMethod = widget.existingRoom!['location_method']?.toString() ?? LocationMethod.mapClick;
      if (rawMethod == LocationMethod.mapClick || rawMethod == 'method1') {
        _formState.locationMethod = LocationMethod.mapClick;
      } else if (rawMethod == LocationMethod.walkCorner || rawMethod == 'method2' || rawMethod == 'gps') {
        _formState.locationMethod = LocationMethod.walkCorner;
      } else if (rawMethod == LocationMethod.manual || rawMethod == 'method3') {
        _formState.locationMethod = LocationMethod.manual;
      } else if (rawMethod == LocationMethod.coordArea || rawMethod == 'method4') {
        _formState.locationMethod = LocationMethod.coordArea;
      } else {
        _formState.locationMethod = LocationMethod.mapClick;
      }

      final cornersList = widget.existingRoom!['corners'] as List? ?? [];
      if (cornersList.isNotEmpty) {
        _formState.corners = cornersList.map((c) {
          final lat = (c['latitude'] as num? ?? c['lat'] as num? ?? 0.0).toDouble();
          final lng = (c['longitude'] as num? ?? c['lng'] as num? ?? 0.0).toDouble();
          return LatLng(lat, lng);
        }).toList();
        _gpsIsCalibrated = true;
      }
    } else {
      _formState.locationMethod = LocationMethod.mapClick;
    }

    _manualCoordsControllers = List.generate(8, (idx) {
      if (_formState.corners.length == 4) {
        final cIdx = idx ~/ 2;
        final isLng = idx % 2 == 1;
        final c = _formState.corners[cIdx];
        final val = isLng ? c.longitude : c.latitude;
        return TextEditingController(text: val != 0.0 ? val.toString() : '');
      }
      return TextEditingController();
    });

    _method4LatController = TextEditingController(text: _formState.centerLat != 0.0 ? _formState.centerLat.toString() : '');
    _method4LngController = TextEditingController(text: _formState.centerLng != 0.0 ? _formState.centerLng.toString() : '');
    _method4AreaController = TextEditingController(text: _formState.areaSqm > 0.0 ? _formState.areaSqm.toString() : '120.0');

    _computePolygonMetrics();
    _loadUserLocation();

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
    _method4LatController.dispose();
    _method4LngController.dispose();
    _method4AreaController.dispose();
    for (var controller in _manualCoordsControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // WGS84 Corner Geodetic Matrix Generator
  List<Map<String, dynamic>> _generateBackendCorners() {
    return List.generate(_formState.corners.length, (idx) {
      final p = _formState.corners[idx];
      return {
        'lat': p.latitude,
        'lng': p.longitude,
        'alt': 0.0,
        'heading': _formState.rotationDegrees,
        'accuracy': _formState.gpsAccuracy > 0 ? _formState.gpsAccuracy : 5.0,
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
          'center_lat': _formState.centerLat,
          'center_lng': _formState.centerLng,
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
    return _formState.areaSqm;
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

    if (!_gpsIsCalibrated || _formState.centerLat == 0.0 || _formState.corners.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please define exactly 4 room corners first (Step 2).'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Run duplicate scan right before every save
    await _checkServerDuplicates();

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
      'location_method': _formState.locationMethod,
      'gps_accuracy': _formState.locationMethod == LocationMethod.walkCorner
          ? _formState.gpsAccuracy
          : null,
      'gps_health_score': _formState.locationMethod == LocationMethod.walkCorner
          ? _formState.gpsHealthScore
          : null,
      'width_meters': _formState.widthMeters,
      'length_meters': _formState.lengthMeters,
      'corner_coordinates': corners,
      'college': collegeId,
      'spatial_metadata': {
        'width_meters': _formState.widthMeters,
        'length_meters': _formState.lengthMeters,
        'rotation_degrees': _formState.rotationDegrees,
        'confidence_score': _formState.confidenceScore,
        'is_rotated_rectangle': true,
        'gps_security_flags_count': _detectedGpsFlags.length,
        'area_sqm': _formState.areaSqm,
      }
    };

    debugPrint('PAYLOAD location_method: ${payload['location_method']}');
    debugPrint('PAYLOAD gps_accuracy: ${payload['gps_accuracy']}');
    debugPrint('PAYLOAD corners count: '
        '${(payload['corner_coordinates'] as List).length}');
    debugPrint('PAYLOAD corner[0]: ${(payload['corner_coordinates'] as List)[0]}');

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

                  if (_formState.locationMethod == LocationMethod.coordArea) {
                    _method4LatController.text = reading.latitude.toString();
                    _method4LngController.text = reading.longitude.toString();
                    _formState.gpsAccuracy = reading.accuracy;
                    _formState.gpsHealthScore = secResult.healthScore;
                    _detectedGpsFlags = secResult.flags;
                    _formState.confidenceScore = secResult.healthScore;
                    _updateMethod4Square();
                    setState(() {
                      _showCaptureOverlay = false;
                    });
                  } else {
                    setState(() {
                      _formState.centerLat = reading.latitude;
                      _formState.centerLng = reading.longitude;
                      _formState.rotationDegrees = reading.heading;
                      _formState.gpsAccuracy = reading.accuracy;
                      _formState.gpsHealthScore = secResult.healthScore;
                      _detectedGpsFlags = secResult.flags;
                      _formState.confidenceScore = secResult.healthScore;
                      
                      _regenerateRotatedRectangleCorners();
                      _computePolygonMetrics();
                      
                      _gpsIsCalibrated = true;
                      _showCaptureOverlay = false;
                    });
                  }

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
        _buildSectionHeader(theme, 'GPS Capture & Spatial Alignment Methods'),
        const SizedBox(height: 8.0),
        Text(
          'Select one of the 4 spatial methods to capture and define the 4 room corners.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
        ),
        const SizedBox(height: 20.0),
        
        // Method choice selector
        _buildMethodSelector(theme, isDark),
        const SizedBox(height: 24.0),
        
        // Method content
        _buildMethodContent(theme, isDark),
      ],
    );
  }

  Widget _buildMethodSelector(ThemeData theme, bool isDark) {
    final methods = [
      {'id': LocationMethod.mapClick, 'label': 'Map Click', 'icon': Icons.map_rounded},
      {'id': LocationMethod.walkCorner, 'label': 'Walk Corners', 'icon': Icons.directions_walk_rounded},
      {'id': LocationMethod.manual, 'label': 'Manual Input', 'icon': Icons.edit_note_rounded},
      {'id': LocationMethod.coordArea, 'label': 'Center + Area', 'icon': Icons.aspect_ratio_rounded},
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.5,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: methods.map((m) {
        final isSel = _formState.locationMethod == m['id'];
        return InkWell(
          onTap: () {
            setState(() {
              _formState.locationMethod = m['id'] as String;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSel ? theme.primaryColor.withOpacity(0.1) : (isDark ? const Color(0xFF1E293B) : Colors.white),
              border: Border.all(
                color: isSel ? theme.primaryColor : (isDark ? Colors.white10 : Colors.grey.shade300),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(m['icon'] as IconData, color: isSel ? theme.primaryColor : Colors.grey, size: 20),
                const SizedBox(width: 8),
                Text(
                  m['label'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isSel ? theme.primaryColor : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMethodContent(ThemeData theme, bool isDark) {
    switch (_formState.locationMethod) {
      case LocationMethod.mapClick:
        return _buildMethod1MapClick(theme, isDark);
      case LocationMethod.walkCorner:
        return _buildMethod2WalkCorners(theme, isDark);
      case LocationMethod.manual:
        return _buildMethod3Manual(theme, isDark);
      case LocationMethod.coordArea:
        return _buildMethod4CenterArea(theme, isDark);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMethod1MapClick(ThemeData theme, bool isDark) {
    final center = _formState.centerLat != 0.0
        ? LatLng(_formState.centerLat, _formState.centerLng)
        : (_userLocationForMap ?? const LatLng(19.076, 72.877));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tap exactly 4 points on the map below in clockwise/counter-clockwise order to define the room corners.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 18.0,
                    onTap: (tapPosition, point) => _handleMapTap(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.smartcampus.erp',
                    ),
                    if (_formState.corners.length == 4)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: _formState.corners,
                            color: theme.primaryColor.withOpacity(0.2),
                            borderColor: theme.primaryColor,
                            borderStrokeWidth: 3.0,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (int i = 0; i < _formState.corners.length; i++)
                          Marker(
                            point: _formState.corners[i],
                            width: 30,
                            height: 30,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: FloatingActionButton.small(
                    onPressed: _loadUserLocation,
                    backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    child: Icon(Icons.my_location_rounded, color: theme.primaryColor),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Corners Placed: ${_formState.corners.length}/4',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _formState.corners.clear();
                  _gpsIsCalibrated = false;
                  _computePolygonMetrics();
                });
              },
              icon: const Icon(Icons.clear_rounded),
              label: const Text('Clear Clicked Corners'),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            ),
          ],
        ),
      ],
    );
  }

  void _handleMapTap(LatLng point) {
    if (_formState.corners.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('4 corners already placed. Tap "Clear Clicked Corners" to reset.')),
      );
      return;
    }
    setState(() {
      _formState.corners.add(point);
      if (_formState.corners.length == 4) {
        _computePolygonMetrics();
        _gpsIsCalibrated = true;
      }
    });
  }

  Widget _buildMethod2WalkCorners(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Walk to each corner of the room in physical order and capture. Averages 5 telemetry readings. Blocks accuracy >15m.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildFormCard(isDark, [
          for (int i = 1; i <= 4; i++) ...[
            _buildWalkCornerRow(i, theme, isDark),
            if (i < 4) const Divider(height: 24),
          ],
        ]),
      ],
    );
  }

  Widget _buildWalkCornerRow(int cornerNum, ThemeData theme, bool isDark) {
    final hasVal = _formState.corners.length >= cornerNum &&
        _formState.corners[cornerNum - 1].latitude != 0.0;
    final latLng = hasVal ? _formState.corners[cornerNum - 1] : null;
    final isCapturing = _capturingCornerIndex == cornerNum;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Corner $cornerNum',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              if (isCapturing)
                Text(
                  'Capturing: $_walkReadingsCount/5 readings...',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                )
              else if (latLng != null)
                Text(
                  'Lat: ${latLng.latitude.toStringAsFixed(6)}, Lng: ${latLng.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(color: Colors.teal, fontSize: 12),
                )
              else
                Text(
                  'Not captured yet',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: _capturingCornerIndex != null
              ? null
              : () => _captureWalkCorner(cornerNum),
          icon: isCapturing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.gps_fixed_rounded, size: 16),
          label: Text(isCapturing ? 'CAPTURING' : (hasVal ? 'RE-TAKE' : 'CAPTURE')),
          style: ElevatedButton.styleFrom(
            backgroundColor: hasVal ? Colors.teal : theme.primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Future<void> _captureWalkCorner(int cornerIndex) async {
    setState(() {
      _capturingCornerIndex = cornerIndex;
      _walkReadingsCount = 0;
      _walkPositions.clear();
    });

    try {
      for (int i = 0; i < 5; i++) {
        setState(() {
          _walkReadingsCount = i + 1;
        });

        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 5),
        );

        if (pos.accuracy > 15.0) {
          setState(() {
            _capturingCornerIndex = null;
          });
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                    SizedBox(width: 8),
                    Text('Inaccurate GPS Signal'),
                  ],
                ),
                content: Text(
                  'GPS accuracy is ±${pos.accuracy.toStringAsFixed(1)} m. '
                  'This exceeds the strict 15 m limit for virtual room certification. '
                  'Move to an open area, wait for GPS to lock, and try again.'
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
          return;
        }

        _walkPositions.add(pos);
        await Future.delayed(const Duration(seconds: 1));
      }

      double avgLat = 0.0;
      double avgLng = 0.0;
      for (var p in _walkPositions) {
        avgLat += p.latitude;
        avgLng += p.longitude;
      }
      avgLat /= 5.0;
      avgLng /= 5.0;

      final newCorner = LatLng(avgLat, avgLng);
      setState(() {
        while (_formState.corners.length < cornerIndex) {
          _formState.corners.add(const LatLng(0.0, 0.0));
        }
        _formState.corners[cornerIndex - 1] = newCorner;
        _capturingCornerIndex = null;
        
        if (_formState.corners.length == 4 && !_formState.corners.contains(const LatLng(0.0, 0.0))) {
          _computePolygonMetrics();
          _gpsIsCalibrated = true;
        }
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Corner $cornerIndex captured successfully!'),
          backgroundColor: Colors.teal,
        ),
      );
    } catch (e) {
      setState(() {
        _capturingCornerIndex = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error capturing corner: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildMethod3Manual(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Type in exact coordinates (latitude and longitude) for all 4 corners. Validates all 8 fields before applying.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildFormCard(isDark, [
          for (int i = 0; i < 4; i++) ...[
            Text(
              'Corner ${i + 1} *',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _manualCoordsControllers[i * 2],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _manualCoordsControllers[i * 2 + 1],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _applyManualCoordinates,
            icon: const Icon(Icons.check_rounded),
            label: const Text('VALIDATE & APPLY CORNERS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ]),
      ],
    );
  }

  void _applyManualCoordinates() {
    final pts = <LatLng>[];
    for (int i = 0; i < 4; i++) {
      final latText = _manualCoordsControllers[i * 2].text.trim();
      final lngText = _manualCoordsControllers[i * 2 + 1].text.trim();
      
      if (latText.isEmpty || lngText.isEmpty) {
        _showManualError('Please fill out both latitude and longitude for Corner ${i + 1}.');
        return;
      }
      final lat = double.tryParse(latText);
      final lng = double.tryParse(lngText);
      if (lat == null || lng == null) {
        _showManualError('Corner ${i + 1} coordinates must be valid numbers.');
        return;
      }
      if (lat < -90.0 || lat > 90.0) {
        _showManualError('Corner ${i + 1} latitude must be between -90 and 90.');
        return;
      }
      if (lng < -180.0 || lng > 180.0) {
        _showManualError('Corner ${i + 1} longitude must be between -180 and 180.');
        return;
      }
      if (lat == 0.0 && lng == 0.0) {
        _showManualError('Corner ${i + 1} coordinates cannot be 0,0.');
        return;
      }
      pts.add(LatLng(lat, lng));
    }

    setState(() {
      _formState.corners = pts;
      _computePolygonMetrics();
      _gpsIsCalibrated = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Manual coordinates successfully validated & applied!'),
        backgroundColor: Colors.teal,
      ),
    );
  }

  void _showManualError(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validation Error'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildMethod4CenterArea(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Specify a center point coordinate and total enclosed room area (in square meters). Generates a perfect square aligned to all 4 directions.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildFormCard(isDark, [
          TextFormField(
            controller: _method4LatController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Center Latitude *',
              prefixIcon: Icon(Icons.map_rounded),
            ),
            onChanged: (v) => _updateMethod4Square(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _method4LngController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Center Longitude *',
              prefixIcon: Icon(Icons.explore_rounded),
            ),
            onChanged: (v) => _updateMethod4Square(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _method4AreaController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Enclosed Area (sqm) *',
              prefixIcon: Icon(Icons.aspect_ratio_rounded),
            ),
            onChanged: (v) => _updateMethod4Square(),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _calibrateCenterFromGps,
            icon: const Icon(Icons.my_location_rounded),
            label: const Text('CALIBRATE CENTER FROM LIVE GPS'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ]),
      ],
    );
  }

  void _calibrateCenterFromGps() async {
    setState(() => _showCaptureOverlay = true);
  }

  void _updateMethod4Square() {
    final lat = double.tryParse(_method4LatController.text) ?? 0.0;
    final lng = double.tryParse(_method4LngController.text) ?? 0.0;
    final area = double.tryParse(_method4AreaController.text) ?? 120.0;
    
    if (lat == 0.0 || lng == 0.0 || area < 3.0 || area > 1200.0) {
      return;
    }
    
    setState(() {
      _formState.centerLat = lat;
      _formState.centerLng = lng;
      _formState.areaSqm = area;
      
      final side = math.sqrt(area);
      final hs = side / 2.0;
      
      final double latRad = lat * math.pi / 180.0;
      const double metersPerDegreeLat = 110574.0;
      final double metersPerDegreeLng = 111320.0 * math.cos(latRad);
      
      final offsets = [
        math.Point(hs, hs),   // Corner 1: NE
        math.Point(hs, -hs),  // Corner 2: SE
        math.Point(-hs, -hs), // Corner 3: SW
        math.Point(-hs, hs),  // Corner 4: NW
      ];
      
      _formState.corners = offsets.map((p) {
        final latOffset = p.y / metersPerDegreeLat;
        final lngOffset = p.x / metersPerDegreeLng;
        return LatLng(lat + latOffset, lng + lngOffset);
      }).toList();
      
      _formState.widthMeters = side;
      _formState.lengthMeters = side;
      _formState.rotationDegrees = 0.0;
      
      _computePolygonMetrics();
      _gpsIsCalibrated = true;
    });
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
          centerLat: _formState.centerLat,
          centerLng: _formState.centerLng,
          widthMeters: _formState.widthMeters,
          lengthMeters: _formState.lengthMeters,
          rotationDegrees: _formState.rotationDegrees,
          confidenceScore: _formState.confidenceScore,
          roomPolygonPoints: _formState.corners,
          onGeometryChanged: (newLat, newLng, newWidth, newLength, newRotation) {
            setState(() {
              _formState.centerLat = newLat;
              _formState.centerLng = newLng;
              _formState.widthMeters = newWidth.clamp(kMinRoomSize, kMaxRoomSize);
              _formState.lengthMeters = newLength.clamp(kMinRoomSize, kMaxRoomSize);
              _formState.rotationDegrees = newRotation;
              _regenerateRotatedRectangleCorners();
              _computePolygonMetrics();
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
                  value: _formState.widthMeters.clamp(kMinRoomSize, kMaxRoomSize),
                  min: kMinRoomSize,
                  max: kMaxRoomSize,
                  divisions: 97,
                  onChanged: (val) {
                    setState(() {
                      _formState.widthMeters = val.clamp(kMinRoomSize, kMaxRoomSize);
                      _regenerateRotatedRectangleCorners();
                      _computePolygonMetrics();
                    });
                  },
                ),
              ),
              Text('${_formState.widthMeters.toStringAsFixed(1)}m'),
            ],
          ),

          // Length tune slider
          Row(
            children: [
              const SizedBox(width: 70, child: Text('Length (m)')),
              Expanded(
                child: Slider(
                  value: _formState.lengthMeters.clamp(kMinRoomSize, kMaxRoomSize),
                  min: kMinRoomSize,
                  max: kMaxRoomSize,
                  divisions: 97,
                  onChanged: (val) {
                    setState(() {
                      _formState.lengthMeters = val.clamp(kMinRoomSize, kMaxRoomSize);
                      _regenerateRotatedRectangleCorners();
                      _computePolygonMetrics();
                    });
                  },
                ),
              ),
              Text('${_formState.lengthMeters.toStringAsFixed(1)}m'),
            ],
          ),

          // Yaw / orientation tuning
          Row(
            children: [
              const SizedBox(width: 70, child: Text('Yaw (deg)')),
              Expanded(
                child: Slider(
                  value: _formState.rotationDegrees.clamp(0.0, 360.0),
                  min: 0.0,
                  max: 360.0,
                  onChanged: (val) {
                    setState(() {
                      _formState.rotationDegrees = val.clamp(0.0, 360.0);
                      _regenerateRotatedRectangleCorners();
                      _computePolygonMetrics();
                    });
                  },
                ),
              ),
              Text('${_formState.rotationDegrees.toStringAsFixed(0)}°'),
            ],
          ),
          const SizedBox(height: 16.0),

          // Live readout below sliders
          Center(
            child: Text(
              'Width: ${_formState.widthMeters.toStringAsFixed(1)} m   '
              'Length: ${_formState.lengthMeters.toStringAsFixed(1)} m   '
              'Area: ${_formState.areaSqm.toStringAsFixed(1)} m²',
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
            _formState.gpsAccuracy <= 35.0 || _formState.locationMethod == 'manual',
            'GPS Accuracy: ±${_formState.gpsAccuracy.toStringAsFixed(1)}m (Required: <= 35.0m)',
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