import 'package:flutter/foundation.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';

class SecurityService {
  /// Returns null if device is safe, or an error message string if not.
  static Future<String?> checkDeviceSecurity() async {
    try {
      // Check root / jailbreak
      final isJailbroken = await FlutterJailbreakDetection.jailbroken;
      if (isJailbroken) {
        return 'Rooted/jailbroken device detected. '
               'Attendance cannot be marked on modified devices.';
      }
      
      // Check developer mode (emulator signal)
      final isDevMode = await FlutterJailbreakDetection.developerMode;
      if (isDevMode) {
        debugPrint('Device is running in Developer Mode.');
      }
      
      return null; // Device is safe
    } catch (e) {
      // Never crash attendance on security check errors
      debugPrint('Security check error (non-fatal): $e');
      return null;
    }
  }
}
