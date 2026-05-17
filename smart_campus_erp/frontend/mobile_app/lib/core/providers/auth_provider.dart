import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';
import '../constants/app_constants.dart';
import '../models/user_model.dart';
import '../network/dio_client.dart';
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
  final DioClient              _api;
  final FlutterSecureStorage   _storage;

  AuthNotifier(this._api, this._storage) : super(AuthInitial()) {
    _restoreOnInit();
  }

  Future<void> _restoreOnInit() async {
    try {
      print('AuthNotifier: Starting restoration check...');
      final token = await SecureStorageService.getAccessToken();
      
      if (token == null) {
        print('AuthNotifier: No token found. Unauthenticated.');
        state = AuthUnauthenticated();
        return;
      }

      final cached = await SecureStorageService.loadUser();
      if (cached != null) {
        print('AuthNotifier: Found cached user: ${cached.fullName}. Role: ${cached.role}');
        state = AuthSuccess(cached);
      } else {
        print('AuthNotifier: No cached user found.');
      }

      try {
        print('AuthNotifier: Attempting to refresh user from API: ${ApiConfig.currentUser}');
        // Use a shorter timeout for the background check to prevent startup freeze
        final res = await _api.get(ApiConfig.currentUser);
        
        final user = UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
        print('AuthNotifier: API refresh success. Saving user.');
        await SecureStorageService.saveUser(user);
        state = AuthSuccess(user);
      } catch (e) {
        print('AuthNotifier: API refresh failed: $e');
        // If we have a cached user, we stay in AuthSuccess(cached) 
        // to allow offline/local access until next action fails.
        if (cached == null) {
          print('AuthNotifier: No cache and API failed. Logging out.');
          await SecureStorageService.clearAll();
          state = AuthUnauthenticated();
        }
      }
    } catch (e) {
      print('AuthNotifier: CRITICAL initialization error: $e');
      state = AuthUnauthenticated();
    }
  }

  Future<void> loginWithEmail(String email, String password) async {
    state = AuthLoading();
    try {
      final res = await _api.post(ApiConfig.loginEmail, data: {
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
      final res = await _api.post(ApiConfig.loginPrn, data: {
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

  Future<void> logout() async {
    try {
      final refresh = await SecureStorageService.getRefreshToken();
      if (refresh != null) {
        await _api.post(ApiConfig.logout, data: {'refresh': refresh});
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
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'Unable to connect to server. Please check your internet or PC connection.';
    }
    
    if (e.type == DioExceptionType.connectionError) {
      return 'Server unreachable. Ensure the backend is running at ${ApiConfig.devIp}.';
    }
    
    return 'Network Error: Unable to connect to server.';
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api     = ref.read(dioClientProvider);
  final storage = ref.read(secureStorageProvider);
  return AuthNotifier(api, storage);
});
