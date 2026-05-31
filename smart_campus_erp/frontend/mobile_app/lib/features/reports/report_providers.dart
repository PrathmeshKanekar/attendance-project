import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/providers/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: safely extract a list from any response shape
// ─────────────────────────────────────────────────────────────────────────────
List<Map<String, dynamic>> _extractList(dynamic raw, List<String> keys) {
  if (raw == null) return [];
  if (raw is List) {
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  if (raw is Map) {
    for (final k in keys) {
      final v = raw[k];
      if (v is List) {
        return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
  }
  return [];
}

// ─────────────────────────────────────────────────────────────────────────────
// STUDENT — my attendance
// GET /api/reports/student/my-attendance/
// Backend returns: { "success": true, "data": { "subjects": [...] } }
// ─────────────────────────────────────────────────────────────────────────────
final studentMyAttendanceProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return [];

  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/reports/student/my-attendance/');
  final raw = res.data;

  // Backend: { data: { subjects: [...] } }  OR  { subjects: [...] }  OR  [...]
  if (raw is List) {
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  if (raw is Map) {
    final inner = raw['data'] ?? raw;
    final list = (inner is Map ? inner['subjects'] : null) ??
        (raw['subjects']) ??
        (raw['data'] is List ? raw['data'] : null) ??
        [];
    if (list is List) {
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  }
  return [];
});

// ─────────────────────────────────────────────────────────────────────────────
// TEACHER — attendance summary for a subject allocation
// GET /api/reports/attendance-summary/?allocation_id=...&start_date=...&end_date=...
// Backend returns: { "data": { "summary": {...}, "students": [...], "allocation": {...} } }
// ─────────────────────────────────────────────────────────────────────────────
final attendanceSummaryProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, String>>(
  (ref, params) async {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) return {};

    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/reports/attendance-summary/', params: params);
    final raw = res.data;

    if (raw is! Map) return {};

    // Backend wraps in 'data' key: { success, data: { summary, students, allocation } }
    final inner = (raw['data'] is Map) ? raw['data'] as Map : raw;

    return {
      'summary'   : Map<String, dynamic>.from(inner['summary'] as Map? ?? {}),
      'students'  : (inner['students'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      'allocation': Map<String, dynamic>.from(inner['allocation'] as Map? ?? {}),
    };
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// TEACHER — session history
// GET /api/reports/teacher/session-history/
// Backend returns: { "data": [...] }  OR  [...]
// ─────────────────────────────────────────────────────────────────────────────
final teacherSessionHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>(
  (ref, allocationId) async {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) return [];

    final api    = ref.read(apiClientProvider);
    final params = <String, dynamic>{'limit': '30'};
    if (allocationId != null && allocationId.isNotEmpty) {
      params['allocation_id'] = allocationId;
    }

    final res = await api.get('/api/reports/teacher/session-history/',
        params: params);

    return _extractList(res.data, ['data', 'results', 'sessions']);
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// DEFAULTERS
// GET /api/reports/defaulters/
// Backend returns: { "data": { "defaulters": [...], "count": int, "threshold": float } }
// ─────────────────────────────────────────────────────────────────────────────
final defaultersProvider =
    FutureProvider.family<Map<String, dynamic>, Map<String, String>>(
  (ref, params) async {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) return {};

    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/reports/defaulters/', params: params);
    final raw = res.data;

    if (raw is! Map) return {};
    final inner = (raw['data'] is Map) ? raw['data'] as Map : raw;
    return {
      'defaulters': (inner['defaulters'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      'count'    : inner['count'] ?? 0,
      'threshold': inner['threshold'] ?? 75.0,
      'subject_name': inner['subject_name'] ?? '',
    };
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// COLLEGE OVERVIEW (Principal / HOD)
// GET /api/reports/college/overview/
// ─────────────────────────────────────────────────────────────────────────────
final collegeOverviewProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return {};

  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/reports/college/overview/');
  final raw = res.data;

  if (raw is! Map) return {};
  final inner = raw['data'] ?? raw;
  if (inner is Map) return Map<String, dynamic>.from(inner);
  return {};
});

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD SUMMARY CARDS
// GET /api/reports/summary/
// Backend returns: { "data": [ { title, value, trend, is_positive }, ... ] }
// ─────────────────────────────────────────────────────────────────────────────
final reportDashboardSummaryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return [];

  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/reports/summary/');

  return _extractList(res.data, ['data', 'summaries', 'results']);
});

// ─────────────────────────────────────────────────────────────────────────────
// ATTENDANCE TRENDS CHART
// GET /api/reports/trends/?days=30
// Backend returns: { "data": [ { date, percentage, present, total }, ... ] }
// ─────────────────────────────────────────────────────────────────────────────
final attendanceTrendsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>(
  (ref, days) async {
    final authState = ref.watch(authProvider);
    if (authState is! AuthSuccess) return [];

    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/reports/trends/',
        params: {'days': '$days'});

    return _extractList(res.data, ['data', 'trends', 'results']);
  },
);