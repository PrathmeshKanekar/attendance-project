import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/config/api_config.dart';

final collegesProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  // CRITICAL FIX: keep alive so data persists during navigation
  ref.keepAlive();

  final api = ref.read(apiClientProvider);
  try {
    // USE CENTRALIZED CONFIG
    final res = await api.get(ApiConfig.colleges);
    final rawData = res.data;

    // Standardize response to a Map<String, dynamic>
    Map<String, dynamic> root = {};
    if (rawData is List) {
      root = {
        'colleges': rawData,
        'total': rawData.length,
      };
    } else if (rawData is Map) {
      root = Map<String, dynamic>.from(rawData);
      // Handle nested 'data' wrapper if present
      if (root.containsKey('data') && root['data'] is Map) {
        root = Map<String, dynamic>.from(root['data'] as Map);
      } else if (root.containsKey('data') && root['data'] is List) {
        // Some APIs return { "data": [...] }
        root = {
          'colleges': root['data'],
          'total': (root['data'] as List).length,
        };
      }
    }

    // Extract the colleges list with fallback keys
    final collegesRaw = root['colleges'] ?? root['results'] ?? root['data'] ?? [];
    final collegesList = (collegesRaw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return {
      ...root,
      'colleges': collegesList,
      'total': (root['total'] ?? root['count'] ?? collegesList.length) as int,
      'active_count': (root['active_count'] ?? collegesList.where((c) => c['is_active'] == true).length) as int,
      'inactive_count': (root['inactive_count'] ?? collegesList.where((c) => c['is_active'] != true).length) as int,
    };
  } catch (e) {
    rethrow;
  }
});


abstract class CollegeCrudState {}
class CollegeCrudIdle    extends CollegeCrudState {}
class CollegeCrudLoading extends CollegeCrudState {}
class CollegeCrudSuccess extends CollegeCrudState {
  final String message;
  final Map<String, dynamic>? data;
  CollegeCrudSuccess(this.message, {this.data});
}
class CollegeCrudError   extends CollegeCrudState {
  final String message;
  CollegeCrudError(this.message);
}

class CollegeCrudNotifier extends StateNotifier<CollegeCrudState> {
  final ApiClient _api;
  final Ref       _ref;
  CollegeCrudNotifier(this._api, this._ref) : super(CollegeCrudIdle());

  Future<bool> createCollege(Map<String, dynamic> data) async {
    state = CollegeCrudLoading();
    try {
      final res = await _api.post(ApiConfig.colleges, data: data);
      _ref.invalidate(collegesProvider);
      
      final responseData = Map<String, dynamic>.from(res.data as Map);
      state = CollegeCrudSuccess(
        responseData['message']?.toString() ?? 'College created.',
        data: responseData['admin_credentials'] != null 
            ? Map<String, dynamic>.from(responseData['admin_credentials'] as Map)
            : null,
      );
      return true;
    } on Exception catch (e) {
      state = CollegeCrudError(_extract(e));
      return false;
    }
  }

  Future<bool> updateCollege(String id, Map<String, dynamic> data) async {
    state = CollegeCrudLoading();
    try {
      final res = await _api.put('${ApiConfig.colleges}$id/', data: data);
      _ref.invalidate(collegesProvider);
      state = CollegeCrudSuccess(
        res.data['message']?.toString() ?? 'College updated.',
      );
      return true;
    } on Exception catch (e) {
      state = CollegeCrudError(_extract(e));
      return false;
    }
  }

  Future<bool> deactivateCollege(String id) async {
    state = CollegeCrudLoading();
    try {
      final res = await _api.delete('${ApiConfig.colleges}$id/');
      _ref.invalidate(collegesProvider);
      state = CollegeCrudSuccess(
        res.data['message']?.toString() ?? 'College deactivated.',
      );
      return true;
    } on Exception catch (e) {
      state = CollegeCrudError(_extract(e));
      return false;
    }
  }

  Future<bool> activateCollege(String id) async {
    state = CollegeCrudLoading();
    try {
      final res = await _api.post('${ApiConfig.colleges}$id/activate/');
      _ref.invalidate(collegesProvider);
      state = CollegeCrudSuccess(
        res.data['message']?.toString() ?? 'College activated.',
      );
      return true;
    } on Exception catch (e) {
      state = CollegeCrudError(_extract(e));
      return false;
    }
  }

  void reset() => state = CollegeCrudIdle();

  String _extract(Object e) {
    if (e is DioException) {
      if (e.response?.statusCode == 403) {
        return 'Permission denied: Restricted to Super Admin.';
      }
      final data = e.response?.data;
      if (data is Map && data.containsKey('error')) {
        return data['error'].toString();
      }
      if (data is Map && data.containsKey('detail')) {
        return data['detail'].toString();
      }
    }
    final msg = e.toString();
    if (msg.contains('"error"')) {
      try {
        final start = msg.indexOf('"error":') + 9;
        final sub   = msg.substring(start);
        final end   = sub.indexOf('"', 1);
        return sub.substring(1, end);
      } catch (_) {}
    }
    return msg.replaceAll('Exception: ', '');
  }
}

final collegeCrudProvider =
    StateNotifierProvider<CollegeCrudNotifier, CollegeCrudState>((ref) {
  return CollegeCrudNotifier(ref.read(apiClientProvider), ref);
});
