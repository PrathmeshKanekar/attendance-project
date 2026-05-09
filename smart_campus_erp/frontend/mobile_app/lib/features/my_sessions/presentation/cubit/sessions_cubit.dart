
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/i_session_repository.dart';
import 'sessions_state.dart';

class SessionsCubit extends Cubit<SessionsState> {
  final ISessionRepository _repository;

  SessionsCubit(this._repository) : super(SessionsInitial());

  Future<void> loadSessions({String? status, bool silent = false}) async {
    if (!silent) emit(SessionsLoading());
    try {
      final sessions = await _repository.getMySessions(status: status);
      final activeCount = sessions.where((s) => s.status == 'active').length;
      
      emit(SessionsLoaded(
        sessions: sessions,
        activeCount: activeCount,
        filterStatus: status,
      ));
    } catch (e) {
      emit(SessionsError(e.toString()));
    }
  }

  Future<void> endSession(String sessionId) async {
    try {
      await _repository.endSession(sessionId);
      final currentFilter = state is SessionsLoaded
          ? (state as SessionsLoaded).filterStatus
          : null;
      await loadSessions(status: currentFilter, silent: true);
    } catch (e) {
      emit(SessionsError('Failed to end session: ${e.toString()}'));
    }
  }
}
