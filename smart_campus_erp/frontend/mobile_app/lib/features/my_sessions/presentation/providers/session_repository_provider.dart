
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../data/repositories/session_repository_impl.dart';
import '../../domain/repositories/i_session_repository.dart';

final sessionRepositoryProvider = Provider<ISessionRepository>((ref) {
  final api = ref.read(apiClientProvider);
  return SessionRepositoryImpl(api);
});
