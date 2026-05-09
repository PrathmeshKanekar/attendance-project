
import 'package:equatable/equatable.dart';
import '../../domain/entities/session_entity.dart';

abstract class SessionsState extends Equatable {
  const SessionsState();

  @override
  List<Object?> get props => [];
}

class SessionsInitial extends SessionsState {}

class SessionsLoading extends SessionsState {}

class SessionsLoaded extends SessionsState {
  final List<SessionEntity> sessions;
  final int activeCount;
  final String? filterStatus;

  const SessionsLoaded({
    required this.sessions,
    this.activeCount = 0,
    this.filterStatus,
  });

  @override
  List<Object?> get props => [sessions, activeCount, filterStatus];
}

class SessionsError extends SessionsState {
  final String message;
  const SessionsError(this.message);

  @override
  List<Object?> get props => [message];
}
