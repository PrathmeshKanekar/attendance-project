import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/auth_provider.dart';

// ── Teacher's Active & Past Sessions ────────────────────────
// Returns { "sessions": [...], "active_count": X, "total": Y }
final mySessionsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return {'sessions': [], 'active_count': 0, 'total': 0};

  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/attendance/sessions/my/');
    if (res.data == null) return {'sessions': [], 'active_count': 0, 'total': 0};
    
    final data = Map<String, dynamic>.from(res.data as Map);
    return {
      'sessions': data['sessions'] ?? [],
      'active_count': data['active_count'] ?? 0,
      'total': data['total'] ?? 0,
    };
  } catch (e) {
    return {'sessions': [], 'active_count': 0, 'total': 0};
  }
});

// ── My Subject Allocations ──────────────────────────────────
final teacherAllocationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return [];

  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/allocations/my/');
    
    if (res.data == null) return [];

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

// ── Virtual Rooms ───────────────────────────────────────────
final teacherRoomsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return [];

  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/virtual-rooms/');

    if (res.data == null) return [];

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

// ── Session Logs ────────────────────────────────────────────
final sessionLogsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, sessionId) async {
  final authState = ref.watch(authProvider);
  if (authState is! AuthSuccess) return {'logs': [], 'present': 0, 'total': 0};

  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/attendance/sessions/$sessionId/logs/');
    if (res.data == null) return {'logs': [], 'present': 0, 'total': 0};
    
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    return {'logs': [], 'present': 0, 'total': 0};
  }
});


// ── Create/End Session State ───────────────────────────────
abstract class CreateSessionState {}
class CreateSessionIdle    extends CreateSessionState {}
class CreateSessionLoading extends CreateSessionState {}
class CreateSessionSuccess extends CreateSessionState {
  final Map<String, dynamic> session;
  final String message;
  CreateSessionSuccess(this.session, this.message);
}
class CreateSessionError   extends CreateSessionState {
  final String message;
  CreateSessionError(this.message);
}

class CreateSessionNotifier extends StateNotifier<CreateSessionState> {
  final ApiClient _api;
  final Ref _ref;
  CreateSessionNotifier(this._api, this._ref) : super(CreateSessionIdle());

  Future<void> createSession(Map<String, dynamic> body) async {
    if (!mounted) return;
    state = CreateSessionLoading();
    try {
      final res = await _api.post('/api/attendance/sessions/', data: body);
      
      if (!mounted) return;

      // Backend returns flat session data, not nested in 'session' key
      final sessionData = res.data != null 
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      
      // Refresh the dashboard list
      _ref.invalidate(mySessionsProvider);

      state = CreateSessionSuccess(
        sessionData,
        sessionData['message']?.toString() ?? 'Session started successfully.',
      );
    } catch (e) {
      if (!mounted) return;
      state = CreateSessionError(_extractError(e));
    }
  }

  Future<void> endSession(String sessionId) async {
    if (!mounted) return;
    state = CreateSessionLoading();
    try {
      final res = await _api.post('/api/attendance/sessions/$sessionId/end/');
      
      if (!mounted) return;

      // Refresh the dashboard list
      _ref.invalidate(mySessionsProvider);

      state = CreateSessionSuccess(
        {},
        res.data != null && res.data is Map 
            ? res.data['message']?.toString() ?? 'Session ended successfully.'
            : 'Session ended successfully.',
      );
    } catch (e) {
      if (!mounted) return;
      state = CreateSessionError(_extractError(e));
    }
  }

  void reset() {
    if (mounted) state = CreateSessionIdle();
  }

  String _extractError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('"error"')) {
      try {
        final start = msg.indexOf('"error":') + 9;
        final sub   = msg.substring(start);
        final end   = sub.indexOf('"', 1);
        return sub.substring(1, end);
      } catch (_) {}
    }
    return msg;
  }
}

final createSessionProvider = StateNotifierProvider<CreateSessionNotifier, CreateSessionState>((ref) {
  return CreateSessionNotifier(ref.read(apiClientProvider), ref);
});
