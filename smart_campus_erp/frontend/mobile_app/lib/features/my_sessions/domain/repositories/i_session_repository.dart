
import '../entities/session_entity.dart';

abstract class ISessionRepository {
  Future<List<SessionEntity>> getMySessions({String? status, int limit = 30});
  Future<void> endSession(String sessionId);
  Future<void> cancelSession(String sessionId, String reason);
  Future<void> createSession(Map<String, dynamic> data);
}
