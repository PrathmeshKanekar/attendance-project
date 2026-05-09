import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceService {
  Future<String> getDeviceId() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      return android.id;
    } else {
      final ios = await info.iosInfo;
      return ios.identifierForVendor ?? 'unknown';
    }
  }
}
