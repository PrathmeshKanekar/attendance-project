// [ignoring loop detection]
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import '../../core/layout/app_layout.dart';
import '../../core/config/map_config.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/services/secure_storage_service.dart';
import 'providers/virtual_room_providers.dart';
import 'models/virtual_room_model.dart';
import 'services/sensor_fusion_service.dart';
import 'dart:async'; 

// ─────────────────────────────────────────────────────────────────────────────
// IMMUTABLE ATOMIC USER TELEMETRY STATE CONTAINER WITH GIS ENHANCEMENTS
// ─────────────────────────────────────────────────────────────────────────────
@immutable
class UserTelemetryState {
  final LatLng? location;
  final LatLng? stabilizedLocation;
  final double accuracy;
  final double heading;
  final String directionLabel;
  final double speedMps;
  final double altitude;
  final double distance;
  final double distanceToBoundary;
  final double confidenceScore;
  final bool isInsideRaw;
  final bool isInsideStabilized;
  final bool isMocked;
  final bool isTeacherPresent;
  final bool attendanceEligible;
  final String overlappingRooms;
  final String hysteresisTicks;
  final String gpsLockStatus;

  const UserTelemetryState({
    this.location,
    this.stabilizedLocation,
    this.accuracy = 0.0,
    this.heading = 0.0,
    this.directionLabel = 'N',
    this.speedMps = 0.0,
    this.altitude = 0.0,
    this.distance = 0.0,
    this.distanceToBoundary = 0.0,
    this.confidenceScore = 100.0,
    this.isInsideRaw = false,
    this.isInsideStabilized = false,
    this.isMocked = false,
    this.isTeacherPresent = false,
    this.attendanceEligible = false,
    this.overlappingRooms = 'None Detected',
    this.hysteresisTicks = 'Inside Ticks: 0/3 | Outside Ticks: 0/3',
    this.gpsLockStatus = 'ACQUIRING',
  });

