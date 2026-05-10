import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/providers/auth_provider.dart';

// ── Student my attendance ──────────────────────────────────
final studentMyAttendanceProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return [];

  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/reports/student/my-attendance/');
    if (res.data == null) return [];
    
    if (res.data is List) {
      return List<Map<String, dynamic>>.from(
        (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } else if (res.data is Map && res.data['subjects'] != null) {
      return List<Map<String, dynamic>>.from(
        (res.data['subjects'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    return [];
  } catch (e) {
    return [];
  }
});

// ── College overview (principal/HOD) ──────────────────────
final collegeOverviewProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return {};

  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/reports/college/overview/');
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    return {};
  }
});

// ── Teacher session history ────────────────────────────────
final teacherSessionHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>(
  (ref, allocationId) async {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) return [];

    try {
      final api    = ref.read(apiClientProvider);
      final params = <String, dynamic>{'limit': '20'};
      if (allocationId != null) params['allocation_id'] = allocationId;
      final res = await api.get('/api/reports/teacher/session-history/',
          params: params);
      
      if (res.data == null) return [];

      if (res.data is List) {
        return List<Map<String, dynamic>>.from(
          (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      } else if (res.data is Map && res.data['results'] != null) {
        return List<Map<String, dynamic>>.from(
          (res.data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  },
);

// ── Attendance summary (teacher filter) ───────────────────
final attendanceSummaryProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, String>>(
  (ref, params) async {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) return {};

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/api/reports/attendance-summary/',
          params: params);
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      return {};
    }
  },
);

// ── Defaulters ────────────────────────────────────────────
final defaultersProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, String>>(
  (ref, params) async {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) return {};

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/api/reports/defaulters/', params: params);
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      return {};
    }
  },
);
