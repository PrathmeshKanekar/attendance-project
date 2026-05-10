import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import '../models/user_model.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    wOptions: WindowsOptions(),
  );

  static const _tokenKey = AppConstants.tokenKey;
  static const _refreshKey = AppConstants.refreshKey;
  static const _userKey = AppConstants.userKey;
  static const _baseUrlKey = 'custom_base_url';

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

  static Future<String> getBaseUrl() async {
    final custom = await _storage.read(key: _baseUrlKey);
    // CRITICAL: If custom URL is localhost or 127.0.0.1, it WILL fail on physical devices.
    // We fall back to the LAN IP defined in AppConstants if we detect a loopback address.
    if (custom != null && (custom.contains('localhost') || custom.contains('127.0.0.1'))) {
      return AppConstants.baseUrl;
    }
    return custom ?? AppConstants.baseUrl;
  }

  static Future<void> saveBaseUrl(String url) => _storage.write(key: _baseUrlKey, value: url);

  static Future<void> clearAll() => _storage.deleteAll();
}
