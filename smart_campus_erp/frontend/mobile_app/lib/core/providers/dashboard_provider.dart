import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';

class DashboardSummary {
  final int collegesCount;
  final int usersCount;
  final int departmentsCount;
  final int studentsCount;
  final int staffCount;
  final int sessionsCount;
  final double avgAttendance;

  DashboardSummary({
    required this.collegesCount,
    required this.usersCount,
    required this.departmentsCount,
    required this.studentsCount,
    required this.staffCount,
    required this.sessionsCount,
    required this.avgAttendance,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      collegesCount: json['colleges_count'] ?? 0,
      usersCount: json['users_count'] ?? 0,
      departmentsCount: json['departments_count'] ?? 0,
      studentsCount: json['students_count'] ?? 0,
      staffCount: json['staff_count'] ?? 0,
      sessionsCount: json['sessions_count'] ?? 0,
      avgAttendance: (json['avg_attendance'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final res = await apiClient.get('/api/reports/dashboard-summary/');
  return DashboardSummary.fromJson(res.data as Map<String, dynamic>);
});
