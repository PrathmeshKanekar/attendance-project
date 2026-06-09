import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smart_campus_app/core/network/api_client.dart';
import 'package:smart_campus_app/core/services/location_service.dart';
import 'package:smart_campus_app/core/services/device_service.dart';

class RoomPresenceState {
  final bool isInside;
  final double distanceToBoundary;
  final String validationMode;
  final String error;
  final bool isTracking;

  RoomPresenceState({
    this.isInside = false,
    this.distanceToBoundary = 0.0,
    this.validationMode = 'denied',
    this.error = '',
    this.isTracking = false,
  });

  RoomPresenceState copyWith({
    bool? isInside,
    double? distanceToBoundary,
    String? validationMode,
    String? error,
    bool? isTracking,
  }) {
    return RoomPresenceState(
      isInside: isInside ?? this.isInside,
      distanceToBoundary: distanceToBoundary ?? this.distanceToBoundary,
      validationMode: validationMode ?? this.validationMode,
      error: error ?? this.error,
      isTracking: isTracking ?? this.isTracking,
    );
  }
}

class RoomPresenceNotifier extends StateNotifier<RoomPresenceState> {
  final ApiClient _api;
  final LocationService _locationService = LocationService();
  Timer? _timer;
  String? _currentRoomId;

  RoomPresenceNotifier(this._api) : super(RoomPresenceState());

  void startPresenceTracking(String roomId) {
    if (_currentRoomId == roomId && state.isTracking) return;
    
    stopPresenceTracking();
    _currentRoomId = roomId;
    state = state.copyWith(isTracking: true, error: '');

    // Immediate first ping
    _sendHeartbeat();

    // Periodic ping every 10 seconds
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _sendHeartbeat();
    });
  }

  void stopPresenceTracking() {
    _timer?.cancel();
    _timer = null;
    _currentRoomId = null;
    state = RoomPresenceState(); // reset to default
  }

  Future<void> _sendHeartbeat() async {
    if (_currentRoomId == null) return;

    try {
      // 1. Get current physical location
      final position = await _locationService.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final deviceId = await DeviceService.getDeviceId();

      // 2. POST to presence heartbeat API
      final res = await _api.post('/virtual-rooms/$_currentRoomId/presence/heartbeat/', data: {
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
        'device_id': deviceId,
      });

      if (res.statusCode == 200 && res.data != null) {
        final data = res.data;
        state = state.copyWith(
          isInside: data['is_inside'] ?? false,
          distanceToBoundary: (data['distance_to_boundary'] as num?)?.toDouble() ?? 0.0,
          validationMode: data['validation_mode'] ?? 'denied',
          error: '',
        );
      } else {
        state = state.copyWith(error: 'Failed to update presence status.');
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

final roomPresenceProvider = StateNotifierProvider<RoomPresenceNotifier, RoomPresenceState>((ref) {
  final api = ref.watch(apiClientProvider);
  return RoomPresenceNotifier(api);
});
