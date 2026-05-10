import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import '../models/user_model.dart';
import '../network/api_client.dart';
import '../services/secure_storage_service.dart';

abstract class AuthState {}
class AuthInitial       extends AuthState {}
class AuthLoading       extends AuthState {}
class AuthSuccess       extends AuthState {
  final UserModel user;
  AuthSuccess(this.user);
}
class AuthError         extends AuthState {
  final String message;
  AuthError(this.message);
}
class AuthUnauthenticated extends AuthState {}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient              _api;
  final FlutterSecureStorage   _storage;

  AuthNotifier(this._api, this._storage) : super(AuthInitial()) {
    // CRITICAL FIX: auto-restore session on creation
    _restoreOnInit();
  }

  // Called automatically when notifier is created
  // Restores user from secure storage without showing loading
  Future<void> _restoreOnInit() async {
    try {
      final token = await SecureStorageService.getAccessToken();
      if (token == null) {
        state = AuthUnauthenticated();
        return;
      }

      final cached = await SecureStorageService.loadUser();
      if (cached != null) {
        state = AuthSuccess(cached);
      }

      try {
        final res = await _api.get('/api/auth/me/');
        final user = UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
        await SecureStorageService.saveUser(user);
        state = AuthSuccess(user);
      } catch (e) {
        if (cached == null) {
          await SecureStorageService.clearAll();
          state = AuthUnauthenticated();
        }
      }
    } catch (_) {
      state = AuthUnauthenticated();
    }
  }

  Future<void> loginWithEmail(String email, String password) async {
    state = AuthLoading();
    try {
      final res = await _api.post('/api/auth/login/email/', data: {
        'email': email.trim().toLowerCase(),
        'password': password,
      });
      await _handleAuthResponse(res.data);
    } on DioException catch (e) {
      state = AuthError(_extractError(e));
    } catch (_) {
      state = AuthError('An unexpected error occurred. Please try again.');
    }
  }

  Future<void> loginWithPrn(String prn, String password) async {
    state = AuthLoading();
    try {
      final res = await _api.post('/api/auth/login/prn/', data: {
        'prn': prn.trim().toUpperCase(),
        'password': password,
      });
      await _handleAuthResponse(res.data);
    } on DioException catch (e) {
      state = AuthError(_extractError(e));
    } catch (_) {
      state = AuthError('An unexpected error occurred. Please try again.');
    }
  }

  Future<UserModel?> restoreSession() async {
    try {
      final token = await _storage.read(key: AppConstants.tokenKey);
      if (token == null) {
        state = AuthUnauthenticated();
        return null;
      }
      final res  = await _api.get('/api/auth/me/');
      final user = UserModel.fromJson(
        res.data['user'] as Map<String, dynamic>,
      );
      await SecureStorageService.saveUser(user);
      state = AuthSuccess(user);
      return user;
    } catch (_) {
      await _storage.deleteAll();
      state = AuthUnauthenticated();
      return null;
    }
  }

  Future<void> logout() async {
    try {
      final refresh = await SecureStorageService.getRefreshToken();
      if (refresh != null) {
        await _api.post('/api/auth/logout/', data: {'refresh': refresh});
      }
    } catch (_) {}
    await SecureStorageService.clearAll();
    state = AuthUnauthenticated();
  }

  Future<void> _handleAuthResponse(Map<String, dynamic> data) async {
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
    await SecureStorageService.saveTokens(
      access: data['access'] as String,
      refresh: data['refresh'] as String,
    );
    await SecureStorageService.saveUser(user);
    state = AuthSuccess(user);
  }

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data.containsKey('error')) {
      return data['error'] as String;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timed out. Ensure your PC and phone are on the same Wi-Fi.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Connection Refused. Verify that your Django server is running on 0.0.0.0:8000 and your firewall allows connections.';
    }
    return 'Network Error: ${e.message ?? "Something went wrong"}. Please check your server IP in settings.';
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api     = ref.read(apiClientProvider);
  final storage = ref.read(secureStorageProvider);
  return AuthNotifier(api, storage);
});
