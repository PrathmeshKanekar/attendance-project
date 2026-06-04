import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smart_campus_app/core/network/api_client.dart';
import 'package:smart_campus_app/core/services/location_service.dart';

class TeacherSessionHeartbeatState {
  final String sessionStatus; // 'active', 'paused', etc.
  final bool isInside;
  final String actionTaken;
  final double distanceToBoundary;
  final String error;
  final bool isTracking;

  TeacherSessionHeartbeatState({
    this.sessionStatus = 'active',
    this.isInside = true,
    this.actionTaken = 'none',
    this.distanceToBoundary = 0.0,
    this.error = '',
    this.isTracking = false,
  });

  TeacherSessionHeartbeatState copyWith({
    String? sessionStatus,
    bool? isInside,
    String? actionTaken,
    double? distanceToBoundary,
    String? error,
    bool? isTracking,
  }) {
    return TeacherSessionHeartbeatState(
      sessionStatus: sessionStatus ?? this.sessionStatus,
      isInside: isInside ?? this.isInside,
      actionTaken: actionTaken ?? this.actionTaken,
      distanceToBoundary: distanceToBoundary ?? this.distanceToBoundary,
      error: error ?? this.error,
      isTracking: isTracking ?? this.isTracking,
    );
  }
}

class TeacherSessionHeartbeatNotifier extends StateNotifier<TeacherSessionHeartbeatState> {
  final ApiClient _api;
  final LocationService _locationService = LocationService();
  Timer? _timer;
  String? _currentSessionId;

  TeacherSessionHeartbeatNotifier(this._api) : super(TeacherSessionHeartbeatState());

  void startHeartbeat(String sessionId) {
    if (_currentSessionId == sessionId && state.isTracking) return;

    stopHeartbeat();
    _currentSessionId = sessionId;
    state = state.copyWith(isTracking: true, error: '');

    // Initial ping
    _sendHeartbeat();

    // Ping every 15 seconds
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _sendHeartbeat();
    });
  }

  void stopHeartbeat() {
    _timer?.cancel();
    _timer = null;
    _currentSessionId = null;
    state = TeacherSessionHeartbeatState(); // Reset
  }

  Future<void> _sendHeartbeat() async {
    if (_currentSessionId == null) return;

    try {
      final position = await _locationService.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final res = await _api.post('/attendance/sessions/$_currentSessionId/teacher-heartbeat/', data: {
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
      });

      if (res.statusCode == 200 && res.data != null) {
        final data = res.data;
        state = state.copyWith(
          sessionStatus: data['session_status'] ?? 'active',
          isInside: data['is_inside'] ?? true,
          actionTaken: data['action_taken'] ?? 'none',
          distanceToBoundary: (data['distance_to_boundary'] as num?)?.toDouble() ?? 0.0,
          error: '',
        );
      } else {
        state = state.copyWith(error: 'Failed to report teacher presence.');
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final teacherSessionHeartbeatProvider =
    StateNotifierProvider<TeacherSessionHeartbeatNotifier, TeacherSessionHeartbeatState>((ref) {
  final api = ref.watch(apiClientProvider);
  return TeacherSessionHeartbeatNotifier(api);
});
