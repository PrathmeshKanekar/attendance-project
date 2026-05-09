import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

final studentAttendanceSummaryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final apiClient = ref.read(apiClientProvider);
  final res = await apiClient.get('/api/reports/student/my-attendance/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

final studentActiveSessionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final apiClient = ref.read(apiClientProvider);
  final res = await apiClient.get('/api/attendance/sessions/active/');
  return List<Map<String, dynamic>>.from(res.data as List);
});
