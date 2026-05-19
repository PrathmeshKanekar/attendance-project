import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/providers/auth_provider.dart';

// ── Student my attendance ──────────────────────────────────
final studentMyAttendanceProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return [];

  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/reports/student/my-attendance/');
  
  if (res.data == null) return [];
  
  if (res.data is List) {
    return List<Map<String, dynamic>>.from(
      (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  } else if (res.data is Map) {
    final list = res.data['data'] ?? res.data['subjects'] ?? [];
    if (list is List) {
      return List<Map<String, dynamic>>.from(
        list.map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
  }
  return [];
});

// ── College overview (principal/HOD) ──────────────────────
final collegeOverviewProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return {};

  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/reports/college/overview/');
  if (res.data is Map) {
    final map = res.data['data'] ?? res.data;
    return Map<String, dynamic>.from(map as Map);
  }
  return {};
});

// ── Teacher session history ────────────────────────────────
final teacherSessionHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>(
  (ref, allocationId) async {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) return [];

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
    } else if (res.data is Map) {
      final list = res.data['data'] ?? res.data['results'] ?? [];
      if (list is List) {
        return List<Map<String, dynamic>>.from(
          list.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
    }
    return [];
  },
);

// ── Attendance summary (teacher filter) ───────────────────
final attendanceSummaryProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, String>>(
  (ref, params) async {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) return {};

    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/reports/attendance-summary/',
        params: params);
    if (res.data is Map) {
      final map = res.data['data'] ?? res.data;
      return Map<String, dynamic>.from(map as Map);
    }
    return {};
  },
);

// ── Defaulters ────────────────────────────────────────────
final defaultersProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, String>>(
  (ref, params) async {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) return {};

    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/reports/defaulters/', params: params);
    if (res.data is Map) {
      final map = res.data['data'] ?? res.data;
      return Map<String, dynamic>.from(map as Map);
    }
    return {};
  },
);

