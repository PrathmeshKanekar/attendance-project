// lib/features/mark_attendance/presentation/cubit/attendance_cubit.dart
// ─────────────────────────────────────────────────────────────────────────────
// FIXES IN THIS FILE:
//   1. Null-safety: bestPos declared as Position? but accessed without ?.
//      Fixed by using a non-nullable local after the null guard.
//   2. Multi-attempt GPS loop replaced with continuous stream subscription.
//   3. Geofence checks migrated to client side via geofence_utils and parsePolygonFromRoom.
//   4. Added final geofence confirmation at moment of tap.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:dartz/dartz.dart';
import 'package:smart_campus_app/core/services/location_service.dart';
import 'package:smart_campus_app/core/services/device_service.dart';
import 'package:smart_campus_app/features/mark_attendance/domain/repositories/i_attendance_repository.dart';
import 'package:smart_campus_app/features/mark_attendance/presentation/cubit/attendance_state.dart';
import 'package:smart_campus_app/utils/geofence_utils.dart';

class AttendanceCubit extends Cubit<AttendanceState> {
  final IAttendanceRepository _repository;
  StreamSubscription<Position>? _positionStreamSubscription;
  List<LatLng> _roomPolygon = [];

  AttendanceCubit(this._repository) : super(const AttendanceState());

  void initSession(Map<String, dynamic> session) {
    if (isClosed) return;
    emit(state.copyWith(sessionData: session));
    _loadRoomAndStartFlow(session);
  }

  Future<void> _loadRoomAndStartFlow(Map<String, dynamic> session) async {
    final roomId = session['virtual_room']?.toString();
    if (roomId != null) {
      final res = await _repository.getVirtualRoom(roomId);
      res.fold(
        (err) {
          debugPrint('Error fetching virtual room corners: $err');
        },
        (roomData) {
          _roomPolygon = parsePolygonFromRoom(roomData);
          debugPrint('Loaded room polygon with ${_roomPolygon.length} corners');
        },
      );
    }
    await _startVerificationFlow();
  }

  Future<void> _startVerificationFlow() async {
    await _validateSession();
    if (isClosed) return;
    if (state.stepStatuses[AttendanceStep.sessionCheck] != StepStatus.success) return;

    await _validateDevice();
    if (isClosed) return;
    if (state.stepStatuses[AttendanceStep.deviceSecurity] != StepStatus.success) return;

    await _validateGeo();
  }

  @override
  Future<void> close() {
    _positionStreamSubscription?.cancel();
    return super.close();
  }

  // ── Step 1: Session validity ──────────────────────────────────────────────
  Future<void> _validateSession() async {
    if (isClosed) return;
    _updateStep(AttendanceStep.sessionCheck, StepStatus.processing);

    final sessionId = state.sessionData['id']?.toString();
    if (sessionId == null) {
      _failStep(AttendanceStep.sessionCheck, 'Invalid session data.');
      return;
    }

    final res = await _repository.validateSession(sessionId);
    if (isClosed) return;

    res.fold(
      (err) => _failStep(AttendanceStep.sessionCheck, err),
      (_) => _updateStep(AttendanceStep.sessionCheck, StepStatus.success),
    );
  }

  // ── Step 2: Device fingerprint ────────────────────────────────────────────
  Future<void> _validateDevice() async {
    if (isClosed) return;
    _updateStep(AttendanceStep.deviceSecurity, StepStatus.processing);
    try {
      final deviceId = await DeviceService.getDeviceId();

      if (isClosed) return;
      emit(state.copyWith(deviceId: deviceId));
      _updateStep(AttendanceStep.deviceSecurity, StepStatus.success);
    } catch (e) {
      if (isClosed) return;
      _failStep(AttendanceStep.deviceSecurity, 'Security check failed: $e');
    }
  }

