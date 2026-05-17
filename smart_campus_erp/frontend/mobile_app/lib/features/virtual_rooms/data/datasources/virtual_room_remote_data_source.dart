// data/datasources/virtual_room_remote_data_source.dart
// ─────────────────────────────────────────────────────────────────────────────
// Production remote data source executing API requests for Virtual Rooms.
// ─────────────────────────────────────────────────────────────────────────────

import '../../../../core/network/api_client.dart';

abstract class IVirtualRoomRemoteDataSource {
  Future<List<Map<String, dynamic>>> getVirtualRooms();
  Future<Map<String, dynamic>> getVirtualRoomDetail(String roomId);
  Future<Map<String, dynamic>> createVirtualRoom(Map<String, dynamic> data);
  Future<Map<String, dynamic>> updateVirtualRoom(String roomId, Map<String, dynamic> data);
  Future<void> deleteVirtualRoom(String roomId);
  Future<Map<String, dynamic>> checkLocation(String roomId, Map<String, dynamic> payload);
  Future<Map<String, dynamic>> captureCorner(Map<String, dynamic> payload);
  Future<Map<String, dynamic>> resetCorners(String roomId);
  Future<Map<String, dynamic>> getRoomStats(String roomId);
  Future<Map<String, dynamic>> getRoomPreview(String roomId);
}

class VirtualRoomRemoteDataSource implements IVirtualRoomRemoteDataSource {
  final ApiClient _api;

  VirtualRoomRemoteDataSource(this._api);

  @override
  Future<List<Map<String, dynamic>>> getVirtualRooms() async {
    final res = await _api.get('/api/virtual-rooms/');
    return List<Map<String, dynamic>>.from(res.data as List);
  }

  @override
  Future<Map<String, dynamic>> getVirtualRoomDetail(String roomId) async {
    final res = await _api.get('/api/virtual-rooms/$roomId/');
    return Map<String, dynamic>.from(res.data as Map);
  }

  @override
  Future<Map<String, dynamic>> createVirtualRoom(Map<String, dynamic> data) async {
    final res = await _api.post('/api/virtual-rooms/', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  @override
  Future<Map<String, dynamic>> updateVirtualRoom(String roomId, Map<String, dynamic> data) async {
    final res = await _api.patch('/api/virtual-rooms/$roomId/', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  @override
  Future<void> deleteVirtualRoom(String roomId) async {
    await _api.delete('/api/virtual-rooms/$roomId/');
  }

  @override
  Future<Map<String, dynamic>> checkLocation(String roomId, Map<String, dynamic> payload) async {
    final res = await _api.post('/api/virtual-rooms/$roomId/check-location/', data: payload);
    return Map<String, dynamic>.from(res.data as Map);
  }

  @override
  Future<Map<String, dynamic>> captureCorner(Map<String, dynamic> payload) async {
    final res = await _api.post('/api/virtual-rooms/capture-corner/', data: payload);
    return Map<String, dynamic>.from(res.data as Map);
  }

  @override
  Future<Map<String, dynamic>> resetCorners(String roomId) async {
    final res = await _api.delete('/api/virtual-rooms/$roomId/reset-corners/');
    return Map<String, dynamic>.from(res.data as Map);
  }

  @override
  Future<Map<String, dynamic>> getRoomStats(String roomId) async {
    final res = await _api.get('/api/virtual-rooms/$roomId/stats/');
    return Map<String, dynamic>.from(res.data as Map);
  }

  @override
  Future<Map<String, dynamic>> getRoomPreview(String roomId) async {
    final res = await _api.get('/api/virtual-rooms/$roomId/preview/');
    return Map<String, dynamic>.from(res.data as Map);
  }
}
