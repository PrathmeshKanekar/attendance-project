
import 'package:equatable/equatable.dart';

enum AttendanceStep {
  sessionCheck,
  deviceSecurity,
  gpsValidation,
  livenessDetection,
  faceMatch,
  finalSubmission,
  success
}

enum StepStatus { pending, processing, success, failed }

class AttendanceState extends Equatable {
  final AttendanceStep currentStep;
  final Map<AttendanceStep, StepStatus> stepStatuses;
  final String? errorMessage;
  final double gpsAccuracy;
  final double distanceToRoom;
  final int blinkCount;
  final bool isInsideRoom;
  final double? lat;
  final double? lng;
  final double? altitude;
  final String? deviceId;
  final Map<String, dynamic> sessionData;

  const AttendanceState({
    this.currentStep = AttendanceStep.sessionCheck,
    this.stepStatuses = const {
      AttendanceStep.sessionCheck: StepStatus.pending,
      AttendanceStep.deviceSecurity: StepStatus.pending,
      AttendanceStep.gpsValidation: StepStatus.pending,
      AttendanceStep.livenessDetection: StepStatus.pending,
      AttendanceStep.faceMatch: StepStatus.pending,
      AttendanceStep.finalSubmission: StepStatus.pending,
    },
    this.errorMessage,
    this.gpsAccuracy = 0.0,
    this.distanceToRoom = 0.0,
    this.blinkCount = 0,
    this.isInsideRoom = false,
    this.lat,
    this.lng,
    this.altitude,
    this.deviceId,
    this.sessionData = const {},
  });

  AttendanceState copyWith({
    AttendanceStep? currentStep,
    Map<AttendanceStep, StepStatus>? stepStatuses,
    String? errorMessage,
    double? gpsAccuracy,
    double? distanceToRoom,
    int? blinkCount,
    bool? isInsideRoom,
    double? lat,
    double? lng,
    double? altitude,
    String? deviceId,
    Map<String, dynamic>? sessionData,
  }) {
    return AttendanceState(
      currentStep: currentStep ?? this.currentStep,
      stepStatuses: stepStatuses ?? this.stepStatuses,
      errorMessage: errorMessage,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      distanceToRoom: distanceToRoom ?? this.distanceToRoom,
      blinkCount: blinkCount ?? this.blinkCount,
      isInsideRoom: isInsideRoom ?? this.isInsideRoom,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      altitude: altitude ?? this.altitude,
      deviceId: deviceId ?? this.deviceId,
      sessionData: sessionData ?? this.sessionData,
    );
  }

  @override
  List<Object?> get props => [
        currentStep,
        stepStatuses,
        errorMessage,
        gpsAccuracy,
        distanceToRoom,
        blinkCount,
        isInsideRoom,
        lat,
        lng,
        altitude,
        deviceId,
        sessionData,
      ];
}
