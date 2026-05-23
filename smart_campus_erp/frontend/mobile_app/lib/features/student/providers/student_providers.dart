import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/auth_provider.dart';
import '../../reports/report_providers.dart';

final studentAttendanceSummaryProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final listAsync = ref.watch(studentMyAttendanceProvider);
  
  return listAsync.when(
    data: (list) {
      int total    = list.length;
      int atRisk   = list.where((s) => (s['percentage'] as num? ?? 0) < 75).length;
      double avg   = total == 0
          ? 0
          : list.fold(0.0, (sum, s) => sum + (s['percentage'] as num? ?? 0)) / total;

      return {
        'total_subjects': total,
        'at_risk'        : atRisk,
        'average_pct'    : avg.toStringAsFixed(1),
        'subjects'       : list,
      };
    },
    loading: () => {'total_subjects': 0, 'at_risk': 0, 'average_pct': '0', 'subjects': []},
    error: (e, _) => throw e,
  );
});

final studentActiveSessionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return [];

  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/attendance/sessions/active/');
    if (res.data is List) {
      return List<Map<String, dynamic>>.from(
        (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    return [];
  } catch (e) {
    rethrow;
  }
});
