
import '../../../../core/network/api_client.dart';
import '../../domain/entities/session_entity.dart';
import '../../domain/repositories/i_session_repository.dart';
import '../models/session_model.dart';

class SessionRepositoryImpl implements ISessionRepository {
  final ApiClient _api;

  SessionRepositoryImpl(this._api);

  @override
  Future<List<SessionEntity>> getMySessions({String? status, int limit = 30}) async {
    final response = await _api.get('/api/attendance/sessions/my/', params: {
      if (status != null) 'status': status,
      'limit': limit,
    });
    
    // Backend returns { sessions: [...], total: N, active_count: N }
    List rawSessions;
    if (response.data is Map && response.data['sessions'] != null) {
      rawSessions = response.data['sessions'] as List;
    } else if (response.data is List) {
      rawSessions = response.data as List;
    } else {
      rawSessions = [];
    }

    final List<SessionEntity> result = [];
    for (final s in rawSessions) {
      try {
        result.add(SessionModel.fromJson(Map<String, dynamic>.from(s as Map)));
      } catch (_) {
        // Skip malformed entries instead of crashing the entire list
      }
    }
    return result;
  }

  @override
  Future<void> endSession(String sessionId) async {
    await _api.post('/api/attendance/sessions/$sessionId/end/');
  }

  @override
  Future<void> cancelSession(String sessionId, String reason) async {
    await _api.post('/api/attendance/sessions/$sessionId/cancel/', data: {
      'reason': reason,
    });
  }

  @override
  Future<void> createSession(Map<String, dynamic> data) async {
    await _api.post('/api/attendance/sessions/', data: data);
  }
}
