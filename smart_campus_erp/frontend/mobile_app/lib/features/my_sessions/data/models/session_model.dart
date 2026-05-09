
import '../../domain/entities/session_entity.dart';

class SessionModel extends SessionEntity {
  const SessionModel({
    required super.id,
    required super.sessionCode,
    required super.status,
    required super.subjectName,
    required super.subjectCode,
    required super.divisionName,
    required super.yearOfStudy,
    super.roomName,
    required super.totalStudents,
    required super.presentCount,
    required super.absentCount,
    required super.attendancePct,
    required super.scheduledStart,
    required super.scheduledEnd,
    super.actualStart,
    super.actualEnd,
    super.durationMinutes,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    // Backend has two response formats:
    // MySessionsView (manual) uses 'year_of_study'
    // AttendanceSessionSerializer uses 'division_year'
    final yearOfStudy = json['year_of_study'] as int?
        ?? json['division_year'] as int?
        ?? 1;

    return SessionModel(
      id: json['id']?.toString() ?? '',
      sessionCode: json['session_code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'scheduled',
      subjectName: json['subject_name']?.toString() ?? 'Subject',
      subjectCode: json['subject_code']?.toString() ?? '',
      divisionName: json['division_name']?.toString() ?? '',
      yearOfStudy: yearOfStudy,
      roomName: json['room_name']?.toString(),
      totalStudents: json['total_students'] as int? ?? 0,
      presentCount: json['present_count'] as int? ?? 0,
      absentCount: json['absent_count'] as int?
          ?? (json['total_students'] as int? ?? 0) - (json['present_count'] as int? ?? 0),
      attendancePct: (json['attendance_pct'] as num? ?? 0.0).toDouble(),
      scheduledStart: json['scheduled_start'] != null
          ? DateTime.parse(json['scheduled_start'])
          : DateTime.now(),
      scheduledEnd: json['scheduled_end'] != null
          ? DateTime.parse(json['scheduled_end'])
          : DateTime.now().add(const Duration(hours: 1)),
      actualStart: json['actual_start'] != null ? DateTime.parse(json['actual_start']) : null,
      actualEnd: json['actual_end'] != null ? DateTime.parse(json['actual_end']) : null,
      durationMinutes: json['duration_minutes'] as int?,
    );
  }
}
