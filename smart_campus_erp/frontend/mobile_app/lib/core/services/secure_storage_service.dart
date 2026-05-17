import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import '../models/user_model.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    wOptions: WindowsOptions(),
  );
});

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    wOptions: WindowsOptions(),
  );

  static const _tokenKey = AppConstants.tokenKey;
  static const _refreshKey = AppConstants.refreshKey;
  static const _userKey = AppConstants.userKey;

  static Future<void> saveTokens({required String access, required String refresh}) async {
    await _storage.write(key: _tokenKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  static Future<void> saveUser(UserModel user) async {
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  static Future<UserModel?> loadUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getAccessToken() => _storage.read(key: _tokenKey);
  static Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  static Future<void> clearAll() => _storage.deleteAll();
}
