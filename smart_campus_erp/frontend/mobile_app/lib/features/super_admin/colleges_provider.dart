import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';

final collegesProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  // CRITICAL FIX: keep alive so data persists during navigation
  ref.keepAlive();

  final api = ref.read(apiClientProvider);
  try {
    final res = await api.get('/api/colleges/');

    // CRITICAL FIX: handle both list and map response formats
    if (res.data is List) {
      // API returned list directly
      final list = List<Map<String, dynamic>>.from(
        (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      return {
        'colleges'      : list,
        'total'         : list.length,
        'active_count'  : list.where((c) => c['is_active'] == true).length,
        'inactive_count': list.where((c) => c['is_active'] != true).length,
      };
    }

    // API returned map with colleges key
    final data = Map<String, dynamic>.from(res.data as Map);
    return data;
  } catch (e) {
    rethrow;
  }
});


abstract class CollegeCrudState {}
class CollegeCrudIdle    extends CollegeCrudState {}
class CollegeCrudLoading extends CollegeCrudState {}
class CollegeCrudSuccess extends CollegeCrudState {
  final String message;
  CollegeCrudSuccess(this.message);
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
      final res = await _api.post('/api/colleges/', data: data);
      _ref.invalidate(collegesProvider);
      state = CollegeCrudSuccess(
        res.data['message']?.toString() ?? 'College created.',
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
      final res = await _api.put('/api/colleges/$id/', data: data);
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
      final res = await _api.delete('/api/colleges/$id/');
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
      final res = await _api.post('/api/colleges/$id/activate/');
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

  String _extract(Exception e) {
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
