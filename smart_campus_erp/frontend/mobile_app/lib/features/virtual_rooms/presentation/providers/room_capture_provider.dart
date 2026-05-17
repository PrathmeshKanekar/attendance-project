// presentation/providers/room_capture_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// Sequential capture state tracking for walk-around room initialization.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/spatial_data.dart';
import '../../../../core/services/spatial_sensor_service.dart';
import '../../utils/spatial_engine.dart';
import 'virtual_room_providers.dart';

class RoomCaptureState {
  final int currentCorner;
  final bool isCapturing;
  final List<SpatialData> capturedCorners;
  final String? error;
  final bool isComplete;
  final SpatialData? currentPosition;
  final double? distanceToLastCorner;
  final bool positionUpdated;

  RoomCaptureState({
    this.currentCorner = 1,
    this.isCapturing = false,
    this.capturedCorners = const [],
    this.error,
    this.isComplete = false,
    this.currentPosition,
    this.distanceToLastCorner,
    this.positionUpdated = false,
  });

  RoomCaptureState copyWith({
    int? currentCorner,
    bool? isCapturing,
    List<SpatialData>? capturedCorners,
    String? error,
    bool? isComplete,
    SpatialData? currentPosition,
    double? distanceToLastCorner,
    bool? positionUpdated,
  }) => RoomCaptureState(
    currentCorner: currentCorner ?? this.currentCorner,
    isCapturing: isCapturing ?? this.isCapturing,
    capturedCorners: capturedCorners ?? this.capturedCorners,
    error: error,
    isComplete: isComplete ?? this.isComplete,
    currentPosition: currentPosition ?? this.currentPosition,
    distanceToLastCorner: distanceToLastCorner ?? this.distanceToLastCorner,
    positionUpdated: positionUpdated ?? this.positionUpdated,
  );
}

class RoomCaptureNotifier extends StateNotifier<RoomCaptureState> {
  final Ref _ref;
  final SpatialSensorService _sensors;
  StreamSubscription<SpatialData>? _sensorSub;

  RoomCaptureNotifier(this._ref, this._sensors) : super(RoomCaptureState()) {
    _sensors.startListening();
    _startPositionStream();
  }

  void _startPositionStream() {
    _sensorSub?.cancel();
    _sensorSub = _sensors.getSpatialDataStream().listen((data) {
      double? distance;
      if (state.capturedCorners.isNotEmpty) {
        final last = state.capturedCorners.last;
        distance = haversineDistance(
          last.latitude,
          last.longitude,
          data.latitude,
          data.longitude,
        );
      }
      state = state.copyWith(
        currentPosition: data,
        distanceToLastCorner: distance,
        positionUpdated: !state.positionUpdated,
      );
    }, onError: (err) {
      state = state.copyWith(error: "GPS Stream Error: $err");
    });
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    _sensors.stopListening();
    super.dispose();
  }

