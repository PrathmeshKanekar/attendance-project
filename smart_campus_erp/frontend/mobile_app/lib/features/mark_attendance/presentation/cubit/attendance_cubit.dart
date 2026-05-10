import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform; // Conditional import for non-web platforms
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smart_campus_app/core/services/location_service.dart';
import 'package:smart_campus_app/features/mark_attendance/domain/repositories/i_attendance_repository.dart';
import 'package:smart_campus_app/features/mark_attendance/presentation/cubit/attendance_state.dart';

class AttendanceCubit extends Cubit<AttendanceState> {
  final IAttendanceRepository _repository;

  AttendanceCubit(this._repository) : super(const AttendanceState());

  void initSession(Map<String, dynamic> session) {
    if (isClosed) return;
    emit(state.copyWith(sessionData: session));
    _startVerificationFlow();
  }

  Future<void> _startVerificationFlow() async {
    // 1. Session Check
    await _validateSession();
    if (isClosed) return;
    if (state.stepStatuses[AttendanceStep.sessionCheck] != StepStatus.success) return;

    // 2. Device Security & ID Capture
    await _validateDevice();
    if (isClosed) return;
    if (state.stepStatuses[AttendanceStep.deviceSecurity] != StepStatus.success) return;

    // 3. GPS & Geo Validation
    await _validateGeo();
  }

  Future<void> _validateSession() async {
    if (isClosed) return;
    _updateStep(AttendanceStep.sessionCheck, StepStatus.processing);
    
    final sessionId = state.sessionData['id']?.toString();
    if (sessionId == null) {
      _failStep(AttendanceStep.sessionCheck, "Invalid session data.");
      return;
    }

    final res = await _repository.validateSession(sessionId);
    if (isClosed) return;

    res.fold(
      (err) => _failStep(AttendanceStep.sessionCheck, err),
      (data) => _updateStep(AttendanceStep.sessionCheck, StepStatus.success),
    );
  }

  Future<void> _validateDevice() async {
    if (isClosed) return;
    _updateStep(AttendanceStep.deviceSecurity, StepStatus.processing);
    try {
      String deviceId = 'unknown';
      final deviceInfo = DeviceInfoPlugin();
      
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        deviceId = 'web-${webInfo.userAgent.hashCode}';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'ios-unknown';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        deviceId = windowsInfo.deviceId;
      }

      if (isClosed) return;
      emit(state.copyWith(deviceId: deviceId));
      _updateStep(AttendanceStep.deviceSecurity, StepStatus.success);
    } catch (e) {
      if (isClosed) return;
      _failStep(AttendanceStep.deviceSecurity, "Security check failed: $e");
    }
  }

  Future<void> _validateGeo() async {
    if (isClosed) return;
    _updateStep(AttendanceStep.gpsValidation, StepStatus.processing);
    try {
      final locService = LocationService();
      final pos = await locService.getCurrentPosition();
      
      if (isClosed) return;

      emit(state.copyWith(
        lat: pos.latitude,
        lng: pos.longitude,
        altitude: pos.altitude,
        gpsAccuracy: pos.accuracy,
      ));

      final sessionId = state.sessionData['id']?.toString() ?? '';
      final res = await _repository.validateGeoLocation(
        lat: pos.latitude,
        lng: pos.longitude,
        altitude: pos.altitude,
        sessionId: sessionId,
        accuracy: pos.accuracy,
      );

      if (isClosed) return;

      res.fold(
        (err) => _failStep(AttendanceStep.gpsValidation, err),
        (geoData) {
          final isInside = geoData['is_inside'] == true;
          final distance = (geoData['distance_from_center'] as num?)?.toDouble() ?? 0;
          final boundary = (geoData['distance_to_boundary'] as num?)?.toDouble() ?? 0;
          final altOk    = geoData['altitude_ok'] == true;
          final radius   = (geoData['room_radius_meters'] as num?)?.toDouble() ?? 30;
          
          emit(state.copyWith(distanceToRoom: distance));

          if (isInside) {
            emit(state.copyWith(
              isInsideRoom: true,
              currentStep: AttendanceStep.livenessDetection,
            ));
            _updateStep(AttendanceStep.gpsValidation, StepStatus.success);
          } else {
            String reason = 'You are outside the classroom boundary.';
            if (!altOk) {
              reason = 'You appear to be on the wrong floor.';
            } else if (boundary > 0) {
              reason = 'You are ${boundary.toStringAsFixed(1)}m outside the '
                       '${radius.toStringAsFixed(0)}m classroom boundary.';
            }
            _failStep(AttendanceStep.gpsValidation, reason);
          }
        },
      );
    } on LocationException catch (e) {
      if (isClosed) return;
      LocationErrorType type = LocationErrorType.other;
      if (e.isServiceDisabled) type = LocationErrorType.serviceDisabled;
      if (e.isPermissionDenied) type = LocationErrorType.permissionDenied;
      if (e.isPermissionPermanentlyDenied) type = LocationErrorType.permissionPermanentlyDenied;
      
      emit(state.copyWith(locationErrorType: type));
      _failStep(AttendanceStep.gpsValidation, e.message);
    } catch (e) {
      if (isClosed) return;
      _failStep(AttendanceStep.gpsValidation, "GPS Error: ${e.toString()}");
    }
  }

  void onBlinkDetected(int count) {
    if (isClosed) return;
    emit(state.copyWith(blinkCount: count));
    if (count >= 3 && state.stepStatuses[AttendanceStep.livenessDetection] != StepStatus.success) {
      _updateStep(AttendanceStep.livenessDetection, StepStatus.success);
      emit(state.copyWith(currentStep: AttendanceStep.faceMatch, faceGuidance: "Liveness Verified!"));
      emit(state.copyWith(currentStep: AttendanceStep.faceMatch));
    }
  }

  void updateFaceGuidance(String? guidance, bool isCentered) {
    if (isClosed) return;
    if (state.faceGuidance == guidance && state.isFaceCentered == isCentered) return;
    emit(state.copyWith(faceGuidance: guidance, isFaceCentered: isCentered));
  }

  Future<void> onFaceMatched() async {
    if (isClosed) return;
    _updateStep(AttendanceStep.faceMatch, StepStatus.processing);
    await Future.delayed(const Duration(seconds: 1)); 
    if (isClosed) return;
    _updateStep(AttendanceStep.faceMatch, StepStatus.success);
    emit(state.copyWith(currentStep: AttendanceStep.finalSubmission));
  }

  Future<void> submitAttendance(String faceImageBase64, Map<String, dynamic> sensors) async {
    if (isClosed) return;
    _updateStep(AttendanceStep.finalSubmission, StepStatus.processing);
    
    if (state.lat == null || state.lng == null || state.deviceId == null) {
      _failStep(AttendanceStep.finalSubmission, "Missing critical data. Please restart verification.");
      return;
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

    res.fold(
      (err) => _failStep(AttendanceStep.finalSubmission, err),
      (success) {
        _updateStep(AttendanceStep.finalSubmission, StepStatus.success);
        emit(state.copyWith(currentStep: AttendanceStep.success));
      },
    );
  }

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
}