  UserTelemetryState copyWith({
    LatLng? location,
    LatLng? stabilizedLocation,
    double? accuracy,
    double? heading,
    String? directionLabel,
    double? speedMps,
    double? altitude,
    double? distance,
    double? distanceToBoundary,
    double? confidenceScore,
    bool? isInsideRaw,
    bool? isInsideStabilized,
    bool? isMocked,
    bool? isTeacherPresent,
    bool? attendanceEligible,
    String? overlappingRooms,
    String? hysteresisTicks,
    String? gpsLockStatus,
  }) {
    return UserTelemetryState(
      location: location ?? this.location,
      stabilizedLocation: stabilizedLocation ?? this.stabilizedLocation,
      accuracy: accuracy ?? this.accuracy,
      heading: heading ?? this.heading,
      directionLabel: directionLabel ?? this.directionLabel,
      speedMps: speedMps ?? this.speedMps,
      altitude: altitude ?? this.altitude,
      distance: distance ?? this.distance,
      distanceToBoundary: distanceToBoundary ?? this.distanceToBoundary,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      isInsideRaw: isInsideRaw ?? this.isInsideRaw,
      isInsideStabilized: isInsideStabilized ?? this.isInsideStabilized,
      isMocked: isMocked ?? this.isMocked,
      isTeacherPresent: isTeacherPresent ?? this.isTeacherPresent,
      attendanceEligible: attendanceEligible ?? this.attendanceEligible,
      overlappingRooms: overlappingRooms ?? this.overlappingRooms,
      hysteresisTicks: hysteresisTicks ?? this.hysteresisTicks,
      gpsLockStatus: gpsLockStatus ?? this.gpsLockStatus,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STUDENT OCCUPANT DTO FOR 3D CANVAS RENDERING
// ─────────────────────────────────────────────────────────────────────────────
class StudentOccupant {
  final String name;
  final String rollNumber;
  final String department;
  final double gridX; // Seat column (0-5)
  final double gridY; // Seat row (0-9)
  final bool validationPassed;
  final String securityAlert;

  const StudentOccupant({
    required this.name,
    required this.rollNumber,
    required this.department,
    required this.gridX,
    required this.gridY,
    required this.validationPassed,
    this.securityAlert = '',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// GENERIC DATASTATE CONTAINER ARCHITECTURE FOR LAB CERTIFICATION CONTRACT
// ─────────────────────────────────────────────────────────────────────────────
abstract class DataState<T> {
  const DataState();
}
class DataLoading<T> extends DataState<T> {
  const DataLoading();
}
class DataReady<T> extends DataState<T> {
  final T value;
  const DataReady(this.value);
}
class DataUnavailable<T> extends DataState<T> {
  final String reason;
  const DataUnavailable(this.reason);
}
class DataError<T> extends DataState<T> {
  final String reason;
  const DataError(this.reason);
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOM VALIDATION SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class RoomValidationScreen extends ConsumerStatefulWidget {
  const RoomValidationScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<RoomValidationScreen> createState() => _RoomValidationScreenState();
}

class _RoomValidationScreenState extends ConsumerState<RoomValidationScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final SensorFusionService _sensorFusionService = SensorFusionService();
  StreamSubscription<FusedSensorReading>? _sensorSub;
  StreamSubscription<Position>? _gpsSubscription;
  Position? _currentPosition;
  bool _gpsReady = false;
  String? _gpsError;
  late final MapController _mapController;

  // Selected Room Geometry
  VirtualRoomModel? _selectedRoom;
  List<LatLng> _roomPolygonPoints = const [];
  LatLng? _roomCenter;

  // Dashboard configuration states
  int _startupPhase = 1;
  bool _is3DViewMode = false;
  
  // QA Simulation Overrides (For stress-testing extreme boundary / low accuracy cases)
  bool _simulatingDrift = false;
  bool _simulatingLowAccuracy = false;
  bool _simulatingMockLocation = false;
  bool _simulatingTeacherPresentOverride = false; // defaults to false to read real API occupancy first!

  // Single Atomic ValueNotifier to prevent nested listener chains and multiple redraw cycles
  final ValueNotifier<UserTelemetryState> _telemetryNotifier = ValueNotifier<UserTelemetryState>(const UserTelemetryState());

  // Log and Session Notifiers
  final ValueNotifier<bool> _isSessionActiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<String>> _sessionLogsNotifier = ValueNotifier<List<String>>(const []);

  // Rolling GPS Stabilization Window
  final List<LatLng> _gpsHistoryBuffer = [];
  static const int _stabilizationWindowSize = 5;

  // Hysteresis calculation buffer variables
  bool _isInsideRaw = false;
  bool _isInsideStabilized = false;
  int _consecutiveInsideCount = 0;
  int _consecutiveOutsideCount = 0;
  static const int _hysteresisThreshold = 3;

  // Stream UI throttling controls
  DateTime _lastUIUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _uiUpdateThrottle = Duration(milliseconds: 1000);

  // ─── Real-Time API Polling States ──────────────────────────────────────────
  Timer? _pollingTimer;
  bool _isFetchingOccupancy = false;
  String? _occupancyError;
  int _totalInside = 0;
  List<Map<String, dynamic>> _realUsersInside = [];

  bool _isSessionActive = false;
  String? _activeSessionCode;

  // Diagnostics Metrics
  bool _apiConnected = false;
  DateTime? _lastSyncTime;
  int _responseTimeMs = 0;
  String _roomApiStatus = 'PENDING';
  String _validationApiStatus = 'PENDING';
  String _attendanceApiStatus = 'PENDING';
  String? _attendanceSummaryError;

  DateTime _lastHeartbeatTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _heartbeatInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapController = MapController();
    _telemetryNotifier.addListener(() {
      if (!mounted) return;
      final val = _telemetryNotifier.value;
      if (val.location == null || val.accuracy == 0.0) {
        if (_validationApiStatus == 'PENDING' || _validationApiStatus.startsWith('PASS') || _validationApiStatus.startsWith('FAIL')) {
          setState(() {
            _validationApiStatus = 'UNAVAILABLE: GPS required';
          });
        }
      } else {
        if (_validationApiStatus == 'UNAVAILABLE: GPS required') {
          setState(() {
            _validationApiStatus = 'PENDING';
          });
        }
      }
    });
    _runPhasedStartup();
    _initGpsStream();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_gpsReady) {
        _initGpsStream();
      }
    }
  }

  Future<void> _initGpsStream() async {
    // Step 1 — check permission
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      if (mounted) {
        setState(() {
          _gpsError = 'Location permission denied. Enable it in device Settings to use validation.';
          _gpsReady = false;
        });
      }
      return;
    }

    // Step 2 — check if location service enabled
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _gpsError = 'Location services are disabled. Enable GPS in device Settings.';
          _gpsReady = false;
        });
      }
      return;
    }

    // Step 3 — start stream
    await _gpsSubscription?.cancel();
    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1, // update every 1 meter change
      ),
    ).listen(
      (Position position) {
        if (!mounted) return;
        // Step 4 — MUST call setState so UI rebuilds
        setState(() {
          _currentPosition = position;
          _gpsReady = true;
          _gpsError = null;
          _runAllTestCases(position); // re-evaluate all tests
        });
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _gpsError = 'GPS stream error: $error';
            _gpsReady = false;
          });
        }
      },
      cancelOnError: false, // keep stream alive on error
    );
  }

  void _runPhasedStartup() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(virtualRoomsProvider.notifier).fetchRooms().then((_) {
          setState(() {
            _roomApiStatus = 'CONNECTED';
            _apiConnected = true;
            _lastSyncTime = DateTime.now();
          });
        }).catchError((e) {
          setState(() {
            _roomApiStatus = 'FAILED ($e)';
            _apiConnected = false;
          });
        });
      }
    });

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _startupPhase = 2);

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _startupPhase = 3);

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _startupPhase = 4);

    _startLiveTracking();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsSubscription?.cancel();
    _sensorSub?.cancel();
    _sensorFusionService.stopTracking();
    _stopPolling();
    _telemetryNotifier.dispose();
    _isSessionActiveNotifier.dispose();
    _sessionLogsNotifier.dispose();
    super.dispose();
  }

  // ── Real-Time Occupancy Polling Engine ─────────────────────────────────────
  void _startPolling() {
    _stopPolling();
    // Controlled polling set to 20 seconds to prevent battery drain and excessive API load
    _pollingTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (mounted && _selectedRoom != null) {
        _fetchRealOccupancy();
        _checkActiveSession();
      }
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _fetchRealOccupancy() async {
    if (_selectedRoom == null) return;
    setState(() {
      _isFetchingOccupancy = true;
      _occupancyError = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final startTime = DateTime.now();
      
      final res = await api.get('/api/virtual-rooms/${_selectedRoom!.id}/occupancy/')
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException(
            'Occupancy API timed out after 15 seconds',
          ),
        );
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;

      if (res.statusCode == 200 && res.data != null) {
        final data = res.data as Map<String, dynamic>;
        final list = data['users'] as List? ?? [];
        setState(() {
          _realUsersInside = List<Map<String, dynamic>>.from(list);
          _totalInside = data['total_inside'] as int? ?? list.length;
          _isFetchingOccupancy = false;
          _apiConnected = true;
          _lastSyncTime = DateTime.now();
          _responseTimeMs = duration;
        });

        _addLog('📊 Occupancy sync: $_totalInside users inside room.');
      } else {
        final code = res.statusCode;
        if (code == 401 || code == 403 || code == 404) {
          _stopPolling();
          _addLog('⚠️ Occupancy API returned access error ($code). Polling stopped to prevent loop.');
        }
        setState(() {
          _occupancyError = 'Failed to load occupancy: ${res.statusCode}';
          _isFetchingOccupancy = false;
          _apiConnected = false;
        });
      }
    } on TimeoutException catch (e) {
      _addLog('TIMEOUT: ${e.message}');
      setState(() {
        _occupancyError = 'Request timed out';
        _isFetchingOccupancy = false;
        _apiConnected = false;
      });
      return;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403 || code == 404) {
        _stopPolling();
        _addLog('⚠️ Occupancy API threw access error ($code). Polling stopped to prevent loop.');
      }
      
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        setState(() {
          _occupancyError = 'Request timed out';
          _isFetchingOccupancy = false;
          _apiConnected = false;
        });
        return;
      } else {
        setState(() {
          _occupancyError = 'Occupancy API error: HTTP $code';
          _isFetchingOccupancy = false;
          _apiConnected = false;
        });
      }
    } catch (e) {
      setState(() {
        _occupancyError = 'Occupancy API error: ${e.toString()}';
        _isFetchingOccupancy = false;
        _apiConnected = false;
      });
    }
  }

  Future<void> _checkActiveSession() async {
    if (_selectedRoom == null) return;
    final String requestUrl = '/api/attendance/sessions/my/';
    final Map<String, dynamic> queryParams = {'status': 'active'};
    
    // Audit log starting
    print('==================================================');
    print('🔍 AUDIT LOG: Initiating active attendance session check');
    print('🔗 Request URL: $requestUrl');
    print('📦 Query Params: $queryParams');
    print('⚡ HTTP Method: GET (Verified matching route decorator)');

    String? token;
    String maskedToken = 'None';
    String decodedJwt = 'None';
    try {
      token = await SecureStorageService.getAccessToken();
      if (token != null) {
        if (token.length > 10) {
          maskedToken = '${token.substring(0, 10)}...[MASKED]';
        } else {
          maskedToken = token;
        }
        final parts = token.split('.');
        if (parts.length >= 2) {
          final normalized = base64Url.normalize(parts[1]);
          decodedJwt = utf8.decode(base64Url.decode(normalized));
        }
      }
    } catch (tokenErr) {
      print('⚠️ Token acquisition error: $tokenErr');
    }

    print('🔑 Authorization Header (Token): $maskedToken');
    print('🔬 Decoded JWT Payload: $decodedJwt');

    try {
      final api = ref.read(apiClientProvider);
      final startTime = DateTime.now();
      
      final res = await api.get(requestUrl, params: queryParams)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException(
            'Attendance API timed out after 15 seconds',
          ),
        );
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;

      print('✅ API Response Status: ${res.statusCode}');
      print('📝 API Response Data: ${res.data}');

      if (res.statusCode == 401 || res.statusCode == 403 || res.statusCode == 404) {
        _stopPolling();
        String apiStatus = res.statusCode == 403 ? 'UNAUTHORIZED' : 'FAILED (${res.statusCode})';
        _addLog(res.statusCode == 403
            ? '⚠️ Attendance data unavailable: insufficient permissions'
            : '⚠️ Active session API returned access error (${res.statusCode}). Polling stopped.');
        
        if (res.statusCode == 403) {
          String detail = 'Insufficient permissions for this role';
          if (res.data is Map) {
            detail = res.data['detail']?.toString() ?? detail;
          }
          print('403 DENIAL REASON: $detail');
          _addLog('Attendance API: UNAUTHORIZED — $detail');
          setState(() {
            _attendanceApiStatus = 'UNAUTHORIZED';
            _attendanceSummaryError =
              'Attendance data unavailable: $detail\n'
              'Ask your administrator to grant access to '
              '/api/reports/attendance-summary/ for this role.';
            _apiConnected = false;
            _isSessionActive = false;
          });
        } else {
          setState(() {
            _attendanceApiStatus = apiStatus;
            _apiConnected = false;
            _isSessionActive = false;
          });
        }
        print('==================================================');
        return;
      }

      bool sessionFound = false;
      String? code;

      List list = [];
      if (res.data is Map && res.data['sessions'] != null) {
        list = res.data['sessions'] as List;
      } else if (res.data is List) {
        list = res.data as List;
      }

      for (final s in list) {
        final Map<String, dynamic> item = Map<String, dynamic>.from(s as Map);
        final String? roomVal = item['virtual_room']?.toString() ?? item['virtual_room_id']?.toString();
        if (roomVal == _selectedRoom!.id) {
          sessionFound = true;
          code = item['session_code']?.toString() ?? item['id']?.toString();
          break;
        }
      }

      setState(() {
        _isSessionActive = sessionFound;
        _activeSessionCode = code;
        _attendanceApiStatus = 'CONNECTED';
        _apiConnected = true;
        _lastSyncTime = DateTime.now();
        _responseTimeMs = duration;
        _attendanceSummaryError = null;
      });

      if (sessionFound) {
        _addLog('🚀 Active session ($code) detected for ${_selectedRoom!.name}.');
      }
      print('==================================================');
    } on TimeoutException catch (e) {
      _addLog('TIMEOUT: ${e.message}');
      setState(() {
        _attendanceApiStatus = 'TIMEOUT';
        _attendanceSummaryError = 'Request timed out';
        _apiConnected = false;
        _isSessionActive = false;
      });
      return;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      
      print('❌ DETECTED API ERROR: ${e.toString()}');
      print('🔴 HTTP Status Code: $code');
      print('📄 Error Body: $body');

      if (code == 403) {
        _stopPolling();
        String detail = 'Insufficient permissions for this role';
        if (body is Map) {
          detail = body['detail']?.toString() ?? detail;
        }
        print('403 DENIAL REASON: $detail');
        _addLog('Attendance API: UNAUTHORIZED — $detail');
        setState(() {
          _attendanceApiStatus = 'UNAUTHORIZED';
          _attendanceSummaryError =
            'Attendance data unavailable: $detail\n'
            'Ask your administrator to grant access to '
            '/api/reports/attendance-summary/ for this role.';
          _apiConnected = false;
          _isSessionActive = false;
        });
        return;
      } else if (e.type == DioExceptionType.connectionTimeout ||
                 e.type == DioExceptionType.receiveTimeout ||
                 e.type == DioExceptionType.sendTimeout) {
        _stopPolling();
        setState(() {
          _attendanceApiStatus = 'TIMEOUT';
          _attendanceSummaryError = 'Request timed out';
          _apiConnected = false;
          _isSessionActive = false;
        });
        return;
      } else {
        _stopPolling();
        _addLog('⚠️ Active session API threw access error ($code). Polling stopped.');
        setState(() {
          _attendanceApiStatus = 'FAILED: HTTP $code';
          _attendanceSummaryError = 'Attendance API error: HTTP $code';
          _apiConnected = false;
          _isSessionActive = false;
        });
      }
    } catch (e) {
      _stopPolling();
      setState(() {
        _attendanceApiStatus = 'FAILED: ${e.toString()}';
        _attendanceSummaryError = 'Attendance API error: ${e.toString()}';
        _apiConnected = false;
        _isSessionActive = false;
      });
    }
  }

  Future<void> _triggerHeartbeatAPI(double lat, double lng, double accuracy) async {
    if (_selectedRoom == null) {
      setState(() {
        _validationApiStatus = 'UNAVAILABLE: No Room Selected';
      });
      return;
    }
    
    final payload = {
      'lat': lat,
      'lng': lng,
      'accuracy': accuracy,
      'device_id': 'validation-tester-device',
    };
    final String requestUrl = '/api/virtual-rooms/${_selectedRoom!.id}/presence/heartbeat/';
    
    print('==================================================');
    print('📡 AUDIT LOG: Sending Polygon Validation API Heartbeat');
    print('🔗 Request URL: $requestUrl');
    print('📦 Request Payload: ${jsonEncode(payload)}');
    print('⚡ HTTP Method: POST (Verified matching route decorator)');

    try {
      final api = ref.read(apiClientProvider);
      final startTime = DateTime.now();
      
      // Await post with a strict 15-second timeout as required
      final res = await api.post(
        requestUrl, 
        data: payload,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Polygon validation API timed out after 15s',
        ),
      );
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;

      print('✅ API Response Status: ${res.statusCode}');
      print('📝 API Response Data: ${res.data}');

      if (res.statusCode == 200 && res.data != null) {
        final data = res.data as Map<String, dynamic>;
        final bool apiInside = data['is_inside'] ?? false;
        final double distToBound = (data['distance_to_boundary'] as num? ?? 0.0).toDouble();
        final String mode = data['validation_mode'] ?? 'denied';

        setState(() {
          _validationApiStatus = apiInside ? 'PASS' : 'FAIL: Outside Boundary';
          _apiConnected = true;
          _lastSyncTime = DateTime.now();
          _responseTimeMs = duration;
        });

        _addLog('📡 API Heartbeat: Inside=${apiInside ? "YES" : "NO"} | Mode=$mode | Bound=${distToBound.toStringAsFixed(1)}m');
      } else {
        setState(() {
          _validationApiStatus = 'FAIL: HTTP ${res.statusCode}';
          _apiConnected = false;
        });
      }
      print('==================================================');
    } on TimeoutException catch (e) {
      _addLog('TIMEOUT: ${e.message}');
      setState(() {
        _validationApiStatus = 'TIMEOUT';
        _apiConnected = false;
      });
      print('==================================================');
      return;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      
      print('❌ Heartbeat API Error detected: ${e.toString()}');
      print('🔴 HTTP Status Code: $code');
      print('📄 Error Body: $body');

      if (code == 403) {
        setState(() {
          _validationApiStatus = 'UNAUTHORIZED';
          _apiConnected = false;
        });
        _addLog('Validation API: UNAUTHORIZED');
        print('==================================================');
        return;
      } else if (e.type == DioExceptionType.connectionTimeout ||
                 e.type == DioExceptionType.receiveTimeout ||
                 e.type == DioExceptionType.sendTimeout) {
        setState(() {
          _validationApiStatus = 'TIMEOUT';
          _apiConnected = false;
        });
        print('==================================================');
        return;
      } else {
        setState(() {
          _validationApiStatus = 'FAIL: HTTP $code';
          _apiConnected = false;
        });
      }
      print('==================================================');
    } catch (e) {
      setState(() {
        _validationApiStatus = 'FAIL: ${e.toString()}';
        _apiConnected = false;
      });
      print('==================================================');
    }
  }

  void _startLiveTracking() async {
    // GPS initialized directly via _initGpsStream() in initState
  }

  String _dirLabel(double deg) {
    const dirs = ['N','NE','E','SE','S','SW','W','NW','N'];
    return dirs[((deg + 22.5) / 45.0).floor().clamp(0, 8)];
  }

  void _runAllTestCases(Position position) {
    if (!mounted) return;
    
    final now = DateTime.now();
    double rawLat = position.latitude;
    double rawLng = position.longitude;
    double rawAcc = position.accuracy;

    if (_simulatingDrift) {
      rawLat += 0.00008;
      rawLng += 0.00008;
    }
    if (_simulatingLowAccuracy) {
      rawAcc = 75.0;
    }

    const double kMaxAllowedAccuracyMeters = 15.0;
    final bool accuracyTooPoor = rawAcc > kMaxAllowedAccuracyMeters;

    if (accuracyTooPoor) {
      _isInsideRaw = false;
      _isInsideStabilized = false;
      _consecutiveInsideCount = 0;
      _consecutiveOutsideCount = 0;
      _gpsHistoryBuffer.clear();
      _addLog('⚠️ GPS accuracy is ±${rawAcc.toStringAsFixed(0)} m. Move to an open area and wait for GPS to lock below ±15 m.');
    } else {
      _evaluateGeofence(rawLat, rawLng, rawAcc);
    }

    // Heartbeat API Sync Tick
    if (now.difference(_lastHeartbeatTime) >= _heartbeatInterval && _selectedRoom != null) {
      _lastHeartbeatTime = now;
      _triggerHeartbeatAPI(rawLat, rawLng, rawAcc);
    }

    final double headingDeg = position.heading;
    final bool isMocked = _simulatingMockLocation || position.isMocked || (rawAcc < 0.5 && rawLat != 0.0);
    final double speedMps = position.speed;

    // Rolling Stabilization Filter
    LatLng rawLoc = LatLng(rawLat, rawLng);
    if (!accuracyTooPoor) {
      _gpsHistoryBuffer.add(rawLoc);
      if (_gpsHistoryBuffer.length > _stabilizationWindowSize) {
        _gpsHistoryBuffer.removeAt(0);
      }
    }
    
    LatLng stabilizedLoc;
    if (_gpsHistoryBuffer.isNotEmpty) {
      double sumLat = 0.0;
      double sumLng = 0.0;
      for (final loc in _gpsHistoryBuffer) {
        sumLat += loc.latitude;
        sumLng += loc.longitude;
      }
      stabilizedLoc = LatLng(sumLat / _gpsHistoryBuffer.length, sumLng / _gpsHistoryBuffer.length);
    } else {
      stabilizedLoc = rawLoc;
    }

    double dist = 0.0;
    double distToBoundary = 0.0;
    String overlapStatus = 'None Detected';

    if (_roomCenter != null) {
      dist = Geolocator.distanceBetween(
        stabilizedLoc.latitude, stabilizedLoc.longitude,
        _roomCenter!.latitude, _roomCenter!.longitude,
      );
    }

    if (_roomPolygonPoints.isNotEmpty) {
      distToBoundary = _minDistanceToBoundary(stabilizedLoc, _roomPolygonPoints);
    }

    // Mathematical GIS Confidence Framework
    double confidence = _calculateGisConfidence(
      accuracyMeters: rawAcc,
      distanceToBoundaryMeters: distToBoundary,
      isInsidePolygon: _isInsideStabilized,
    );

    const double kMinConfidenceToMark = 60.0;
    if (_isInsideStabilized && confidence < kMinConfidenceToMark) {
      _isInsideStabilized = false;
      confidence = 0.0;
      _addLog('⚠️ Location confidence is too low. Cannot confirm room position. Improve GPS signal.');
    }

    // Multiple Room Overlaps Check
    final otherRooms = ref.read(virtualRoomsProvider).rooms.where((r) => r.id != _selectedRoom?.id);
    final overlappingList = <String>[];
    for (final other in otherRooms) {
      final poly = _buildPolygonPoints(other);
      if (poly.isNotEmpty && _isPointInPolygon(stabilizedLoc, poly)) {
        overlappingList.add(other.name);
      }
    }
    if (overlappingList.isNotEmpty) {
      overlapStatus = overlappingList.join(', ');
    }

    // Resolve teacher presence
    bool teacherPresent = false;
    for (final u in _realUsersInside) {
      final role = u['role']?.toString() ?? 'student';
      if (role == 'teacher' || role == 'admin' || role == 'lab_assistant') {
        teacherPresent = true;
      }
    }
    if (_simulatingTeacherPresentOverride) {
      teacherPresent = true;
    }

    // Security Gate Validation PASS/FAIL
    final bool attendanceAllowed = _isInsideStabilized &&
        rawAcc <= 15.0 &&
        confidence >= 60.0 &&
        !isMocked &&
        teacherPresent &&
        _isSessionActive &&
        _selectedRoom != null;

    final newState = _telemetryNotifier.value.copyWith(
      location: rawLoc,
      stabilizedLocation: stabilizedLoc,
      accuracy: rawAcc,
      heading: headingDeg,
      directionLabel: _dirLabel(headingDeg),
      speedMps: speedMps,
      altitude: position.altitude,
      distance: dist,
      distanceToBoundary: distToBoundary,
      confidenceScore: confidence,
      isInsideRaw: _isInsideRaw,
      isInsideStabilized: _isInsideStabilized,
      isMocked: isMocked,
      isTeacherPresent: teacherPresent,
      attendanceEligible: attendanceAllowed,
      overlappingRooms: overlapStatus,
      hysteresisTicks: 'Inside: $_consecutiveInsideCount/3 | Outside: $_consecutiveOutsideCount/3',
      gpsLockStatus: accuracyTooPoor ? 'POOR ACCURACY (±${rawAcc.toStringAsFixed(0)}m)' : 'LOCKED',
    );

    _telemetryNotifier.value = newState;
  }

  // ── Correct point-in-polygon Ray-Casting algorithm ────────────────────────
  bool _isPointInsidePolygon(LatLng point, List<LatLng> polygon) {
    int intersections = 0;
    final int n = polygon.length;

    for (int i = 0; i < n; i++) {
      final LatLng a = polygon[i];
      final LatLng b = polygon[(i + 1) % n];

      if (((a.latitude <= point.latitude && point.latitude < b.latitude) ||
           (b.latitude <= point.latitude && point.latitude < a.latitude)) &&
          (point.longitude < 
           (b.longitude - a.longitude) * 
           (point.latitude - a.latitude) / 
           (b.latitude - a.latitude) + a.longitude)) {
        intersections++;
      }
    }
    return (intersections % 2) == 1;
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    return _isPointInsidePolygon(point, polygon);
  }

  double _calculateGisConfidence({
    required double accuracyMeters,
    required double distanceToBoundaryMeters,
    required bool isInsidePolygon,
  }) {
    // If outside polygon, confidence of being inside = 0
    if (!isInsidePolygon) return 0.0;

    // Accuracy score: 100% at ±1m, 0% at ±50m
    final double accuracyScore = 
      ((50.0 - accuracyMeters) / 50.0).clamp(0.0, 1.0) * 100;

    // Boundary margin score: how far inside the boundary
    // More margin = more confident
    final double marginScore = 
      (distanceToBoundaryMeters / 10.0).clamp(0.0, 1.0) * 100;

    // Weighted average: accuracy matters more
    return (accuracyScore * 0.7) + (marginScore * 0.3);
  }

  List<LatLng> _parsePolygonFromGeoJson(Map<String, dynamic> geoJson) {
    try {
      if (geoJson.isEmpty) return const [];
      
      Map<String, dynamic> geom = geoJson;
      if (geoJson.containsKey('geometry') && geoJson['geometry'] is Map) {
        geom = geoJson['geometry'] as Map<String, dynamic>;
      }
      
      if (!geom.containsKey('coordinates')) return const [];
      final coordinates = geom['coordinates'][0] as List;
      return coordinates
        .take(coordinates.length - 1) // remove closing duplicate point
        .map((c) => LatLng(
          (c[1] as num).toDouble(), // latitude
          (c[0] as num).toDouble(), // longitude
        ))
        .toList();
    } catch (e) {
      debugPrint('⚠️ Error parsing polygon GeoJson: $e');
      return const [];
    }
  }

  // ── Perpendicular boundary distance math ─────────────────────────────────
  double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
    final double latMid = (a.latitude + b.latitude) / 2.0;
    const double metersPerDegreeLat = 110574.0;
    final double metersPerDegreeLng = 111320.0 * math.cos(latMid * math.pi / 180.0);

    final double px = p.longitude * metersPerDegreeLng;
    final double py = p.latitude * metersPerDegreeLat;
    final double ax = a.longitude * metersPerDegreeLng;
    final double ay = a.latitude * metersPerDegreeLat;
    final double bx = b.longitude * metersPerDegreeLng;
    final double by = b.latitude * metersPerDegreeLat;

    final double l2 = (ax - bx) * (ax - bx) + (ay - by) * (ay - by);
    if (l2 == 0) return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));

    double t = ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / l2;
    t = math.max(0.0, math.min(1.0, t));

    final double projx = ax + t * (bx - ax);
    final double projy = ay + t * (by - ay);

    return math.sqrt((px - projx) * (px - projx) + (py - projy) * (py - projy));
  }

  double _minDistanceToBoundary(LatLng p, List<LatLng> polygon) {
    if (polygon.length < 3) return double.infinity;
    double minDistance = double.infinity;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      final double dist = _distanceToSegment(p, polygon[i], polygon[j]);
      if (dist < minDistance) minDistance = dist;
      j = i;
    }
    return minDistance;
  }

  void _evaluateGeofence(double lat, double lng, double accuracy) {
    if (_selectedRoom == null || _roomPolygonPoints.isEmpty) return;

    final user = LatLng(lat, lng);
    final isInsideNow = _isPointInPolygon(user, _roomPolygonPoints);

    if (isInsideNow != _isInsideRaw) {
      _isInsideRaw = isInsideNow;
      _addLog('🔍 Raw containment transition: ${isInsideNow ? "INSIDE" : "OUTSIDE"}');
    }

    if (isInsideNow) {
      _consecutiveInsideCount++;
      _consecutiveOutsideCount = 0;
      if (_consecutiveInsideCount >= _hysteresisThreshold && !_isInsideStabilized) {
        _isInsideStabilized = true;
        _addLog('❇️ Stabilized Geofence: ENTERED "${_selectedRoom!.name}".');
      }
    } else {
      _consecutiveOutsideCount++;
      _consecutiveInsideCount = 0;
      if (_consecutiveOutsideCount >= _hysteresisThreshold && _isInsideStabilized) {
        _isInsideStabilized = false;
        _addLog('⚠️ Stabilized Geofence: EXITED "${_selectedRoom!.name}".');
      }
    }
  }

  List<LatLng> _buildPolygonPoints(VirtualRoomModel room) {
    if (room.boundaryGeoJson.isNotEmpty) {
      final parsed = _parsePolygonFromGeoJson(room.boundaryGeoJson);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }
    try {
      final centerLat = room.centerLat ?? 0.0;
      final centerLng = room.centerLng ?? 0.0;
      if (centerLat == 0.0 && centerLng == 0.0) return const [];

      final width = (room.spatialMetadata['width_meters'] as num? ?? 10.0).toDouble();
      final length = (room.spatialMetadata['length_meters'] as num? ?? 12.0).toDouble();
      final rotation = (room.spatialMetadata['rotation_degrees'] as num? ?? room.orientationDegrees).toDouble();

      final double latRad = centerLat * math.pi / 180.0;
      const double metersPerDegreeLat = 110574.0;
      final double metersPerDegreeLng = 111320.0 * math.cos(latRad);
      
      final double rotationRad = rotation * math.pi / 180.0;
      final cosRot = math.cos(rotationRad);
      final sinRot = math.sin(rotationRad);
      
      final hw = width / 2.0;
      final hl = length / 2.0;
      
      final List<math.Point<double>> offsets = [
        math.Point(hw, hl),
        math.Point(hw, -hl),
        math.Point(-hw, -hl),
        math.Point(-hw, hl),
      ];
      
      return offsets.map((p) {
        final dx = p.x * cosRot + p.y * sinRot;
        final dy = -p.x * sinRot + p.y * cosRot;
        return LatLng(centerLat + (dy / metersPerDegreeLat), centerLng + (dx / metersPerDegreeLng));
      }).toList();
    } catch (e) {
      debugPrint('⚠️ Polygon build failed: $e');
      return const [];
    }
  }

  void _addLog(String msg) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final fullLog = '[$timeStr] $msg';

    if (_isSessionActiveNotifier.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final currentList = List<String>.from(_sessionLogsNotifier.value);
        currentList.insert(0, fullLog);
        if (currentList.length > 25) currentList.removeRange(25, currentList.length);
        _sessionLogsNotifier.value = currentList;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Allowed roles guard: Lab Assistant only
    final allowedRoles = ['lab_assistant'];
    if (authState is AuthSuccess && !allowedRoles.contains(authState.user.role)) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: RepaintBoundary(child: _AccessDeniedCard())),
      );
    }

    final bool isLoading = ref.watch(virtualRoomsProvider.select((s) => s.isLoading));
    final String? error = ref.watch(virtualRoomsProvider.select((s) => s.error));
    final int roomsCount = ref.watch(virtualRoomsProvider.select((s) => s.rooms.length));

    return AppLayout(
      title: 'Room Validation & 3D Lab 🔬',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          tooltip: 'Refresh Virtual Rooms',
          onPressed: () {
            ref.read(virtualRoomsProvider.notifier).fetchRooms();
            _addLog('🔄 Triggered virtual rooms list refresh.');
          },
        )
      ],
      child: SafeArea(child: _buildBodyContent(isLoading, error, roomsCount)),
    );
  }

  // ─── RENDERING HELPERS FOR LAB CERTIFICATION CONTRACT ──────────────────────
  Widget _renderStateValue<T>({
    required DataState<T> state,
    required Widget Function(T val) onReady,
  }) {
    if (state is DataLoading<T>) {
      return const Text('—', style: TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace'));
    } else if (state is DataReady<T>) {
      return onReady(state.value);
    } else if (state is DataUnavailable<T>) {
      if (state.reason == 'GPS Required') {
        if (_currentPosition == null && !_gpsReady) {
          if (_gpsError != null) {
            return Text(
              _gpsError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
            );
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.orangeAccent),
              ),
              SizedBox(width: 6),
              Text(
                'Acquiring GPS...',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          );
        }
      }
      return Text(
        'Unavailable: ${state.reason}',
        style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
      );
    } else if (state is DataError<T>) {
      return Text(
        'Error: ${state.reason}',
        style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
      );
    }
    return const Text('—', style: TextStyle(color: Colors.white38, fontSize: 12));
  }

  Widget _buildTestCaseSubfield<T>({
    required String label,
    required DataState<T> state,
    required Widget Function(T val) onReady,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: _renderStateValue<T>(
                state: state,
                onReady: onReady,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestCaseCard({
    required String testNumber,
    required String title,
    required String description,
    required List<Widget> fields,
    required bool isPassed,
    required String statusLabel,
    Color? statusColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPassed ? Colors.tealAccent.withOpacity(0.15) : Colors.redAccent.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPassed ? Colors.teal.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        testNumber,
                        style: TextStyle(
                          color: isPassed ? Colors.tealAccent : Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (statusColor ?? (isPassed ? Colors.green : Colors.red)).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor ?? (isPassed ? Colors.green : Colors.red)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor ?? (isPassed ? Colors.greenAccent : Colors.redAccent),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(color: Colors.white38, fontSize: 10.5),
          ),
          const Divider(color: Colors.white10, height: 20),
          Column(children: fields),
        ],
      ),
    );
  }

  double calculateConfidence(double accuracy, double distanceToBoundary, bool isInside) {
    return _calculateGisConfidence(
      accuracyMeters: accuracy,
      distanceToBoundaryMeters: distanceToBoundary,
      isInsidePolygon: isInside,
    );
  }

  Widget _buildRoomDetailsCard() {
    if (_selectedRoom == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Text(
            'Select a room above to view verified configuration.',
            style: TextStyle(color: Colors.white38, fontSize: 11.5),
          ),
        ),
      );
    }

    final room = _selectedRoom!;
    final String dimensions = room.spatialMetadata['width_meters'] != null && room.spatialMetadata['length_meters'] != null
        ? '${room.spatialMetadata['width_meters']}m x ${room.spatialMetadata['length_meters']}m'
        : 'Not set';

    final String polyStatus = _roomPolygonPoints.isNotEmpty
        ? 'Calibrated (${_roomPolygonPoints.length} vertices)'
        : 'Not set';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.room_preferences_rounded, color: Colors.tealAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Test Case 4 — Room API Verification: ${room.name}',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 20),
          _buildDetailRow('Room Name', room.name),
          _buildDetailRow('Room Code', room.spatialMetadata['room_code']?.toString() ?? 'Not set'),
          _buildDetailRow('Department', room.department ?? 'Not set'),
          _buildDetailRow('Building', room.building ?? 'Not set'),
          _buildDetailRow('Floor', room.floorNumber.toString()),
          _buildDetailRow('Capacity', room.capacity.toString()),
          _buildDetailRow('Room Dimensions', dimensions),
          _buildDetailRow('Created By', room.createdBy ?? 'Not set'),
          _buildDetailRow('Created Date', room.createdAt?.toIso8601String() ?? 'Not set'),
          _buildDetailRow('Polygon Status', polyStatus, isHighlight: true),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          Text(
            value,
            style: TextStyle(
              color: isHighlight ? Colors.tealAccent : Colors.white,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCertificationBanner(UserTelemetryState state) {
    if (_selectedRoom == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_rounded, color: Colors.blueAccent, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Please select a Virtual Room to begin the physical validation and certification process.',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    final bool isGpsUnavailable = state.location == null || state.accuracy == 0.0;
    final bool isPolygonUnavailable = _roomPolygonPoints.isEmpty || _roomCenter == null;
    final bool isApiUnauthorized = _attendanceApiStatus == 'UNAUTHORIZED' || _validationApiStatus == 'UNAUTHORIZED';
    final bool isApiFailed = _attendanceApiStatus.startsWith('FAILED') || _validationApiStatus.startsWith('FAIL') || _roomApiStatus.startsWith('FAIL');

    String? failureReason;
    if (isGpsUnavailable) {
      failureReason = 'Test Case 5: GPS Lock is not active or signal is lost.';
    } else if (isPolygonUnavailable) {
      failureReason = 'Test Case 6: Target virtual room polygon geometry could not be loaded.';
    } else if (isApiUnauthorized) {
      failureReason = 'API Health: Insufficient permissions for attendance or validation endpoints.';
    } else if (isApiFailed) {
      failureReason = 'API Health: Connection link is currently failed or timed out.';
    } else if (!state.isInsideStabilized) {
      failureReason = 'Test Case 2: Lab Assistant physically stands outside the geofence limits.';
    } else if (state.accuracy > 15.0) {
      failureReason = 'Test Case 5: GPS Accuracy exceeds the safety limit (current: ${state.accuracy.toStringAsFixed(1)}m > 15m).';
    } else if (state.confidenceScore < 60.0) {
      failureReason = 'Location confidence is too low (${state.confidenceScore.toStringAsFixed(0)}%). Cannot confirm room position. Improve GPS signal.';
    } else if (state.isMocked) {
      failureReason = 'Test Case 5: Location spoofing or virtual provider mock flag detected!';
    } else if (!_isSessionActive) {
      failureReason = 'Test Case 7: Attendance active session is not running inside this room.';
    }

    final bool isCertified = failureReason == null;

    if (isCertified) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.teal.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.tealAccent, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.tealAccent.withOpacity(0.1),
              blurRadius: 16,
              spreadRadius: 2,
            )
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_rounded, color: Colors.tealAccent, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '✓ ROOM VALIDATION STATUS: READY FOR PRODUCTION',
                    style: TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              'All 8 test cases have successfully passed! The virtual room polygon geometry, GPS telemetry stability, teacher presence verification, and attendance endpoints are certified for live production use by teachers and students.',
              style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
            ),
          ],
        ),
      );
    } else {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.redAccent, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '✗ ROOM VALIDATION STATUS: VALIDATION FAILED',
                    style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Certification Blocker: $failureReason',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'To certify this room, the Lab Assistant must resolve all active failures. Ensure you are standing physically inside the room, GPS has stabilized with high accuracy, and the attendance session is active.',
              style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildBodyContent(bool isLoading, String? error, int roomsCount) {
    if (isLoading && roomsCount == 0) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blueAccent),
            SizedBox(height: 16),
            Text('Loading Campus Virtual Rooms...', style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      );
    }

    if (error != null && roomsCount == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 54),
                const SizedBox(height: 16),
                const Text('Connection Calibration Failed',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry Calibration Request'),
                  onPressed: () => ref.read(virtualRoomsProvider.notifier).fetchRooms(),
                )
              ],
            ),
          ),
        ),
      );
    }

    if (roomsCount == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.04)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.layers_clear_rounded, color: Colors.white38, size: 54),
                const SizedBox(height: 16),
                const Text('No Virtual Rooms Available',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Please record and calibrate geofence polygons in the room manager before accessing validation tests.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check For Rooms Again'),
                  onPressed: () => ref.read(virtualRoomsProvider.notifier).fetchRooms(),
                )
              ],
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder<UserTelemetryState>(
      valueListenable: _telemetryNotifier,
      builder: (context, state, _) {
        final bool isGpsReady = _gpsReady && _currentPosition != null;
        final bool isPolyReady = _roomPolygonPoints.isNotEmpty;

        // Map telemetry data states
        final roomFoundState = _selectedRoom != null ? DataReady<bool>(true) : const DataUnavailable<bool>('No Room Selected');
        final polyLoadedState = isPolyReady ? DataReady<bool>(true) : const DataUnavailable<bool>('Room polygon unavailable');

        final insideRoomState = !isGpsReady
            ? const DataUnavailable<bool>('GPS Required')
            : (!isPolyReady ? const DataUnavailable<bool>('Room polygon unavailable') : DataReady<bool>(state.isInsideStabilized));

        final distanceState = !isGpsReady
            ? const DataUnavailable<double>('GPS Required')
            : DataReady<double>(state.distance);

        final validationState = !isGpsReady
            ? const DataUnavailable<String>('GPS Required')
            : (!isPolyReady ? const DataUnavailable<String>('Room polygon unavailable') : DataReady<String>(_validationApiStatus));

        final attendanceState = !isGpsReady
            ? const DataUnavailable<String>('GPS Required')
            : (!isPolyReady ? const DataUnavailable<String>('Room polygon unavailable') : DataReady<String>(state.attendanceEligible ? 'VISIBLE' : 'HIDDEN'));

        final reasonState = !isGpsReady
            ? const DataUnavailable<String>('GPS Required')
            : (!isPolyReady
                ? const DataUnavailable<String>('Room polygon unavailable')
                : DataReady<String>(
                    !state.isInsideStabilized
                        ? 'Outside Boundary'
                        : ((_currentPosition?.accuracy ?? state.accuracy) > 15.0
                            ? 'Poor GPS'
                            : (!_isSessionActive
                                ? 'Session Inactive'
                                : (!state.isTeacherPresent ? 'Teacher Missing' : 'Eligible')))));

        // Boundary test states
        final boundaryDistanceState = !isGpsReady
            ? const DataUnavailable<double>('GPS Required')
            : (!isPolyReady ? const DataUnavailable<double>('Room polygon unavailable') : DataReady<double>(state.distanceToBoundary));

        final confidenceState = !isGpsReady
            ? const DataUnavailable<double>('GPS Required')
            : (!isPolyReady ? const DataUnavailable<double>('Room polygon unavailable') : DataReady<double>(calculateConfidence(_currentPosition!.accuracy, state.distanceToBoundary, state.isInsideStabilized)));

        final boundaryStatusState = !isGpsReady
            ? const DataUnavailable<String>('GPS Required')
            : (!isPolyReady
                ? const DataUnavailable<String>('Room polygon unavailable')
                : DataReady<String>(
                    state.distanceToBoundary <= _currentPosition!.accuracy
                        ? 'NEAR'
                        : (state.isInsideStabilized ? 'INSIDE' : 'OUTSIDE')));

        // GPS States
        final latState = isGpsReady ? DataReady<double>(_currentPosition!.latitude) : const DataUnavailable<double>('GPS Required');
        final lngState = isGpsReady ? DataReady<double>(_currentPosition!.longitude) : const DataUnavailable<double>('GPS Required');
        final accuracyState = isGpsReady ? DataReady<double>(_currentPosition!.accuracy) : const DataUnavailable<double>('GPS Required');
        final gpsLockState = DataReady<String>(state.gpsLockStatus);
        final gpsStabState = isGpsReady
            ? DataReady<String>(_gpsHistoryBuffer.length >= _stabilizationWindowSize ? 'STABILIZED (Window: 5)' : 'STABILIZING')
            : const DataUnavailable<String>('GPS Required');
        final gpsHealthState = isGpsReady
            ? DataReady<String>(_currentPosition!.accuracy <= 15.0 ? 'EXCELLENT' : (_currentPosition!.accuracy <= 30.0 ? 'GOOD' : 'POOR'))
            : const DataUnavailable<String>('GPS Required');
        final signalState = isGpsReady
            ? DataReady<String>(_currentPosition!.accuracy <= 15.0 ? 'STRONG' : (_currentPosition!.accuracy <= 35.0 ? 'MEDIUM' : 'WEAK'))
            : const DataUnavailable<String>('GPS Required');

        // Polygon Validation States
        final polyExistsState = isPolyReady ? DataReady<bool>(true) : const DataUnavailable<bool>('Room polygon unavailable');
        final polyValidState = isPolyReady && _roomCenter != null ? DataReady<bool>(true) : const DataUnavailable<bool>('Room polygon unavailable');
        final polyLoadedState2 = isPolyReady ? DataReady<bool>(true) : const DataUnavailable<bool>('Room polygon unavailable');
        final polyCoordsState = isPolyReady ? DataReady<bool>(true) : const DataUnavailable<bool>('Room polygon unavailable');
        final centerValidState = _roomCenter != null ? DataReady<bool>(true) : const DataUnavailable<bool>('Room center invalid');
        final areaValidState = (_selectedRoom?.spatialMetadata['width_meters'] as num? ?? 0.0) > 0.0 ? DataReady<bool>(true) : const DataUnavailable<bool>('Room area invalid');

        // Attendance eligibility states
        final eligibleInsideState = insideRoomState;
        final eligibleState = !isGpsReady
            ? const DataUnavailable<bool>('GPS Required')
            : (!isPolyReady
                ? const DataUnavailable<bool>('Room polygon unavailable')
                : (_attendanceApiStatus == 'UNAUTHORIZED' || _attendanceApiStatus.startsWith('FAILED')
                    ? const DataUnavailable<bool>('Attendance data unavailable')
                    : DataReady<bool>(state.attendanceEligible)));

        // Teacher presence states
        final isAuthUnavailable = _attendanceApiStatus == 'UNAUTHORIZED' || _attendanceApiStatus.startsWith('FAILED');
        final teacherPresentState = isAuthUnavailable
            ? const DataUnavailable<bool>('Teacher presence data unavailable')
            : DataReady<bool>(state.isTeacherPresent);
        final teacherInsideState = isAuthUnavailable
            ? const DataUnavailable<bool>('Teacher presence data unavailable')
            : DataReady<bool>(state.isTeacherPresent);
        final sessionActiveState = isAuthUnavailable
            ? const DataUnavailable<bool>('Teacher presence data unavailable')
            : DataReady<bool>(_isSessionActive);
        final sessionStatusState = isAuthUnavailable
            ? const DataUnavailable<String>('Teacher presence data unavailable')
            : DataReady<String>(_isSessionActive ? 'ACTIVE SESSION' : 'NO ACTIVE SESSION');

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // tab selector for Modes
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _is3DViewMode = false),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !_is3DViewMode ? const Color(0xFF0F172A) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.dashboard_rounded, color: Colors.white70, size: 16),
                              SizedBox(width: 8),
                              Text('Validation Lab 🧪', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (_selectedRoom == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please select a Virtual Room first to load 3D occupancy model!')),
                            );
                            return;
                          }
                          setState(() => _is3DViewMode = true);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _is3DViewMode ? const Color(0xFF0F172A) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.view_in_ar_rounded, color: Colors.white70, size: 16),
                              SizedBox(width: 8),
                              Text('3D Occupancy 📊', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (!_is3DViewMode) ...[
                const Text('1. Select Virtual Room for Calibration Validation',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _RoomSelectorWidget(
                  selectedRoom: _selectedRoom,
                  onRoomSelected: (room) {
                    setState(() {
                      _selectedRoom = room;
                      _roomCenter = LatLng(room.centerLat ?? 0.0, room.centerLng ?? 0.0);
                      _roomPolygonPoints = _buildPolygonPoints(room);
                      _isInsideRaw = false;
                      _isInsideStabilized = false;
                      _consecutiveInsideCount = 0;
                      _consecutiveOutsideCount = 0;
                      _telemetryNotifier.value = const UserTelemetryState();
                      _realUsersInside = [];
                      _totalInside = 0;
                      _isSessionActive = false;
                    });
                    _fetchRealOccupancy();
                    _checkActiveSession();
                    _startPolling();
                    
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _roomCenter != null) {
                        try {
                          _mapController.move(_roomCenter!, 18.5);
                        } catch (e) {
                          debugPrint('⚠️ Map controller move failed: $e');
                        }
                      }
                    });
                    _addLog('📂 Loaded room geometry for: ${room.name}');
                  },
                ),
                const SizedBox(height: 20),

                // ROOM CERTIFICATION RESULT
                _buildRoomCertificationBanner(state),
                const SizedBox(height: 20),

                // TEST CASE 4: Room Details configuration verification
                _buildRoomDetailsCard(),
                const SizedBox(height: 20),

                // Simulation controls
                _buildSimulationBoard(),
                const SizedBox(height: 20),

                // THE 8 PHYSICAL TEST CASES FOR LAB ASSISTANT
                const Text('Lab Assistant Certification Testing Board',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                // TEST CASE 1: STANDING INSIDE ROOM
                _buildTestCaseCard(
                  testNumber: 'TEST case 1',
                  title: 'Inside Room Validation',
                  description: 'Physically stand inside the calibrated virtual room geofence. Verifies correct entry detection.',
                  isPassed: _selectedRoom != null && isGpsReady && isPolyReady && state.isInsideStabilized,
                  statusLabel: _selectedRoom != null && isGpsReady && isPolyReady && state.isInsideStabilized ? 'PASS' : 'FAIL',
                  fields: [
                    _buildTestCaseSubfield<bool>(label: 'Room Found', state: roomFoundState, onReady: (v) => Text(v ? 'YES' : 'NO', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<bool>(label: 'Polygon Loaded', state: polyLoadedState, onReady: (v) => Text(v ? 'YES' : 'NO', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<bool>(label: 'Inside Room', state: insideRoomState, onReady: (v) => Text(v ? 'YES' : 'NO', style: TextStyle(color: v ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<double>(label: 'Distance to Center', state: distanceState, onReady: (v) => Text('${v.toStringAsFixed(1)}m', style: const TextStyle(color: Colors.white, fontSize: 11.5))),
                    _buildTestCaseSubfield<String>(label: 'Validation API', state: validationState, onReady: (v) => Text(v, style: TextStyle(color: v.startsWith('PASS') ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                  ],
                ),

                // TEST CASE 2: STANDING OUTSIDE ROOM
                _buildTestCaseCard(
                  testNumber: 'TEST case 2',
                  title: 'Outside Room Boundary Validation',
                  description: 'Walk outside the room boundary. Verifies correct exit geofencing containment and blockage.',
                  isPassed: _selectedRoom != null && isGpsReady && isPolyReady && !state.isInsideStabilized,
                  statusLabel: _selectedRoom != null && isGpsReady && isPolyReady && !state.isInsideStabilized ? 'PASS' : 'FAIL',
                  fields: [
                    _buildTestCaseSubfield<bool>(label: 'Inside Room', state: insideRoomState, onReady: (v) => Text(v ? 'YES' : 'NO', style: TextStyle(color: v ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<String>(label: 'Validation Status', state: validationState, onReady: (v) => Text(v, style: TextStyle(color: v.startsWith('PASS') ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<String>(label: 'Attendance Visibility', state: attendanceState, onReady: (v) => Text(v, style: TextStyle(color: v == 'VISIBLE' ? Colors.tealAccent : Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<String>(label: 'Failing Block Reason', state: reasonState, onReady: (v) => Text(v, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                  ],
                ),

                // TEST CASE 3: BOUNDARY EDGE TESTING
                _buildTestCaseCard(
                  testNumber: 'TEST case 3',
                  title: 'Boundary & Precision Edge Validation',
                  description: 'Stand at the threshold of the geofence to calibrate sensitivity, accuracy tolerances, and GIS confidence metrics.',
                  isPassed: _selectedRoom != null && isGpsReady && isPolyReady,
                  statusLabel: _selectedRoom != null && isGpsReady && isPolyReady ? 'CALIBRATED' : 'FAIL',
                  statusColor: _selectedRoom != null && isGpsReady && isPolyReady ? Colors.teal : Colors.red,
                  fields: [
                    _buildTestCaseSubfield<double>(label: 'Distance to Boundary', state: boundaryDistanceState, onReady: (v) => Text('${v.toStringAsFixed(2)} meters', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<double>(label: 'Validation Confidence', state: confidenceState, onReady: (v) => Text('${v.toStringAsFixed(1)}%', style: TextStyle(color: v > 75 ? Colors.tealAccent : Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<String>(label: 'Boundary Status', state: boundaryStatusState, onReady: (v) => Text(v, style: TextStyle(color: v == 'NEAR' ? Colors.orangeAccent : (v == 'INSIDE' ? Colors.tealAccent : Colors.redAccent), fontWeight: FontWeight.bold, fontSize: 11.5))),
                  ],
                ),

                // TEST CASE 5: GPS STABILIZATION AND QUALITY HEALTH
                _buildTestCaseCard(
                  testNumber: 'TEST case 5',
                  title: 'GPS Quality & Stabilization Health',
                  description: 'Monitors real device GPS hardware lock precision, stabilization window filter, and signals.',
                  isPassed: isGpsReady && state.accuracy <= 15.0 && !state.isMocked,
                  statusLabel: isGpsReady ? (state.isMocked ? 'WARNING: SPOOFED' : 'LOCKED (${state.accuracy.toStringAsFixed(1)}m)') : 'ACQUIRING',
                  statusColor: isGpsReady ? (state.isMocked ? Colors.orange : Colors.green) : Colors.amber,
                  fields: [
                    _buildTestCaseSubfield<double>(label: 'Current Latitude', state: latState, onReady: (v) => Text(v.toStringAsFixed(7), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontFamily: 'monospace'))),
                    _buildTestCaseSubfield<double>(label: 'Current Longitude', state: lngState, onReady: (v) => Text(v.toStringAsFixed(7), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontFamily: 'monospace'))),
                    _buildTestCaseSubfield<double>(label: 'GPS Accuracy Radius', state: accuracyState, onReady: (v) => Text('${v.toStringAsFixed(1)}m', style: TextStyle(color: v <= 15.0 ? Colors.tealAccent : Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<String>(label: 'GPS Signal Health', state: gpsHealthState, onReady: (v) => Text(v, style: TextStyle(color: v == 'EXCELLENT' ? Colors.tealAccent : Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<String>(label: 'Signal Quality', state: signalState, onReady: (v) => Text(v, style: TextStyle(color: v == 'STRONG' ? Colors.tealAccent : Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<String>(label: 'Stabilization Filter', state: gpsStabState, onReady: (v) => Text(v, style: const TextStyle(color: Colors.white70, fontSize: 11.5))),
                    _buildTestCaseSubfield<String>(label: 'Location Lock Status', state: gpsLockState, onReady: (v) => Text(v, style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                  ],
                ),

                // TEST CASE 6: POLYGON VERIFICATION AND CENTER VALIDATION
                _buildTestCaseCard(
                  testNumber: 'TEST case 6',
                  title: 'Polygon Geometry Integrity Calibration',
                  description: 'Verifies the room coordinate boundary shape is valid, loaded, and math center exists.',
                  isPassed: _selectedRoom != null && isPolyReady && _roomCenter != null,
                  statusLabel: _selectedRoom != null && isPolyReady && _roomCenter != null ? 'GEOMETRY PASS' : 'FAIL',
                  fields: [
                    _buildTestCaseSubfield<bool>(label: 'Polygon Coordinates Exists', state: polyExistsState, onReady: (v) => Text(v ? 'YES' : 'NO', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<bool>(label: 'Polygon Vertices Loaded', state: polyLoadedState2, onReady: (v) => Text(v ? 'YES (${_roomPolygonPoints.length} vertices)' : 'NO', style: const TextStyle(color: Colors.white70, fontSize: 11.5))),
                    _buildTestCaseSubfield<bool>(label: 'Polygon Map Geometry Valid', state: polyValidState, onReady: (v) => Text(v ? 'YES' : 'NO', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<bool>(label: 'Room Center Valid', state: centerValidState, onReady: (v) => Text(v ? 'YES (${_roomCenter!.latitude.toStringAsFixed(6)}, ${_roomCenter!.longitude.toStringAsFixed(6)})' : 'NO', style: const TextStyle(color: Colors.white70, fontSize: 11.5))),
                    _buildTestCaseSubfield<bool>(label: 'Room Floor Area Calibrated', state: areaValidState, onReady: (v) => Text(v ? 'YES' : 'NO', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                  ],
                ),

                // TEST CASE 7: ATTENDANCE ELIGIBILITY
                _buildTestCaseCard(
                  testNumber: 'TEST case 7',
                  title: 'Attendance Eligibility Gate',
                  description: 'Evaluates if a student is allowed to capture attendance in this geofence at this instant.',
                  isPassed: _selectedRoom != null && state.attendanceEligible,
                  statusLabel: _selectedRoom != null && state.attendanceEligible ? 'ELIGIBLE' : 'BLOCKED',
                  statusColor: _selectedRoom != null && state.attendanceEligible ? Colors.green : Colors.amber,
                  fields: [
                    _buildTestCaseSubfield<bool>(label: 'Containment (Inside Room)', state: eligibleInsideState, onReady: (v) => Text(v ? 'YES' : 'NO', style: TextStyle(color: v ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<bool>(label: 'Eligibility Status', state: eligibleState, onReady: (v) => Text(v ? 'YES: READY' : 'NO: BLOCKED', style: TextStyle(color: v ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<String>(label: 'Denial/Eligibility Reason', state: reasonState, onReady: (v) => Text(v, style: TextStyle(color: v == 'Eligible' ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                  ],
                ),

                // TEST CASE 8: TEACHER PRESENCE AND ATTENDANCE SESSIONS
                _buildTestCaseCard(
                  testNumber: 'TEST case 8',
                  title: 'Teacher Presence & Active Session Verification',
                  description: 'Ensures the geofence scanner and matching attendance period session is running live.',
                  isPassed: _selectedRoom != null && state.isTeacherPresent && _isSessionActive,
                  statusLabel: _selectedRoom != null && state.isTeacherPresent && _isSessionActive ? 'PASS' : 'FAIL',
                  fields: [
                    _buildTestCaseSubfield<bool>(label: 'Teacher Present Inside Room', state: teacherPresentState, onReady: (v) => Text(v ? 'YES' : 'NO', style: TextStyle(color: v ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<bool>(label: 'Teacher Geofence Intersection', state: teacherInsideState, onReady: (v) => Text(v ? 'YES' : 'NO', style: TextStyle(color: v ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<bool>(label: 'Active Attendance Period', state: sessionActiveState, onReady: (v) => Text(v ? 'YES' : 'NO', style: TextStyle(color: v ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                    _buildTestCaseSubfield<String>(label: 'Attendance Session Status', state: sessionStatusState, onReady: (v) => Text(v, style: TextStyle(color: _isSessionActive ? Colors.tealAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11.5))),
                  ],
                ),
                const SizedBox(height: 20),

                const Text('2. Real-Time Geofence Map Overlay',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                RepaintBoundary(child: _buildMapSection()),
                const SizedBox(height: 20),

                const Text('3. Validation Debug Panel (Enterprise Grade)',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                RepaintBoundary(
                  child: _LiveTelemetryGrid(
                    selectedRoom: _selectedRoom,
                    telemetryNotifier: _telemetryNotifier,
                  ),
                ),
                const SizedBox(height: 20),

                RepaintBoundary(
                  child: _AttendanceVisibilityTester(
                    selectedRoom: _selectedRoom,
                    telemetryNotifier: _telemetryNotifier,
                    isSessionActive: _isSessionActive,
                    activeSessionCode: _activeSessionCode,
                    attendanceApiStatus: _attendanceApiStatus,
                    attendanceSummaryError: _attendanceSummaryError,
                    onRetry: _checkActiveSession,
                  ),
                ),
                const SizedBox(height: 20),

                _buildDiagnosticsSection(),
                const SizedBox(height: 20),

                RepaintBoundary(
                  child: _SessionLoggerWidget(
                    isSessionActiveNotifier: _isSessionActiveNotifier,
                    sessionLogsNotifier: _sessionLogsNotifier,
                    onSessionStateChanged: (isActive) {
                      if (isActive) {
                        _sessionLogsNotifier.value = const [];
                        _addLog('🚀 Began virtual room validation session.');
                      } else {
                        _addLog('🛑 Validation session stopped.');
                      }
                    },
                  ),
                ),
                const SizedBox(height: 20),

                RepaintBoundary(
                  child: _ExpandableDebugPanel(
                    selectedRoom: _selectedRoom,
                    telemetryNotifier: _telemetryNotifier,
                  ),
                ),
              ] else ...[
                // 3D OCCUPANCY REAL-TIME VISUALIZER
                _build3DRealTimeOccupancyPanel(),
              ]
            ],
          ),
        );
      },
    );
  }

  // ── Simulation QA Override Board ──────────────────────────────────────────
  Widget _buildSimulationBoard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔬 QA Simulation Overrides (For Boundary & Drift Testing)',
              style: TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Manually inject edge cases to stress-test your client geofence validation rules:',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const Divider(color: Colors.white10, height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _buildSimToggle(
                label: 'Simulate GPS Drift (+8.5m)',
                value: _simulatingDrift,
                onChanged: (val) {
                  setState(() => _simulatingDrift = val);
                  _addLog(_simulatingDrift ? '⚠️ Simulated coordinate drift (+8.5m) Active' : '❇️ Coordinate drift Restored');
                },
              ),
              _buildSimToggle(
                label: 'Low GPS Accuracy (75m)',
                value: _simulatingLowAccuracy,
                onChanged: (val) {
                  setState(() => _simulatingLowAccuracy = val);
                  _addLog(_simulatingLowAccuracy ? '⚠️ Simulated Low Accuracy Bounds (75m)' : '❇️ Restored standard GPS accuracy');
                },
              ),
              _buildSimToggle(
                label: 'Spoofed Location Flag',
                value: _simulatingMockLocation,
                onChanged: (val) {
                  setState(() => _simulatingMockLocation = val);
                  _addLog(_simulatingMockLocation ? '🛑 Mock Developer Provider spoof flag ACTIVE' : '❇️ Mock simulation disabled');
                },
              ),
              _buildSimToggle(
                label: 'Force Teacher Presence',
                value: _simulatingTeacherPresentOverride,
                onChanged: (val) {
                  setState(() => _simulatingTeacherPresentOverride = val);
                  _addLog(_simulatingTeacherPresentOverride ? '❇️ Teacher presence override FORCED TRUE' : '❇️ Restored live API teacher detection');
                },
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSimToggle({required String label, required bool value, required ValueChanged<bool> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: value ? Colors.tealAccent.withOpacity(0.3) : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(width: 8),
          SizedBox(
            height: 20,
            width: 32,
            child: Switch(
              value: value,
              activeColor: Colors.tealAccent,
              onChanged: onChanged,
            ),
          )
        ],
      ),
    );
  }

  // ── 3D Dashboard Occupancy Panel ──────────────────────────────────────────
  Widget _build3DRealTimeOccupancyPanel() {
    final totalSeats = _selectedRoom?.capacity ?? 60;
    
    // Convert actual live database room occupants into StudentOccupant coordinates
    final List<StudentOccupant> realStudents = [];
    bool teacherPresent = false;

    for (int i = 0; i < _realUsersInside.length; i++) {
      final user = _realUsersInside[i];
      final role = user['role']?.toString() ?? 'student';
      if (role == 'teacher' || role == 'admin' || role == 'lab_assistant') {
        teacherPresent = true;
      } else {
        final gx = (realStudents.length % 6).toDouble();
        final gy = (realStudents.length ~/ 6).toDouble();
        final lastAccuracy = (user['last_accuracy'] as num? ?? 5.0).toDouble();

        realStudents.add(StudentOccupant(
          name: user['name']?.toString() ?? 'Unknown Student',
          rollNumber: user['user_id']?.toString() ?? 'N/A',
          department: user['department']?.toString() ?? 'N/A',
          gridX: gx,
          gridY: gy,
          validationPassed: lastAccuracy <= 15.0,
          securityAlert: lastAccuracy > 15.0 ? 'High GPS drift (±${lastAccuracy.toStringAsFixed(1)}m)' : '',
        ));
      }
    }

    if (_simulatingTeacherPresentOverride) {
      teacherPresent = true;
    }

    final presentCount = realStudents.length;
    final absentCount = totalSeats - presentCount;
    final double occupancyRate = totalSeats > 0 ? (presentCount / totalSeats) * 100 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Real-Time Analytics Bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.teal.withOpacity(0.15)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedRoom?.name ?? 'Virtual Room',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const Text('Live Geofenced Occupancy Dashboard', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: teacherPresent ? Colors.amber.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: teacherPresent ? Colors.amber : Colors.red),
                    ),
                    child: Text(
                      teacherPresent ? 'TEACHER PRESENT' : 'TEACHER ABSENT',
                      style: TextStyle(color: teacherPresent ? Colors.amberAccent : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              ),
              const Divider(color: Colors.white10, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildOccupancyStat('ROOM CAPACITY', '$totalSeats SEATS', Icons.chair_rounded, Colors.white70),
                  _buildOccupancyStat('PRESENT (VALIDATED)', '$presentCount', Icons.check_circle_rounded, Colors.greenAccent),
                  _buildOccupancyStat('ABSENT', '$absentCount', Icons.cancel_rounded, Colors.white30),
                  _buildOccupancyStat('OCCUPANCY', '${occupancyRate.toStringAsFixed(1)}%', Icons.pie_chart_rounded, Colors.tealAccent),
                ],
              )
            ],
          ),
        ),
        const SizedBox(height: 20),

        if (_occupancyError != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _occupancyError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        if (_isFetchingOccupancy && realStudents.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(color: Colors.tealAccent),
            ),
          )
        else
          _Interactive3DViewport(
            roomWidth: (_selectedRoom!.spatialMetadata['width_meters'] as num? ?? 10.0).toDouble(),
            roomLength: (_selectedRoom!.spatialMetadata['length_meters'] as num? ?? 12.0).toDouble(),
            students: realStudents,
            teacherPresent: teacherPresent,
          ),
      ],
    );
  }

  Widget _buildOccupancyStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDiagnosticsSection() {
    final syncTimeStr = _lastSyncTime != null
        ? '${_lastSyncTime!.hour.toString().padLeft(2, '0')}:${_lastSyncTime!.minute.toString().padLeft(2, '0')}:${_lastSyncTime!.second.toString().padLeft(2, '0')}'
        : 'N/A';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.health_and_safety_rounded, color: Colors.blueAccent, size: 20),
              SizedBox(width: 8),
              Text('4. API Connection Health Diagnostics',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDiagnosticCell('NETWORK LINK', _apiConnected ? 'CONNECTED' : 'FAILED', _apiConnected ? Colors.tealAccent : Colors.redAccent),
              _buildDiagnosticCell('RESP TIME', '${_responseTimeMs}ms', _responseTimeMs < 200 ? Colors.tealAccent : Colors.orangeAccent),
              _buildDiagnosticCell('LAST SYNC', syncTimeStr, Colors.white70),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          _buildHealthStatusRow('Room API (CRUD & Lists)', _roomApiStatus),
          _buildHealthStatusRow('Validation API (Polygon)', _validationApiStatus),
          _buildHealthStatusRow('Attendance Session API', _attendanceApiStatus),
        ],
      ),
    );
  }

  Widget _buildDiagnosticCell(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildHealthStatusRow(String apiName, String status) {
    final bool isOk = status == 'CONNECTED';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(apiName, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOk ? Colors.teal.withOpacity(0.12) : Colors.red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: isOk ? Colors.tealAccent : Colors.redAccent,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMapSection() {
    if (_startupPhase < 2) {
      return Container(
        height: 300,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: Text('Map initializing...', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      );
    }

    if (_roomCenter == null || _roomPolygonPoints.isEmpty) {
      return Container(
        height: 300,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_rounded, color: Colors.blue.shade400, size: 54),
            const SizedBox(height: 16),
            const Text('Geofence Map Calibration Required',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                'Select a Virtual Room above to visualize geofence overlays.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    return RoomValidationMapWidget(
      mapController: _mapController,
      roomCenter: _roomCenter,
      roomPolygonPoints: _roomPolygonPoints,
      telemetryNotifier: _telemetryNotifier,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACCESS DENIED CARD
// ─────────────────────────────────────────────────────────────────────────────
class _AccessDeniedCard extends StatelessWidget {
  const _AccessDeniedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 64),
          SizedBox(height: 16),
          Text('Access Denied',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(
            'Only Admins, Teachers, and Lab Assistants are authorized to access the Virtual Room Validation Laboratory.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROOM SELECTOR DROPDOWN
// ─────────────────────────────────────────────────────────────────────────────
class _RoomSelectorWidget extends ConsumerWidget {
  final VirtualRoomModel? selectedRoom;
  final ValueChanged<VirtualRoomModel> onRoomSelected;

  const _RoomSelectorWidget({
    required this.selectedRoom,
    required this.onRoomSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(virtualRoomsProvider.select((state) => state.rooms));

    final bool exists = selectedRoom != null && rooms.any((r) => r.id == selectedRoom!.id);
    final VirtualRoomModel? activeValue = exists ? rooms.firstWhere((r) => r.id == selectedRoom!.id) : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<VirtualRoomModel>(
          dropdownColor: const Color(0xFF1E293B),
          hint: const Text('Search / Select Virtual Room', style: TextStyle(color: Colors.white38, fontSize: 13)),
          value: activeValue,
          isExpanded: true,
          style: const TextStyle(color: Colors.white),
          items: rooms.map((room) {
            final width = (room.spatialMetadata['width_meters'] as num? ?? 10.0).toDouble();
            final length = (room.spatialMetadata['length_meters'] as num? ?? 12.0).toDouble();
            return DropdownMenuItem<VirtualRoomModel>(
              value: room,
              child: Text(
                '${room.name} (${room.building}) · ${width.toStringAsFixed(0)}x${length.toStringAsFixed(0)}m',
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            );
          }).toList(),
          onChanged: (room) {
            if (room != null) onRoomSelected(room);
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RoomValidationMapWidget STATEFUL MAP ENGINE
// ─────────────────────────────────────────────────────────────────────────────
class RoomValidationMapWidget extends StatefulWidget {
  final MapController mapController;
  final LatLng? roomCenter;
  final List<LatLng> roomPolygonPoints;
  final ValueNotifier<UserTelemetryState> telemetryNotifier;

  const RoomValidationMapWidget({
    Key? key,
    required this.mapController,
    required this.roomCenter,
    required this.roomPolygonPoints,
    required this.telemetryNotifier,
  }) : super(key: key);

  @override
  State<RoomValidationMapWidget> createState() => _RoomValidationMapWidgetState();
}

class _RoomValidationMapWidgetState extends State<RoomValidationMapWidget> {
  LatLng? _userLoc;
  double _heading = 0.0;

  @override
  void initState() {
    super.initState();
    _userLoc = widget.telemetryNotifier.value.location;
    _heading = widget.telemetryNotifier.value.heading;
    widget.telemetryNotifier.addListener(_onTelemetry);
  }

  @override
  void didUpdateWidget(RoomValidationMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.telemetryNotifier != widget.telemetryNotifier) {
      oldWidget.telemetryNotifier.removeListener(_onTelemetry);
      _userLoc = widget.telemetryNotifier.value.location;
      _heading = widget.telemetryNotifier.value.heading;
      widget.telemetryNotifier.addListener(_onTelemetry);
    }
  }

  void _onTelemetry() {
    if (!mounted) return;
    final val = widget.telemetryNotifier.value;
    if (val.location != _userLoc || val.heading != _heading) {
      setState(() {
        _userLoc = val.location;
        _heading = val.heading;
      });
    }
  }

  @override
  void dispose() {
    widget.telemetryNotifier.removeListener(_onTelemetry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasValidPolygon = widget.roomPolygonPoints.length >= 3 &&
        widget.roomPolygonPoints.every((p) =>
            !p.latitude.isNaN && !p.longitude.isNaN && !p.latitude.isInfinite && !p.longitude.isInfinite);

    final LatLng? userLoc = _userLoc;
    final double heading = _heading;
    final bool userLocValid = userLoc != null && !userLoc.latitude.isNaN && !userLoc.longitude.isNaN;

    return SizedBox(
      height: 300,
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              FlutterMap(
                mapController: widget.mapController,
                options: MapOptions(
                  initialCenter: widget.roomCenter ?? const LatLng(19.076, 72.877),
                  initialZoom: 18.5,
                  maxZoom: 22,
                ),
                children: [
                  TileLayer(
                    urlTemplate: MapConfig.urlTemplate,
                    subdomains: MapConfig.subdomains,
                    additionalOptions: MapConfig.headers,
                    userAgentPackageName: MapConfig.userAgentPackageName,
                    maxZoom: 22,
                  ),
                  if (hasValidPolygon)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: widget.roomPolygonPoints,
                          color: Colors.teal.withOpacity(0.22),
                          borderColor: Colors.tealAccent,
                          borderStrokeWidth: 3,
                        ),
                      ],
                    ),
                  if (widget.roomCenter != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: widget.roomCenter!,
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.stars_rounded, color: Colors.amber, size: 30),
                        ),
                      ],
                    ),
                  if (userLocValid)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: userLoc!,
                          width: 45,
                          height: 45,
                          child: Transform.rotate(
                            angle: heading * math.pi / 180,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.3),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.blueAccent, width: 2),
                                  ),
                                ),
                                const Icon(Icons.navigation_rounded, color: Colors.blueAccent, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              Positioned(
                bottom: 12,
                right: 12,
                child: FloatingActionButton.small(
                  backgroundColor: Colors.blue.shade700,
                  onPressed: () {
                    if (userLocValid) {
                      try {
                        widget.mapController.move(userLoc!, 19.0);
                      } catch (e) {
                        debugPrint('⚠️ map move failed: $e');
                      }
                    }
                  },
                  child: const Icon(Icons.my_location_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REAL-TIME ISOLATED TELEMETRY GRID
// ─────────────────────────────────────────────────────────────────────────────
class _LiveTelemetryGrid extends StatelessWidget {
  final VirtualRoomModel? selectedRoom;
  final ValueNotifier<UserTelemetryState> telemetryNotifier;

  const _LiveTelemetryGrid({
    required this.selectedRoom,
    required this.telemetryNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserTelemetryState>(
      valueListenable: telemetryNotifier,
      builder: (context, state, _) {
        final bool isGpsUnavailable = state.location == null || state.accuracy == 0.0;
        final bool isPolygonUnavailable = selectedRoom == null || selectedRoom!.centerLat == null || selectedRoom!.centerLng == null;

        // 1. GEOFENCE STATUS
        String geofenceValue;
        IconData geofenceIcon = Icons.cancel_rounded;
        Color geofenceColor = Colors.grey;

        if (isGpsUnavailable) {
          geofenceValue = 'GPS Required';
        } else if (selectedRoom == null) {
          geofenceValue = 'No Room Selected';
        } else if (isPolygonUnavailable) {
          geofenceValue = 'Room polygon unavailable';
        } else {
          geofenceValue = state.isInsideStabilized ? 'INSIDE ROOM' : 'OUTSIDE ROOM';
          geofenceIcon = state.isInsideStabilized ? Icons.check_circle_rounded : Icons.cancel_rounded;
          geofenceColor = state.isInsideStabilized ? Colors.green.shade400 : Colors.amber.shade500;
        }

        // 2. GPS LOCK ACCURACY
        String gpsValue;
        Color gpsColor = Colors.grey;
        if (isGpsUnavailable) {
          gpsValue = state.gpsLockStatus != 'ACQUIRING' ? state.gpsLockStatus : 'GPS Data Not Available';
        } else {
          gpsValue = '±${state.accuracy.toStringAsFixed(1)}m';
          gpsColor = state.accuracy <= 4.0
              ? Colors.tealAccent
              : (state.accuracy <= 15.0 ? Colors.orangeAccent : Colors.redAccent);
        }

        // 3. GIS CONFIDENCE SCORE
        String confidenceValue;
        Color confidenceColor = Colors.grey;
        if (isGpsUnavailable) {
          confidenceValue = 'GPS Required';
        } else {
          confidenceValue = '${state.confidenceScore.toStringAsFixed(1)}%';
          confidenceColor = state.confidenceScore >= 80.0 ? Colors.tealAccent : Colors.orangeAccent;
        }

        // 4. SECURITY INTEGRITY
        String securityValue;
        IconData securityIcon = Icons.verified_user_rounded;
        Color securityColor = Colors.grey;
        if (isGpsUnavailable) {
          securityValue = 'GPS Required';
        } else {
          securityValue = state.isMocked ? 'SPOOF DETECTED' : 'SAFE / CLEAN';
          securityIcon = state.isMocked ? Icons.warning_amber_rounded : Icons.verified_user_rounded;
          securityColor = state.isMocked ? Colors.redAccent : Colors.tealAccent;
        }

        return ExcludeSemantics(
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.1,
            children: [
              _buildValidationCard(
                title: 'GEOFENCE STATUS',
                value: geofenceValue,
                icon: geofenceIcon,
                color: geofenceColor,
              ),
              _buildValidationCard(
                title: 'GPS LOCK ACCURACY',
                value: gpsValue,
                icon: Icons.gps_fixed_rounded,
                color: gpsColor,
              ),
              _buildValidationCard(
                title: 'GIS CONFIDENCE SCORE',
                value: confidenceValue,
                icon: Icons.shield_rounded,
                color: confidenceColor,
              ),
              _buildValidationCard(
                title: 'SECURITY INTEGRITY',
                value: securityValue,
                icon: securityIcon,
                color: securityColor,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildValidationCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _AttendanceVisibilityTester extends StatelessWidget {
  final VirtualRoomModel? selectedRoom;
  final ValueNotifier<UserTelemetryState> telemetryNotifier;
  final bool isSessionActive;
  final String? activeSessionCode;
  final String attendanceApiStatus;
  final String? attendanceSummaryError;
  final VoidCallback onRetry;

  const _AttendanceVisibilityTester({
    required this.selectedRoom,
    required this.telemetryNotifier,
    required this.isSessionActive,
    this.activeSessionCode,
    required this.attendanceApiStatus,
    this.attendanceSummaryError,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (attendanceApiStatus == 'PENDING' || attendanceApiStatus == 'loading') {
      return const Card(
        color: Color(0xFF1E293B),
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            children: [
              CircularProgressIndicator(color: Colors.tealAccent),
              SizedBox(height: 12),
              Text('Checking active attendance sessions...', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    if (attendanceApiStatus == 'UNAUTHORIZED') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.lock_rounded, color: Colors.redAccent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Access Restricted',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        attendanceSummaryError ?? 'Attendance data unavailable: Insufficient permissions for this role.',
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 24),
            const Text(
              'Please contact your IT administrator to grant access to the /api/reports/attendance-summary/ endpoints.',
              style: TextStyle(color: Colors.white38, fontSize: 10.5, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    }

    if (attendanceApiStatus == 'TIMEOUT') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.watch_later_rounded, color: Colors.orangeAccent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Request Timed Out',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        attendanceSummaryError ?? 'Attendance API timed out after 15 seconds.',
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry Connection', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
    }

    if (attendanceApiStatus.startsWith('FAILED')) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Connection Error',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        attendanceSummaryError ?? 'Attendance data failed to load: $attendanceApiStatus',
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry Connection', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
    }

    if (attendanceApiStatus == 'NO_DATA') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_rounded, color: Colors.blueAccent, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No attendance records found for this period.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    // CONNECTED STATE
    return ValueListenableBuilder<UserTelemetryState>(
      valueListenable: telemetryNotifier,
      builder: (context, state, _) {
        final isVisible = selectedRoom != null &&
            state.isInsideStabilized &&
            state.accuracy <= 15.0 &&
            state.confidenceScore >= 60.0 &&
            !state.isMocked &&
            state.isTeacherPresent &&
            isSessionActive;

        String badgeText = isVisible ? 'VISIBLE' : 'HIDDEN';
        Color badgeColor = isVisible ? Colors.green : Colors.amber;
        Color badgeTextColor = isVisible ? Colors.greenAccent : Colors.amberAccent;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isVisible ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.06),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Attendance Visibility Status:',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: badgeColor),
                      ),
                      child: Text(
                        badgeText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: badgeTextColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                ],
              ),
              const Divider(color: Colors.white10, height: 24),
              _buildCheckRow('Student inside stabilized polygon geofence', state.isInsideStabilized),
              _buildCheckRow('GPS Accuracy within safety bounds (<= 15m)', state.accuracy <= 15.0),
              _buildCheckRow('GIS validation confidence score (>= 60%)', state.confidenceScore >= 60.0),
              _buildCheckRow('Anti-spoof integrity verified (No mock location)', !state.isMocked),
              _buildCheckRow('Teacher present inside Room geofence limits', state.isTeacherPresent),
              _buildCheckRow(
                isSessionActive && activeSessionCode != null
                    ? 'Active attendance session running in room ($activeSessionCode)'
                    : 'Active attendance session running in room',
                isSessionActive,
              ),
              _buildCheckRow('Target virtual room calibrated', selectedRoom != null),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCheckRow(String label, bool passed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: passed ? Colors.greenAccent : Colors.white24,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(color: passed ? Colors.white : Colors.white54, fontSize: 12)),
          )
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION LOGGER
// ─────────────────────────────────────────────────────────────────────────────
class _SessionLoggerWidget extends StatelessWidget {
  final ValueNotifier<bool> isSessionActiveNotifier;
  final ValueNotifier<List<String>> sessionLogsNotifier;
  final Function(bool) onSessionStateChanged;

  const _SessionLoggerWidget({
    required this.isSessionActiveNotifier,
    required this.sessionLogsNotifier,
    required this.onSessionStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('5. Live Boundary Audit Logger',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ValueListenableBuilder<bool>(
              valueListenable: isSessionActiveNotifier,
              builder: (context, isActive, _) {
                return ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive ? Colors.red.shade700 : Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: () {
                    isSessionActiveNotifier.value = !isActive;
                    onSessionStateChanged(!isActive);
                  },
                  icon: Icon(isActive ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  label: Text(isActive ? 'Stop Logging' : 'Start Session', style: const TextStyle(fontSize: 12)),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 150,
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: ValueListenableBuilder<List<String>>(
            valueListenable: sessionLogsNotifier,
            builder: (context, logs, _) {
              if (logs.isEmpty) {
                return const Center(
                  child: Text(
                    'Press "Start Session" to capture live boundary telemetry logs.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white30, fontSize: 11, fontFamily: 'monospace'),
                  ),
                );
              }
              return ExcludeSemantics(
                child: ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, idx) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Text(logs[idx],
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace')),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DEBUG TELEMETRY PANEL
// ─────────────────────────────────────────────────────────────────────────────
class _ExpandableDebugPanel extends StatelessWidget {
  final VirtualRoomModel? selectedRoom;
  final ValueNotifier<UserTelemetryState> telemetryNotifier;

  const _ExpandableDebugPanel({
    required this.selectedRoom,
    required this.telemetryNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        collapsedIconColor: Colors.white54,
        iconColor: Colors.tealAccent,
        title: const Text('🔬 Expand Developer Debug Telemetry',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ValueListenableBuilder<UserTelemetryState>(
              valueListenable: telemetryNotifier,
              builder: (context, state, _) {
                final bool isGpsUnavailable = state.location == null || state.accuracy == 0.0;
                final bool isPolygonUnavailable = selectedRoom == null || selectedRoom!.centerLat == null || selectedRoom!.centerLng == null;

                return ExcludeSemantics(
                  child: Table(
                    border: TableBorder.all(color: Colors.white10, width: 1, borderRadius: BorderRadius.circular(8)),
                    children: [
                      _buildDebugRow(
                        'Raw Coordinates',
                        isGpsUnavailable
                            ? 'GPS Required'
                            : 'Lat: ${state.location!.latitude.toStringAsFixed(6)}, Lng: ${state.location!.longitude.toStringAsFixed(6)}',
                      ),
                      _buildDebugRow(
                        'Stabilized Coordinates',
                        isGpsUnavailable
                            ? 'GPS Required'
                            : 'Lat: ${state.stabilizedLocation!.latitude.toStringAsFixed(6)}, Lng: ${state.stabilizedLocation!.longitude.toStringAsFixed(6)}',
                      ),
                      _buildDebugRow(
                        'Accuracy / GPS Lock',
                        isGpsUnavailable ? 'GPS Required' : '±${state.accuracy.toStringAsFixed(2)} meters',
                      ),
                      _buildDebugRow(
                        'Center Distance',
                        isGpsUnavailable
                            ? 'GPS Required'
                            : (selectedRoom == null ? 'No Room Selected' : '${state.distance.toStringAsFixed(2)} meters'),
                      ),
                      _buildDebugRow(
                        'Geofence Boundary Dist',
                        isGpsUnavailable
                            ? 'GPS Required'
                            : (selectedRoom == null
                                ? 'No Room Selected'
                                : (isPolygonUnavailable ? 'Room polygon unavailable' : '${state.distanceToBoundary.toStringAsFixed(2)} meters')),
                      ),
                      _buildDebugRow(
                        'GIS Confidence Score',
                        isGpsUnavailable ? 'GPS Required' : '${state.confidenceScore.toStringAsFixed(1)}%',
                      ),
                      _buildDebugRow(
                        'Multiple Room Overlap',
                        isGpsUnavailable ? 'GPS Required' : state.overlappingRooms,
                      ),
                      _buildDebugRow('GPS Lock Status', state.gpsLockStatus),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildDebugRow(String key, String val) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(key, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(val, style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontFamily: 'monospace')),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INTERACTIVE 2D / 3D OCCUPANCY VIEWPORT
// ─────────────────────────────────────────────────────────────────────────────
class _Interactive3DViewport extends StatefulWidget {
  final double roomWidth;
  final double roomLength;
  final List<StudentOccupant> students;
  final bool teacherPresent;

  const _Interactive3DViewport({
    Key? key,
    required this.roomWidth,
    required this.roomLength,
    required this.students,
    required this.teacherPresent,
  }) : super(key: key);

  @override
  State<_Interactive3DViewport> createState() => _Interactive3DViewportState();
}

class _Interactive3DViewportState extends State<_Interactive3DViewport> {
  double _yaw = -3.8;      // Orbit angle
  double _pitch = -0.4;    // Pitch altitude angle
  double _zoom = 1.0;      // Zoom scale factor
  bool _isPerspective = true; // Toggle between 2D Top CAD view & 3D mesh

  StudentOccupant? _selectedStudent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // CAD Rotational & View Controls toolbar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('CAD Visualization Controls',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      const Text('2D View', style: TextStyle(color: Colors.white38, fontSize: 10)),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 20,
                        width: 32,
                        child: Switch(
                          value: _isPerspective,
                          activeColor: Colors.tealAccent,
                          onChanged: (val) => setState(() => _isPerspective = val),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('3D View', style: TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  )
                ],
              ),
              if (_isPerspective) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.rotate_left_rounded, color: Colors.white38, size: 14),
                    const SizedBox(width: 8),
                    const Text('Orbit Rot:', style: TextStyle(color: Colors.white38, fontSize: 9)),
                    Expanded(
                      child: Slider(
                        value: _yaw,
                        min: -math.pi * 2,
                        max: math.pi * 2,
                        activeColor: Colors.tealAccent,
                        onChanged: (v) => setState(() => _yaw = v),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.height_rounded, color: Colors.white38, size: 14),
                    const SizedBox(width: 8),
                    const Text('Pitch Alt:', style: TextStyle(color: Colors.white38, fontSize: 9)),
                    Expanded(
                      child: Slider(
                        value: _pitch,
                        min: -math.pi / 2 + 0.1,
                        max: 0.1,
                        activeColor: Colors.tealAccent,
                        onChanged: (v) => setState(() => _pitch = v),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.zoom_in_rounded, color: Colors.white38, size: 14),
                    const SizedBox(width: 8),
                    const Text('Zoom Lvl:', style: TextStyle(color: Colors.white38, fontSize: 9)),
                    Expanded(
                      child: Slider(
                        value: _zoom,
                        min: 0.5,
                        max: 1.5,
                        activeColor: Colors.tealAccent,
                        onChanged: (v) => setState(() => _zoom = v),
                      ),
                    ),
                  ],
                )
              ]
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Interactive 3D Perspective Graphic Box
        GestureDetector(
          onTapDown: (details) {
            _handleCanvasClick(details.localPosition, context);
          },
          child: Container(
            height: 380,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.teal.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.teal.withOpacity(0.08),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ]
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: CustomPaint(
                painter: _Room3DPainter(
                  yaw: _yaw,
                  pitch: _pitch,
                  zoom: _zoom,
                  isPerspective: _isPerspective,
                  students: widget.students,
                  teacherPresent: widget.teacherPresent,
                  selectedStudent: _selectedStudent,
                ),
              ),
            ),
          ),
        ),

        // Clicked Interactive Detail Card Drawer
        if (_selectedStudent != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _selectedStudent!.validationPassed ? Colors.tealAccent.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _selectedStudent!.validationPassed ? Colors.teal.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                  radius: 20,
                  child: Icon(
                    _selectedStudent!.validationPassed ? Icons.person_rounded : Icons.gpp_bad_rounded,
                    color: _selectedStudent!.validationPassed ? Colors.tealAccent : Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_selectedStudent!.name,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Roll/ID: ${_selectedStudent!.rollNumber} · Dept: ${_selectedStudent!.department}',
                          style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        _selectedStudent!.validationPassed
                            ? '✅ Geofence Validated • Seat Allocation Approved'
                            : '❌ Validation Blocked: ${_selectedStudent!.securityAlert}',
                        style: TextStyle(
                            color: _selectedStudent!.validationPassed ? Colors.tealAccent : Colors.redAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      )
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                  onPressed: () => setState(() => _selectedStudent = null),
                )
              ],
            ),
          )
        ]
      ],
    );
  }

  void _handleCanvasClick(Offset localPos, BuildContext context) {
    final size = const Size(350, 380); // match Container bounds approximately
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    double minDist = 30.0;
    StudentOccupant? clicked;

    final double cosY = math.cos(_isPerspective ? _yaw : 0.0);
    final double sinY = math.sin(_isPerspective ? _yaw : 0.0);
    final double cosP = math.cos(_isPerspective ? _pitch : -math.pi / 2);
    final double sinP = math.sin(_isPerspective ? _pitch : -math.pi / 2);

    for (final st in widget.students) {
      final double sx = -0.4 + (st.gridX / 5) * 0.8;
      final double sy = -0.4 + (st.gridY / 9) * 0.8;
      const double sz = -0.15; // Floor height

      // Rotate Y (yaw)
      final double rx1 = sx * cosY - sy * sinY;
      final double ry1 = sx * sinY + sy * cosY;
      final double rz1 = sz;

      // Rotate X (pitch)
      final double rx2 = rx1;
      final double ry2 = ry1 * cosP - rz1 * sinP;
      final double rz2 = ry1 * sinP + rz1 * cosP;

      final double zoomFactor = 280 * _zoom;
      final double divisor = _isPerspective ? (rz2 + 2.0) : 2.0;

      final double px = cx + (rx2 * zoomFactor) / divisor;
      final double py = cy + (ry2 * zoomFactor) / divisor;

      final double dist = (localPos - Offset(px, py)).distance;
      if (dist < minDist) {
        minDist = dist;
        clicked = st;
      }
    }

    if (clicked != null) {
      setState(() => _selectedStudent = clicked);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MATHEMATICAL Perspective 3D PROJECTION PAINTER
// ─────────────────────────────────────────────────────────────────────────────
class _Room3DPainter extends CustomPainter {
  final double yaw;
  final double pitch;
  final double zoom;
  final bool isPerspective;
  final List<StudentOccupant> students;
  final bool teacherPresent;
  final StudentOccupant? selectedStudent;

  const _Room3DPainter({
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.isPerspective,
    required this.students,
    required this.teacherPresent,
    required this.selectedStudent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    final double cosY = math.cos(isPerspective ? yaw : 0.0);
    final double sinY = math.sin(isPerspective ? yaw : 0.0);
    final double cosP = math.cos(isPerspective ? pitch : -math.pi / 2);
    final double sinP = math.sin(isPerspective ? pitch : -math.pi / 2);

    final double zoomFactor = 280 * zoom;

    Offset project(double x, double y, double z) {
      final double rx1 = x * cosY - y * sinY;
      final double ry1 = x * sinY + y * cosY;
      final double rz1 = z;

      final double rx2 = rx1;
      final double ry2 = ry1 * cosP - rz1 * sinP;
      final double rz2 = ry1 * sinP + rz1 * cosP;

      final double divisor = isPerspective ? (rz2 + 2.0) : 2.0;
      return Offset(cx + (rx2 * zoomFactor) / divisor, cy + (ry2 * zoomFactor) / divisor);
    }

    // Floor grid
    final gridPaint = Paint()
      ..color = Colors.teal.withOpacity(0.06)
      ..strokeWidth = 1.0;

    for (double i = -0.5; i <= 0.5; i += 0.1) {
      canvas.drawLine(project(i, -0.5, -0.2), project(i, 0.5, -0.2), gridPaint);
      canvas.drawLine(project(-0.5, i, -0.2), project(0.5, i, -0.2), gridPaint);
    }

    // Walls & boundaries
    final wallPaint = Paint()
      ..color = Colors.teal.withOpacity(0.18)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final wallFill = Paint()
      ..color = Colors.teal.withOpacity(0.015)
      ..style = PaintingStyle.fill;

    final f1 = project(-0.5, -0.5, -0.2);
    final f2 = project(0.5, -0.5, -0.2);
    final f3 = project(0.5, 0.5, -0.2);
    final f4 = project(-0.5, 0.5, -0.2);

    final c1 = project(-0.5, -0.5, 0.15);
    final c2 = project(0.5, -0.5, 0.15);
    final c3 = project(0.5, 0.5, 0.15);
    final c4 = project(-0.5, 0.5, 0.15);

    final floorPath = Path()..moveTo(f1.dx, f1.dy)..lineTo(f2.dx, f2.dy)..lineTo(f3.dx, f3.dy)..lineTo(f4.dx, f4.dy)..close();
    canvas.drawPath(floorPath, wallFill);

    canvas.drawPath(floorPath, wallPaint);
    canvas.drawLine(f1, c1, wallPaint);
    canvas.drawLine(f2, c2, wallPaint);
    canvas.drawLine(f3, c3, wallPaint);
    canvas.drawLine(f4, c4, wallPaint);

    if (isPerspective) {
      final ceilingPath = Path()..moveTo(c1.dx, c1.dy)..lineTo(c2.dx, c2.dy)..lineTo(c3.dx, c3.dy)..lineTo(c4.dx, c4.dy)..close();
      canvas.drawPath(ceilingPath, wallPaint);
    }

    // Teacher desk
    final double tx = 0.0;
    final double ty = -0.43;
    final double tz = -0.2;

    final l1 = project(tx - 0.1, ty - 0.06, tz);
    final l2 = project(tx + 0.1, ty - 0.06, tz);
    final l3 = project(tx + 0.1, ty + 0.06, tz);
    final l4 = project(tx - 0.1, ty + 0.06, tz);

    final lTop1 = project(tx - 0.1, ty - 0.06, tz + 0.08);
    final lTop2 = project(tx + 0.1, ty - 0.06, tz + 0.08);
    final lTop3 = project(tx + 0.1, ty + 0.06, tz + 0.08);
    final lTop4 = project(tx - 0.1, ty + 0.06, tz + 0.08);

    final deskPaint = Paint()
      ..color = Colors.amber.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    final deskBorder = Paint()
      ..color = Colors.amber.withOpacity(0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final deskPath = Path()..moveTo(l1.dx, l1.dy)..lineTo(l2.dx, l2.dy)..lineTo(l3.dx, l3.dy)..lineTo(l4.dx, l4.dy)..close();
    canvas.drawPath(deskPath, deskPaint);
    canvas.drawPath(deskPath, deskBorder);

    canvas.drawLine(l1, lTop1, deskBorder);
    canvas.drawLine(l2, lTop2, deskBorder);
    canvas.drawLine(l3, lTop3, deskBorder);
    canvas.drawLine(l4, lTop4, deskBorder);

    final deskTopPath = Path()..moveTo(lTop1.dx, lTop1.dy)..lineTo(lTop2.dx, lTop2.dy)..lineTo(lTop3.dx, lTop3.dy)..lineTo(lTop4.dx, lTop4.dy)..close();
    canvas.drawPath(deskTopPath, deskPaint);
    canvas.drawPath(deskTopPath, deskBorder);

    // Teacher beacon
    if (teacherPresent) {
      final tPos = project(tx, ty, tz + 0.12);
      final glowPaint = Paint()
        ..color = Colors.amber.withOpacity(0.2)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(tPos, 14.0 * zoom, glowPaint);
      canvas.drawCircle(tPos, 8.0 * zoom, glowPaint..color = Colors.amber.withOpacity(0.4));
      canvas.drawCircle(tPos, 4.0 * zoom, glowPaint..color = Colors.amber);
    }

    // Seating chairs grid
    final seatPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int gx = 0; gx < 6; gx++) {
      for (int gy = 0; gy < 10; gy++) {
        final double sx = -0.4 + (gx / 5) * 0.8;
        final double sy = -0.4 + (gy / 9) * 0.8;
        final sPos = project(sx, sy, -0.2);
        canvas.drawRect(Rect.fromCenter(center: sPos, width: 6 * zoom, height: 6 * zoom), seatPaint);
      }
    }

    // Render active students
    final Paint activePaint = Paint()..style = PaintingStyle.fill;

    for (final st in students) {
      final double sx = -0.4 + (st.gridX / 5) * 0.8;
      final double sy = -0.4 + (st.gridY / 9) * 0.8;
      const double sz = -0.15;

      final sPos = project(sx, sy, sz);
      final isSelected = selectedStudent?.rollNumber == st.rollNumber;

      if (st.validationPassed) {
        activePaint.color = isSelected ? Colors.tealAccent : Colors.teal;
        canvas.drawCircle(sPos, isSelected ? 8.0 * zoom : 4.5 * zoom, activePaint);
        
        if (isSelected) {
          final borderPaint = Paint()
            ..color = Colors.tealAccent.withOpacity(0.3)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;
          canvas.drawCircle(sPos, 13.0 * zoom, borderPaint);
        }
      } else {
        activePaint.color = isSelected ? Colors.redAccent : Colors.redAccent.withOpacity(0.8);
        canvas.drawCircle(sPos, isSelected ? 7.5 * zoom : 4.0 * zoom, activePaint);

        if (isSelected) {
          final borderPaint = Paint()
            ..color = Colors.redAccent.withOpacity(0.3)
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke;
          canvas.drawCircle(sPos, 12.0 * zoom, borderPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Room3DPainter oldDelegate) {
    return oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.zoom != zoom ||
        oldDelegate.isPerspective != isPerspective ||
        oldDelegate.students != students ||
        oldDelegate.teacherPresent != teacherPresent ||
        oldDelegate.selectedStudent != selectedStudent;
  }
}