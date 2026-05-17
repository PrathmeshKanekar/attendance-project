// presentation/providers/virtual_room_providers.dart
// ─────────────────────────────────────────────────────────────────────────────
// Riverpod state management and dependency injection for Virtual Rooms.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../data/datasources/virtual_room_remote_data_source.dart';
import '../../data/repositories/virtual_room_repository.dart';
import '../../domain/repositories/i_virtual_room_repository.dart';
import '../../data/models/virtual_room_model.dart';

final virtualRoomRemoteDataSourceProvider = Provider<IVirtualRoomRemoteDataSource>((ref) {
  final api = ref.watch(apiClientProvider);
  return VirtualRoomRemoteDataSource(api);
});

final virtualRoomRepositoryProvider = Provider<IVirtualRoomRepository>((ref) {
  final remoteDS = ref.watch(virtualRoomRemoteDataSourceProvider);
  return VirtualRoomRepository(remoteDS);
});

// ── Room list ─────────────────────────────────────────────────────────────────
final virtualRoomsProvider = FutureProvider<List<VirtualRoom>>((ref) async {
  final repo = ref.watch(virtualRoomRepositoryProvider);
  return await repo.getAllRooms();
});

// ── Room detail ───────────────────────────────────────────────────────────────
final roomDetailProvider = FutureProvider.family<VirtualRoom, String>((ref, roomId) async {
  final repo = ref.watch(virtualRoomRepositoryProvider);
  return await repo.getRoomDetail(roomId);
});

// ── Room stats ────────────────────────────────────────────────────────────────
final roomStatsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, roomId) async {
  final repo = ref.watch(virtualRoomRepositoryProvider);
  return await repo.getRoomStats(roomId);
});

// ── Room Preview ──────────────────────────────────────────────────────────────
final roomPreviewProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, roomId) async {
  final repo = ref.watch(virtualRoomRepositoryProvider);
  return await repo.getRoomPreview(roomId);
});

// ── CRUD state machine ────────────────────────────────────────────────────────
sealed class RoomCrudState {}

class RoomCrudIdle extends RoomCrudState {}
class RoomCrudLoading extends RoomCrudState {}
class RoomCrudSuccess extends RoomCrudState {
  final String message;
  final VirtualRoom? data;
  RoomCrudSuccess(this.message, {this.data});
}
class RoomCrudError extends RoomCrudState {
  final String message;
  RoomCrudError(this.message);
}

class RoomCrudNotifier extends StateNotifier<RoomCrudState> {
  final IVirtualRoomRepository _repo;
  final Ref _ref;

  RoomCrudNotifier(this._repo, this._ref) : super(RoomCrudIdle());

  Future<bool> createRoom(Map<String, dynamic> data) async {
    state = RoomCrudLoading();
    try {
      final room = await _repo.createRoom(data);
      _ref.invalidate(virtualRoomsProvider);
      state = RoomCrudSuccess('Room created successfully.', data: room);
      return true;
    } on Exception catch (e) {
      state = RoomCrudError(_extractError(e));
      return false;
    }
  }

  Future<bool> updateRoom(String id, Map<String, dynamic> data) async {
    state = RoomCrudLoading();
    try {
      final room = await _repo.updateRoom(id, data);
      _ref.invalidate(virtualRoomsProvider);
      _ref.invalidate(roomDetailProvider(id));
      state = RoomCrudSuccess('Room updated successfully.', data: room);
      return true;
    } on Exception catch (e) {
      state = RoomCrudError(_extractError(e));
      return false;
    }
  }

  Future<bool> deleteRoom(String id) async {
    state = RoomCrudLoading();
    try {
      await _repo.deleteRoom(id);
      _ref.invalidate(virtualRoomsProvider);
      state = RoomCrudSuccess('Room deactivated.');
      return true;
    } on Exception catch (e) {
      state = RoomCrudError(_extractError(e));
      return false;
    }
  }

  Future<Map<String, dynamic>?> checkLocation({
    required String roomId,
    required double lat,
    required double lng,
    required double altitude,
    double gpsAccuracy = 10.0,
    Map<String, dynamic>? sensors,
  }) async {
    try {
      return await _repo.checkLocation(roomId, {
        'lat': lat,
        'lng': lng,
        'altitude': altitude,
        'gps_accuracy': gpsAccuracy,
        if (sensors != null) 'sensors': sensors,
      });
    } on Exception catch (e) {
      state = RoomCrudError(_extractError(e));
      return null;
    }
  }

  Future<bool> resetCorners(String roomId) async {
    state = RoomCrudLoading();
    try {
      await _repo.resetCorners(roomId);
      _ref.invalidate(roomDetailProvider(roomId));
      _ref.invalidate(virtualRoomsProvider);
      state = RoomCrudSuccess('Corners reset. Room is ready for re-capture.');
      return true;
    } on Exception catch (e) {
      state = RoomCrudError(_extractError(e));
      return false;
    }
  }

  void reset() => state = RoomCrudIdle();

  String _extractError(Object e) {
    if (e is DioException) {
      if (e.response?.statusCode == 403) {
        return 'Permission denied. You do not have the required role.';
      }
      if (e.response?.statusCode == 404) {
        return 'Room not found.';
      }
      final data = e.response?.data;
      if (data is Map) {
        if (data.containsKey('error')) return data['error'].toString();
        if (data.containsKey('detail')) return data['detail'].toString();
        final first = data.values.firstOrNull;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Request timed out. Check your connection.';
      }
    }
    return e.toString().replaceAll('Exception: ', '');
  }
}

final roomCrudProvider = StateNotifierProvider<RoomCrudNotifier, RoomCrudState>((ref) {
  final repo = ref.watch(virtualRoomRepositoryProvider);
  return RoomCrudNotifier(repo, ref);
});

// ── Corner capture state ──────────────────────────────────────────────────────
class CornerCaptureState {
  final bool isCapturing;
  final String? error;
  const CornerCaptureState({this.isCapturing = false, this.error});
}

class CornerCaptureNotifier extends StateNotifier<CornerCaptureState> {
  final IVirtualRoomRepository _repo;

  CornerCaptureNotifier(this._repo) : super(const CornerCaptureState());

  Future<Map<String, dynamic>?> captureCorner({
    required String roomId,
    required int cornerIndex,
    required Map<String, dynamic> payload,
  }) async {
    state = const CornerCaptureState(isCapturing: true);
    try {
      final res = await _repo.captureCorner({
        'room_id': roomId,
        'corner_index': cornerIndex,
        ...payload,
      });
      state = const CornerCaptureState();
      return res;
    } on DioException catch (e) {
      final msg = e.response?.data?['error']?.toString() ?? e.message ?? 'Network error';
      state = CornerCaptureState(error: msg);
      return null;
    } on Exception catch (e) {
      state = CornerCaptureState(error: e.toString());
      return null;
    }
  }

  void clearError() => state = const CornerCaptureState();
}

final cornerCaptureProvider = StateNotifierProvider<CornerCaptureNotifier, CornerCaptureState>((ref) {
  final repo = ref.watch(virtualRoomRepositoryProvider);
  return CornerCaptureNotifier(repo);
});