  // ── Step 3: GPS + Geofence ────────────────────────────────────────────────
  Future<void> _validateGeo() async {
    if (isClosed) return;
    _updateStep(AttendanceStep.gpsValidation, StepStatus.processing);

    try {
      // Check permissions first
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          _failStep(AttendanceStep.gpsValidation, 'Location permission denied.');
          return;
        }
      }

      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        emit(state.copyWith(locationErrorType: LocationErrorType.serviceDisabled));
        _failStep(AttendanceStep.gpsValidation, 'GPS location services are disabled.');
        return;
      }

      // Cancel previous subscription if any
      await _positionStreamSubscription?.cancel();

      // Configure stream settings
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      );

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position pos) {
          _handleLivePositionUpdate(pos);
        },
        onError: (error) {
          _failStep(AttendanceStep.gpsValidation, 'GPS Error: ${error.toString()}');
        },
      );
    } catch (e) {
      if (isClosed) return;
      _failStep(AttendanceStep.gpsValidation, 'GPS Error: ${e.toString()}');
    }
  }

  void _handleLivePositionUpdate(Position pos) {
    if (isClosed) return;

    final studentPt = LatLng(pos.latitude, pos.longitude);
    final isInside = isPointInsidePolygon(studentPt, _roomPolygon);
    final distanceToBoundary = distanceToPolygonBoundary(studentPt, _roomPolygon);

    emit(state.copyWith(
      lat: pos.latitude,
      lng: pos.longitude,
      altitude: pos.altitude,
      gpsAccuracy: pos.accuracy,
      isInsideRoom: isInside && pos.accuracy <= 15.0,
      distanceToRoom: distanceToBoundary,
    ));

    if (isInside && pos.accuracy <= 15.0) {
      _updateStep(AttendanceStep.gpsValidation, StepStatus.success);
      if (state.currentStep == AttendanceStep.gpsValidation) {
        emit(state.copyWith(currentStep: AttendanceStep.livenessDetection));
      }
    } else {
      _updateStep(AttendanceStep.gpsValidation, StepStatus.processing);
      if (state.currentStep != AttendanceStep.gpsValidation &&
          state.currentStep != AttendanceStep.finalSubmission &&
          state.currentStep != AttendanceStep.success) {
        emit(state.copyWith(currentStep: AttendanceStep.gpsValidation));
      }
    }
  }

  // ── Step 4: Liveness ──────────────────────────────────────────────────────
  void onBlinkDetected(int count) {
    if (isClosed) return;
    emit(state.copyWith(blinkCount: count));
    if (count >= 3 &&
        state.stepStatuses[AttendanceStep.livenessDetection] != StepStatus.success) {
      _updateStep(AttendanceStep.livenessDetection, StepStatus.success);
      emit(state.copyWith(
        currentStep: AttendanceStep.faceMatch,
        faceGuidance: 'Liveness Verified!',
      ));
    }
  }

  void updateFaceGuidance(String? guidance, bool isCentered) {
    if (isClosed) return;
    if (state.faceGuidance == guidance && state.isFaceCentered == isCentered) return;
    emit(state.copyWith(faceGuidance: guidance, isFaceCentered: isCentered));
  }

  // ── Step 5: Face match ────────────────────────────────────────────────────
  Future<void> onFaceMatched() async {
    if (isClosed) return;
    _updateStep(AttendanceStep.faceMatch, StepStatus.processing);
    await Future.delayed(const Duration(seconds: 1));
    if (isClosed) return;
    _updateStep(AttendanceStep.faceMatch, StepStatus.success);
    emit(state.copyWith(currentStep: AttendanceStep.finalSubmission));
  }

  // ── Step 6: Final submission ──────────────────────────────────────────────
  Future<void> submitAttendance(
      String faceImageBase64, Map<String, dynamic> sensors) async {
    if (isClosed) return;
    _updateStep(AttendanceStep.finalSubmission, StepStatus.processing);

    if (state.deviceId == null) {
      _failStep(AttendanceStep.finalSubmission,
          'Missing device ID. Please restart verification.');
      return;
    }

    // Run ONE FINAL geofence check at moment of tap
    try {
      final finalPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );

      final studentPt = LatLng(finalPos.latitude, finalPos.longitude);
      final isInside = isPointInsidePolygon(studentPt, _roomPolygon);
      final distBoundary = distanceToPolygonBoundary(studentPt, _roomPolygon);

      // Emit new values so they are displayed and saved
      emit(state.copyWith(
        lat: finalPos.latitude,
        lng: finalPos.longitude,
        altitude: finalPos.altitude,
        gpsAccuracy: finalPos.accuracy,
        isInsideRoom: isInside && finalPos.accuracy <= 15.0,
        distanceToRoom: distBoundary,
      ));

      if (finalPos.accuracy > 15.0) {
        _failStep(AttendanceStep.finalSubmission,
            'Final verification failed: GPS accuracy is too low (±${finalPos.accuracy.toStringAsFixed(1)}m, required ≤ 15m). Please try again.');
        return;
      }

      if (!isInside) {
        _failStep(AttendanceStep.finalSubmission,
            'Final verification failed: You are physically outside the classroom boundary. Distance: ${distBoundary.toStringAsFixed(1)}m.');
        return;
      }
    } catch (e) {
      // Fallback to last streamed position if current position fetch fails
      debugPrint('Error getting final position on tap: $e. Falling back to last streamed position.');
      if (state.lat == null || state.lng == null) {
        _failStep(AttendanceStep.finalSubmission,
            'Could not acquire location. Please try again.');
        return;
      }
      
      final studentPt = LatLng(state.lat!, state.lng!);
      final isInside = isPointInsidePolygon(studentPt, _roomPolygon);
      if (!isInside || state.gpsAccuracy > 15.0) {
        _failStep(AttendanceStep.finalSubmission,
            'Final verification failed: Outside boundary or poor accuracy.');
        return;
      }
    }

    final res = await _repository.markAttendance(
      sessionId: state.sessionData['id'].toString(),
      faceImageBase64: faceImageBase64,
      lat: state.lat!,
      lng: state.lng!,
      altitude: state.altitude ?? 0.0,
      deviceId: state.deviceId!,
      blinkCount: state.blinkCount,
      accuracy: state.gpsAccuracy,
      extraSensors: sensors,
    );

    if (isClosed) return;

    bool isDeviceError = false;
    res.fold(
      (err) {
        final lowerErr = err.toLowerCase();
        if (lowerErr.contains('device') && 
            (lowerErr.contains('not registered') || lowerErr.contains('register your device'))) {
          isDeviceError = true;
        }
      },
      (_) {},
    );

    if (isDeviceError) {
      debugPrint('AttendanceCubit: Device validation error detected. Triggering auto device recovery...');
      final recoveryRes = await reRegisterDevice();
      if (isClosed) return;

      bool recoverySuccess = false;
      recoveryRes.fold(
        (recErr) {
          debugPrint('AttendanceCubit: Auto device registration recovery failed: $recErr');
        },
        (recData) {
          recoverySuccess = true;
          debugPrint('AttendanceCubit: Auto device registration recovery successful: $recData');
        },
      );

      if (recoverySuccess) {
        debugPrint('AttendanceCubit: Retrying attendance marking with newly registered device...');
        final retryRes = await _repository.markAttendance(
          sessionId: state.sessionData['id'].toString(),
          faceImageBase64: faceImageBase64,
          lat: state.lat!,
          lng: state.lng!,
          altitude: state.altitude ?? 0.0,
          deviceId: state.deviceId!,
          blinkCount: state.blinkCount,
          accuracy: state.gpsAccuracy,
          extraSensors: sensors,
        );

        if (isClosed) return;

        retryRes.fold(
          (err) => _failStep(AttendanceStep.finalSubmission, err),
          (_) {
            _updateStep(AttendanceStep.finalSubmission, StepStatus.success);
            emit(state.copyWith(currentStep: AttendanceStep.success));
          },
        );
        return;
      }
    }

    res.fold(
      (err) => _failStep(AttendanceStep.finalSubmission, err),
      (_) {
        _updateStep(AttendanceStep.finalSubmission, StepStatus.success);
        emit(state.copyWith(currentStep: AttendanceStep.success));
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _updateStep(AttendanceStep step, StepStatus status) {
    if (isClosed) return;
    final newStatuses = Map<AttendanceStep, StepStatus>.from(state.stepStatuses);
    newStatuses[step] = status;
    emit(state.copyWith(stepStatuses: newStatuses));
  }

  void _failStep(AttendanceStep step, String error) {
    if (isClosed) return;
    final newStatuses = Map<AttendanceStep, StepStatus>.from(state.stepStatuses);
    newStatuses[step] = StepStatus.failed;
    emit(state.copyWith(stepStatuses: newStatuses, errorMessage: error));
  }

  Future<Either<String, Map<String, dynamic>>> reRegisterDevice() async {
    try {
      final deviceId = await DeviceService.getDeviceId();
      String deviceName = "Unknown Device";
      String platform = "other";
      
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
          platform = 'android';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceName = iosInfo.name;
          platform = 'ios';
        }
      } catch (_) {}

      final res = await _repository.refreshDeviceBinding(
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
      );
      
      return res;
    } catch (e) {
      return Left(e.toString());
    }
  }
}