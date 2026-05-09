import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';

// ── Active sessions (teacher) ──────────────────────────────
final teacherActiveSessionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/attendance/sessions/active/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── My allocations ─────────────────────────────────────────
final myAllocationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/allocations/my/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── Virtual rooms ──────────────────────────────────────────
final virtualRoomsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/virtual-rooms/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── Session logs ───────────────────────────────────────────
final sessionLogsProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
  (ref, sessionId) async {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/attendance/sessions/$sessionId/logs/');
    return Map<String, dynamic>.from(res.data as Map);
  },
);

// ── Create session state ───────────────────────────────────
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
  CreateSessionNotifier(this._api) : super(CreateSessionIdle());

  Future<void> createSession(Map<String, dynamic> body) async {
    state = CreateSessionLoading();
    try {
      final res = await _api.post('/api/attendance/sessions/', data: body);
      state = CreateSessionSuccess(
        Map<String, dynamic>.from(res.data['session'] as Map),
        res.data['message']?.toString() ?? 'Session started.',
      );
    } on Exception catch (e) {
      state = CreateSessionError(_extractError(e));
    }
  }

  Future<void> endSession(String sessionId) async {
    state = CreateSessionLoading();
    try {
      final res = await _api.post(
        '/api/attendance/sessions/$sessionId/end/',
      );
      state = CreateSessionSuccess(
        {},
        res.data['message']?.toString() ?? 'Session ended.',
      );
    } on Exception catch (e) {
      state = CreateSessionError(_extractError(e));
    }
  }

  void reset() => state = CreateSessionIdle();

  String _extractError(Exception e) {
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

final createSessionProvider =
    StateNotifierProvider<CreateSessionNotifier, CreateSessionState>((ref) {
  return CreateSessionNotifier(ref.read(apiClientProvider));
});
