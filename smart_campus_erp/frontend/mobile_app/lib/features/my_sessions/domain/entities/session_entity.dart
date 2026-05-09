
import 'package:equatable/equatable.dart';

class SessionEntity extends Equatable {
  final String id;
  final String sessionCode;
  final String status;
  final String subjectName;
  final String subjectCode;
  final String divisionName;
  final int yearOfStudy;
  final String? roomName;
  final int totalStudents;
  final int presentCount;
  final int absentCount;
  final double attendancePct;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final int? durationMinutes;

  const SessionEntity({
    required this.id,
    required this.sessionCode,
    required this.status,
    required this.subjectName,
    required this.subjectCode,
    required this.divisionName,
    required this.yearOfStudy,
    this.roomName,
    required this.totalStudents,
    required this.presentCount,
    required this.absentCount,
    required this.attendancePct,
    required this.scheduledStart,
    required this.scheduledEnd,
    this.actualStart,
    this.actualEnd,
    this.durationMinutes,
  });

  @override
  List<Object?> get props => [
        id,
        sessionCode,
        status,
        subjectName,
        subjectCode,
        divisionName,
        yearOfStudy,
        roomName,
        totalStudents,
        presentCount,
        absentCount,
        attendancePct,
        scheduledStart,
        scheduledEnd,
        actualStart,
        actualEnd,
        durationMinutes,
      ];
}
