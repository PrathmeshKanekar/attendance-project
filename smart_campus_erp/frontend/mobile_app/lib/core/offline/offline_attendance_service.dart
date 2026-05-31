import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../network/api_client.dart';

class OfflineAttendanceService {
  static const String boxName = 'offline_attendance';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(boxName);
  }

  Future<void> saveForLater(Map<String, dynamic> data) async {
    final box = Hive.isBoxOpen(boxName) ? Hive.box(boxName) : await Hive.openBox(boxName);
    await box.add({
      ...data,
      'savedAt': DateTime.now().toIso8601String(),
      'synced': false,
    });
  }

  Future<List<Map>> getPendingEntries() async {
    final box = Hive.isBoxOpen(boxName) ? Hive.box(boxName) : await Hive.openBox(boxName);
    return box.values.where((e) => e is Map && e['synced'] == false).cast<Map>().toList();
  }

  Future<void> syncAll(ApiClient api) async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    final box = Hive.isBoxOpen(boxName) ? Hive.box(boxName) : await Hive.openBox(boxName);
    final pendingKeys = box.keys.where((k) {
      final val = box.get(k);
      return val is Map && val['synced'] == false;
    }).toList();

    for (final key in pendingKeys) {
      final entry = Map<String, dynamic>.from(box.get(key));
      try {
        final res = await api.post('/api/attendance/mark/', data: entry);
        final rawData = res.data;
        if (rawData is Map && rawData['success'] == true && rawData.containsKey('attendance_id')) {
          entry['synced'] = true;
          await box.put(key, entry);
        }
      } catch (_) {
        // Leave for next attempt
      }
    }
  }
}