  Future<void> captureCorner(String roomId) async {
    if (state.isCapturing) return;

    state = state.copyWith(isCapturing: true, error: null);

    // 1. Collect 5 live GPS samples over the stream
    final List<SpatialData> samples = [];
    final completer = Completer<List<SpatialData>>();
    StreamSubscription<SpatialData>? tempSub;

    tempSub = _sensors.getSpatialDataStream().listen((sample) {
      samples.add(sample);
      state = state.copyWith(
        isCapturing: true,
        error: "Stabilizing coordinates... Sample ${samples.length}/5 (Accuracy: ${sample.accuracy.toStringAsFixed(1)}m)",
      );
      if (samples.length >= 5) {
        tempSub?.cancel();
        completer.complete(samples);
      }
    }, onError: (err) {
      tempSub?.cancel();
      completer.completeError(err);
    });

    List<SpatialData> collected;
    try {
      collected = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          tempSub?.cancel();
          if (samples.isNotEmpty) {
            return samples;
          }
          throw TimeoutException("GPS stabilization timed out. Standing in a clearer area helps.");
        },
      );
    } catch (e) {
      state = state.copyWith(isCapturing: false, error: e.toString());
      return;
    }

    if (collected.isEmpty) {
      state = state.copyWith(isCapturing: false, error: "No GPS samples received. Please try again.");
      return;
    }

    // 2. Calculate average latitude, longitude, altitude, and accuracy
    double sumLat = 0.0;
    double sumLng = 0.0;
    double sumAlt = 0.0;
    double sumAcc = 0.0;
    for (final s in collected) {
      sumLat += s.latitude;
      sumLng += s.longitude;
      sumAlt += s.altitude;
      sumAcc += s.accuracy;
    }
    final avgLat = sumLat / collected.length;
    final avgLng = sumLng / collected.length;
    final avgAlt = sumAlt / collected.length;
    final avgAcc = sumAcc / collected.length;

    // 3. Evaluate stability across samples (max difference <= 0.0002 deg)
    double minLat = collected.first.latitude;
    double maxLat = collected.first.latitude;
    double minLng = collected.first.longitude;
    double maxLng = collected.first.longitude;
    for (final s in collected) {
      if (s.latitude < minLat) minLat = s.latitude;
      if (s.latitude > maxLat) maxLat = s.latitude;
      if (s.longitude < minLng) minLng = s.longitude;
      if (s.longitude > maxLng) maxLng = s.longitude;
    }
    final isStable = (maxLat - minLat).abs() < 0.0002 && (maxLng - minLng).abs() < 0.0002;

    // 4. Smart Adaptive GPS rules: Outdoor <= 20m, Indoor <= 80m with stability check
    bool isAllowed = false;
    if (avgAcc <= 20.0) {
      isAllowed = true;
    } else if (avgAcc <= 80.0 && isStable) {
      isAllowed = true;
    }

    if (!isAllowed) {
      state = state.copyWith(
        isCapturing: false,
        error: avgAcc > 80.0
            ? "Averaged GPS accuracy too poor (${avgAcc.toStringAsFixed(1)}m). Limit is 80m."
            : "GPS signals unstable (${avgAcc.toStringAsFixed(1)}m). Please hold the device steady.",
      );
      return;
    }

    // 5. Duplicate Check + Distance check (Threshold: 1.5 meters)
    if (state.capturedCorners.isNotEmpty) {
      final last = state.capturedCorners.last;
      final dist = haversineDistance(
        last.latitude,
        last.longitude,
        avgLat,
        avgLng,
      );

      if (dist < 1.5) {
        state = state.copyWith(
          isCapturing: false,
          error: "Move to a different physical corner before capturing (dist: ${dist.toStringAsFixed(1)}m).",
        );
        return;
      }

      for (int i = 0; i < state.capturedCorners.length; i++) {
        final prev = state.capturedCorners[i];
        final distToPrev = haversineDistance(
          prev.latitude,
          prev.longitude,
          avgLat,
          avgLng,
        );
        if (distToPrev < 1.5) {
          state = state.copyWith(
            isCapturing: false,
            error: "Corner duplicate detected. Move to a new corner.",
          );
          return;
        }
      }
    }

    try {
      final representative = collected.last;
      final payload = {
        'lat': avgLat,
        'lng': avgLng,
        'altitude': avgAlt,
        'accuracy': avgAcc,
        'heading': representative.heading,
        'accelerometer': representative.accelerometer,
        'gyroscope': representative.gyroscope,
        'magnetic_field': representative.magneticField,
      };

      final res = await _ref.read(cornerCaptureProvider.notifier).captureCorner(
        roomId: roomId,
        cornerIndex: state.currentCorner,
        payload: payload,
      );

      if (res == null) {
        throw _ref.read(cornerCaptureProvider).error ?? 'Corner capture refused by spatial gateway.';
      }

      final bool isComplete = res['room_finalized'] == true || res['corner_count'] == 4;
      final localModel = SpatialData(
        latitude: avgLat,
        longitude: avgLng,
        altitude: avgAlt,
        heading: representative.heading,
        accuracy: avgAcc,
        accelerometer: representative.accelerometer,
        gyroscope: representative.gyroscope,
        magneticField: representative.magneticField,
        timestamp: DateTime.now(),
      );

      final newCorners = [...state.capturedCorners, localModel];

      if (isComplete) {
        state = state.copyWith(
          isCapturing: false,
          capturedCorners: newCorners,
          isComplete: true,
        );
        _ref.invalidate(roomDetailProvider(roomId));
      } else {
        state = state.copyWith(
          isCapturing: false,
          capturedCorners: newCorners,
          currentCorner: state.currentCorner + 1,
        );
      }
    } catch (e) {
      state = state.copyWith(isCapturing: false, error: e.toString());
    }
  }

  void undoLastCorner() {
    if (state.capturedCorners.isEmpty) return;
    final List<SpatialData> updated = List.from(state.capturedCorners)..removeLast();
    state = RoomCaptureState(
      currentCorner: state.currentCorner > 1 ? state.currentCorner - 1 : 1,
      capturedCorners: updated,
      isCapturing: false,
      isComplete: false,
      currentPosition: state.currentPosition,
    );
  }

  void reset() {
    state = RoomCaptureState();
  }
}

final roomCaptureProvider = StateNotifierProvider.autoDispose<RoomCaptureNotifier, RoomCaptureState>((ref) {
  return RoomCaptureNotifier(ref, SpatialSensorService());
});
