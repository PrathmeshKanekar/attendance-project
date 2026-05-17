import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

// Helper to handle both List and Paginated responses
List<Map<String, dynamic>> _parseList(dynamic data, {String? key}) {
  if (data is List) {
    return List<Map<String, dynamic>>.from(data);
  }
  if (data is Map) {
    if (key != null && data.containsKey(key)) {
      return List<Map<String, dynamic>>.from(data[key] as List);
    }
    if (data.containsKey('results')) {
      return List<Map<String, dynamic>>.from(data['results'] as List);
    }
    if (data.containsKey('users')) {
      return List<Map<String, dynamic>>.from(data['users'] as List);
    }
  }
  return [];
}

// ── Departments ────────────────────────────────────────────
final departmentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/departments/');
  return _parseList(res.data);
});

// ── Courses ────────────────────────────────────────────────
final coursesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/courses/');
    return _parseList(res.data);
  } on DioException catch (e) {
    if (e.response?.statusCode == 403) return [];
    rethrow;
  }
});

// ── Academic Years ─────────────────────────────────────────
final academicYearsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/academic-years/');
    return _parseList(res.data);
  } on DioException catch (e) {
    if (e.response?.statusCode == 403) return [];
    rethrow;
  }
});

// ── Divisions ──────────────────────────────────────────────
final divisionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/divisions/');
  return _parseList(res.data);
});

// ── Subjects ───────────────────────────────────────────────
final subjectsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/subjects/');
  return _parseList(res.data);
});

// ── Allocations ────────────────────────────────────────────
final allocationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/allocations/');
  return _parseList(res.data);
});

// ── Teachers list (for allocation picker) ─────────────────
final teachersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/auth/users/', params: {
    'role': 'teacher', 'is_approved': 'true',
  });
  return _parseList(res.data, key: 'users');
});

// ── Students list ─────────────────────────────────────────
final studentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/students/');
  return _parseList(res.data);
});

