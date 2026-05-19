import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiConfig {
  ApiConfig._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _baseUrlKey = 'custom_base_url';

  // ── CENTRALIZED PC LAN IP (Single Source of Truth) ──────────────
  static const String pcWifiIp = '10.226.203.98';
  static const String devIp    = pcWifiIp; // Compatibility alias
  static const String devPort  = '8000';

  /// Dynamically resolve default base URL based on platform/device type
  static Future<String> get defaultBaseUrl async {
    if (kIsWeb) {
      return 'http://localhost:$devPort';
    }
    if (Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        if (!androidInfo.isPhysicalDevice) {
          // Android Emulator
          return 'http://10.0.2.2:$devPort';
        }
      } catch (e) {
        debugPrint('ApiConfig: Error reading androidInfo: $e');
      }
      // Physical Android Device (connects directly to PC Wi-Fi IP)
      return 'http://$pcWifiIp:$devPort';
    }
    // Default fallback (Localhost) for iOS / desktop platforms
    return 'http://127.0.0.1:$devPort';
  }

  /// Get the validated base URL
  static Future<String> get baseUrl async {
    final fallback = await defaultBaseUrl;
    try {
      debugPrint('ApiConfig: Resolving base URL...');
      final custom = await _storage.read(key: _baseUrlKey).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('ApiConfig: Storage read timed out. Using default.');
          return null;
        },
      );
      final resolved = await _sanitize(custom);
      debugPrint('ApiConfig: Resolved to $resolved');
      return resolved;
    } catch (e) {
      debugPrint('ApiConfig: Error reading base URL: $e. Using default.');
      return fallback;
    }
  }

  /// Sanitize and validate URL to prevent loopback failures on mobile
  static Future<String> _sanitize(String? url) async {
    final fallback = await defaultBaseUrl;
    if (url == null || url.trim().isEmpty) return fallback;
    
    final lower = url.toLowerCase().trim();
    if (lower.contains('localhost') || 
        lower.contains('127.0.0.1') || 
        lower.contains('0.0.0.0')) {
      return fallback;
    }
    return url.trim();
  }

  /// Save a custom base URL (with validation)
  static Future<void> setCustomBaseUrl(String url) async {
    final sanitized = await _sanitize(url);
    await _storage.write(key: _baseUrlKey, value: sanitized);
  }

  // ── API ENDPOINTS ───────────────────────────────────────────────
  
  // Auth
  static const String loginEmail     = '/api/auth/login/email/';
  static const String loginPrn       = '/api/auth/login/prn/';
  static const String logout         = '/api/auth/logout/';
  static const String refreshToken   = '/api/auth/refresh/';
  static const String currentUser    = '/api/auth/me/';
  static const String userDetail     = '/api/auth/users/'; // Use with ID
  
  // Core / Academic
  static const String colleges       = '/api/tenants/colleges/';
  static const String divisions      = '/api/academic/divisions/';
  static const String departments    = '/api/academic/departments/';
  static const String subjects       = '/api/academic/subjects/';
  
  // Student
  static const String studentsRegister = '/api/students/register/';
  static const String studentProfile  = '/api/students/profile/';
  
  // Attendance
  static const String sessionsActive  = '/api/attendance/sessions/active/';
  static const String sessionsMy      = '/api/attendance/sessions/my/';
  static const String checkLocation   = '/api/attendance/check-location/';
  static const String markAttendance  = '/api/attendance/mark/';
  static const String manualAttendance = '/api/attendance/manual/';
  
  // Rooms
  static const String virtualRooms    = '/api/virtual-rooms/';
  
  // Reports
  static const String reportSummary   = '/api/reports/summary/';
  static const String reportDefaulters = '/api/reports/defaulters/';
  
  // Approvals
  static const String pendingApprovals = '/api/approvals/pending/';
}
