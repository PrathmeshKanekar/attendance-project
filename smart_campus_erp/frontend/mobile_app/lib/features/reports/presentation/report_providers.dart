import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// METADATA DRIP DROPDOWN PROVIDERS FOR DYNAMIC FILTERING
// ─────────────────────────────────────────────────────────────────────────────

final academicYearsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/academic/academic-years/');
    if (res.data is List) {
      return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else if (res.data is Map && res.data['data'] is List) {
      return (res.data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  } catch (_) {}
  return [];
});

final departmentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/academic/departments/');
    if (res.data is List) {
      return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else if (res.data is Map && res.data['data'] is List) {
      return (res.data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  } catch (_) {}
  return [];
});

final coursesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/academic/courses/');
    if (res.data is List) {
      return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else if (res.data is Map && res.data['data'] is List) {
      return (res.data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  } catch (_) {}
  return [];
});

final divisionsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/academic/divisions/');
    if (res.data is List) {
      return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else if (res.data is Map && res.data['data'] is List) {
      return (res.data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  } catch (_) {}
  return [];
});

final subjectsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/academic/subjects/');
    if (res.data is List) {
      return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else if (res.data is Map && res.data['data'] is List) {
      return (res.data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  } catch (_) {}
  return [];
});

final myAllocationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/academic/allocations/my/');
    if (res.data is List) {
      return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else if (res.data is Map && res.data['data'] is List) {
      return (res.data['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  } catch (_) {}
  return [];
});
