import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

class DeviceService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    wOptions: WindowsOptions(),
  );

  static const _key = 'secure_device_id';
  static String? _cachedDeviceId;

  /// Helper to normalize device ID exactly matching backend rules:
  /// strip, lowercase, remove hyphens and colons
  static String normalizeDeviceId(String deviceId) {
    return deviceId.trim().toLowerCase().replaceAll('-', '').replaceAll(':', '');
  }

  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    // 1. Try to read from memory cache or secure storage first
    try {
      final storedId = await _storage.read(key: _key);
      if (storedId != null && storedId.isNotEmpty) {
        _cachedDeviceId = normalizeDeviceId(storedId);
        return _cachedDeviceId!;
      }
    } catch (e) {
      debugPrint('DeviceService: Secure storage read error: $e');
    }

    // 2. Try to read from Hive backup cache (in case secure storage resets)
    try {
      final box = await Hive.openBox('device_cache');
      final hiveId = box.get(_key) as String?;
      if (hiveId != null && hiveId.isNotEmpty) {
        _cachedDeviceId = normalizeDeviceId(hiveId);
        // Sync back to secure storage
        await _storage.write(key: _key, value: hiveId);
        return _cachedDeviceId!;
      }
    } catch (e) {
      debugPrint('DeviceService: Hive read error: $e');
    }

    // 3. Obtain hardware/platform specific identifier
    String? rawId;
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        rawId = 'web_client';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        rawId = androidInfo.id; // hardware build/serial signature or Android ID
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        rawId = iosInfo.identifierForVendor;
      }
    } catch (e) {
      debugPrint('DeviceService: Error getting platform info: $e');
    }

    // 4. Fallback to UUID v4 if platform ID is unavailable or trivial
    if (rawId == null || rawId.isEmpty || rawId.toLowerCase() == 'unknown') {
      rawId = const Uuid().v4();
    }

    final normalized = normalizeDeviceId(rawId);

    // 5. Persist the ID to both secure storage and Hive cache
    try {
      await _storage.write(key: _key, value: normalized);
      final box = await Hive.openBox('device_cache');
      await box.put(_key, normalized);
    } catch (e) {
      debugPrint('DeviceService: Persist error: $e');
    }

    _cachedDeviceId = normalized;
    return _cachedDeviceId!;
  }
}
