import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

// ── Departments ────────────────────────────────────────────
final departmentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/departments/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── Courses ────────────────────────────────────────────────
final coursesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/courses/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── Academic Years ─────────────────────────────────────────
final academicYearsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/academic-years/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── Divisions ──────────────────────────────────────────────
final divisionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/divisions/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── Subjects ───────────────────────────────────────────────
final subjectsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/subjects/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── Allocations ────────────────────────────────────────────
final allocationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/allocations/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── Teachers list (for allocation picker) ─────────────────
final teachersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/auth/users/', params: {
    'role': 'teacher', 'is_approved': 'true',
  });
  if (res.data is Map && res.data.containsKey('users')) {
    return List<Map<String, dynamic>>.from(res.data['users'] as List);
  } else if (res.data is Map && res.data.containsKey('results')) {
    return List<Map<String, dynamic>>.from(res.data['results'] as List);
  } else if (res.data is List) {
    return List<Map<String, dynamic>>.from(res.data as List);
  }
  return [];
});

// ── Students list ─────────────────────────────────────────
final studentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/students/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── Principal existence check ──────────────────────────────
final principalExistsProvider = FutureProvider<bool>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/auth/users/', params: {
      'role': 'principal',
      'is_approved': 'true',
      'is_active': 'true',
    });
    
    if (res.data is Map && res.data.containsKey('users')) {
      final users = res.data['users'] as List;
      return users.isNotEmpty;
    } else if (res.data is List) {
      return res.data.isNotEmpty;
    }
    return false;
  } catch (e) {
    return false;
  }
});
