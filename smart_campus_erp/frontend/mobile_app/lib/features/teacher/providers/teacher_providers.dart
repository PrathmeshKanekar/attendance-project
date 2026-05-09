
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/auth_provider.dart';

final mySessionsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return {};

  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/attendance/sessions/my/');
  return Map<String, dynamic>.from(res.data as Map);
});

final teacherRoomsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return [];

  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/virtual-rooms/');

    List rawList = [];
    if (res.data is List) {
      rawList = res.data as List;
    } else if (res.data is Map && res.data['results'] != null) {
      rawList = res.data['results'] as List;
    }

    return rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (e) {
    return [];
  }
});

final teacherAllocationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return [];

  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/allocations/my/');

    List rawList = [];
    if (res.data is List) {
      rawList = res.data as List;
    } else if (res.data is Map && res.data['results'] != null) {
      rawList = res.data['results'] as List;
    }

    return rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (e) {
    return [];
  }
});

final sessionLogsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, sessionId) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return {};

  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/attendance/sessions/$sessionId/logs/');
  return Map<String, dynamic>.from(res.data as Map);
});
