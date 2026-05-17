// data/repositories/virtual_room_repository.dart
// ─────────────────────────────────────────────────────────────────────────────
// Production implementation of the Virtual Room repository with optional cache.
// ─────────────────────────────────────────────────────────────────────────────

import '../../domain/repositories/i_virtual_room_repository.dart';
import '../datasources/virtual_room_remote_data_source.dart';
import '../models/virtual_room_model.dart';

class VirtualRoomRepository implements IVirtualRoomRepository {
  final IVirtualRoomRemoteDataSource _remoteDataSource;
  
  // High efficiency caching
  final Map<String, VirtualRoom> _roomCache = {};
  DateTime? _lastCacheFetch;

  VirtualRoomRepository(this._remoteDataSource);

  @override
  Future<List<VirtualRoom>> getAllRooms() async {
    // Basic 10-second debounce caching to avoid excessive dashboard re-fetching
    if (_roomCache.isNotEmpty && 
        _lastCacheFetch != null && 
        DateTime.now().difference(_lastCacheFetch!).inSeconds < 10) {
      return _roomCache.values.toList();
    }

    final rawList = await _remoteDataSource.getVirtualRooms();
    final rooms = rawList.map((json) => VirtualRoom.fromJson(json)).toList();
    
    _roomCache.clear();
    for (final r in rooms) {
      _roomCache[r.id] = r;
    }
    _lastCacheFetch = DateTime.now();
    return rooms;
  }

  @override
  Future<VirtualRoom> getRoomDetail(String roomId) async {
    final raw = await _remoteDataSource.getVirtualRoomDetail(roomId);
    final room = VirtualRoom.fromJson(raw);
    _roomCache[roomId] = room; // Update cache
    return room;
  }

  @override
  Future<VirtualRoom> createRoom(Map<String, dynamic> data) async {
    final raw = await _remoteDataSource.createVirtualRoom(data);
    final room = VirtualRoom.fromJson(raw);
    _roomCache[room.id] = room;
    return room;
  }

  @override
  Future<VirtualRoom> updateRoom(String roomId, Map<String, dynamic> data) async {
    final raw = await _remoteDataSource.updateVirtualRoom(roomId, data);
    final room = VirtualRoom.fromJson(raw);
    _roomCache[room.id] = room;
    return room;
  }

  @override
  Future<void> deleteRoom(String roomId) async {
    await _remoteDataSource.deleteVirtualRoom(roomId);
    _roomCache.remove(roomId);
  }

  @override
  Future<Map<String, dynamic>> checkLocation(String roomId, Map<String, dynamic> data) async {
    return await _remoteDataSource.checkLocation(roomId, data);
  }

  @override
  Future<Map<String, dynamic>> captureCorner(Map<String, dynamic> payload) async {
    return await _remoteDataSource.captureCorner(payload);
  }

  @override
  Future<void> resetCorners(String roomId) async {
    await _remoteDataSource.resetCorners(roomId);
    if (_roomCache.containsKey(roomId)) {
      final old = _roomCache[roomId]!;
      _roomCache[roomId] = VirtualRoom(
        id: old.id,
        name: old.name,
        building: old.building,
        floorNumber: old.floorNumber,
        department: old.department,
        capacity: old.capacity,
        hasPolygon: false,
        cornerCount: 0,
        radiusMeters: old.radiusMeters,
        isActive: old.isActive,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> getRoomStats(String roomId) async {
    return await _remoteDataSource.getRoomStats(roomId);
  }

  @override
  Future<Map<String, dynamic>> getRoomPreview(String roomId) async {
    return await _remoteDataSource.getRoomPreview(roomId);
  }
}
