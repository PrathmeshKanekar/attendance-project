import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';

// ── Rooms list ─────────────────────────────────────────────
final virtualRoomsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/api/virtual-rooms/');
  return List<Map<String, dynamic>>.from(res.data as List);
});

// ── Single room detail ─────────────────────────────────────
final roomDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
  (ref, roomId) async {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/virtual-rooms/$roomId/');
    return Map<String, dynamic>.from(res.data as Map);
  },
);

// ── Room stats ─────────────────────────────────────────────
final roomStatsProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
  (ref, roomId) async {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/virtual-rooms/$roomId/stats/');
    return Map<String, dynamic>.from(res.data as Map);
  },
);

// ── Room CRUD state ────────────────────────────────────────
abstract class RoomCrudState {}
class RoomCrudIdle    extends RoomCrudState {}
class RoomCrudLoading extends RoomCrudState {}
class RoomCrudSuccess extends RoomCrudState {
  final String message;
  RoomCrudSuccess(this.message);
}
class RoomCrudError   extends RoomCrudState {
  final String message;
  RoomCrudError(this.message);
}

class RoomCrudNotifier extends StateNotifier<RoomCrudState> {
  final ApiClient _api;
  final Ref       _ref;

  RoomCrudNotifier(this._api, this._ref) : super(RoomCrudIdle());

  Future<bool> createRoom(Map<String, dynamic> data) async {
    state = RoomCrudLoading();
    try {
      await _api.post('/api/virtual-rooms/', data: data);
      _ref.invalidate(virtualRoomsProvider);
      state = RoomCrudSuccess('Room created successfully.');
      return true;
    } on Exception catch (e) {
      state = RoomCrudError(_extractError(e));
      return false;
    }
  }

  Future<bool> updateRoom(String id, Map<String, dynamic> data) async {
    state = RoomCrudLoading();
    try {
      await _api.put('/api/virtual-rooms/$id/', data: data);
      _ref.invalidate(virtualRoomsProvider);
      _ref.invalidate(roomDetailProvider(id));
      state = RoomCrudSuccess('Room updated successfully.');
      return true;
    } on Exception catch (e) {
      state = RoomCrudError(_extractError(e));
      return false;
    }
  }

  Future<bool> deleteRoom(String id) async {
    state = RoomCrudLoading();
    try {
      await _api.delete('/api/virtual-rooms/$id/');
      _ref.invalidate(virtualRoomsProvider);
      state = RoomCrudSuccess('Room deactivated.');
      return true;
    } on Exception catch (e) {
      state = RoomCrudError(_extractError(e));
      return false;
    }
  }

  Future<Map<String, dynamic>?> checkLocation(
    String roomId,
    double lat,
    double lng,
    double altitude,
  ) async {
    try {
      final res = await _api.post(
        '/api/virtual-rooms/$roomId/check-location/',
        data: {'lat': lat, 'lng': lng, 'altitude': altitude},
      );
      return Map<String, dynamic>.from(res.data as Map);
    } on Exception catch (e) {
      state = RoomCrudError(_extractError(e));
      return null;
    }
  }

  void reset() => state = RoomCrudIdle();

  String _extractError(Exception e) {
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

final roomCrudProvider =
    StateNotifierProvider<RoomCrudNotifier, RoomCrudState>((ref) {
  return RoomCrudNotifier(ref.read(apiClientProvider), ref);
});
