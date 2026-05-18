import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../models/virtual_room_model.dart';

final virtualRoomRepositoryProvider = Provider<VirtualRoomRepository>((ref) {
  final api = ref.read(apiClientProvider);
  return VirtualRoomRepository(api);
});

class VirtualRoomRepository {
  final ApiClient _api;

  VirtualRoomRepository(this._api);

  Future<List<VirtualRoomModel>> getVirtualRooms() async {
    final response = await _api.get('/api/virtual-rooms/');
    final data = response.data;
    List<dynamic> list;
    if (data is Map && data.containsKey('data')) {
      list = data['data'] as List? ?? [];
    } else if (data is List) {
      list = data;
    } else {
      list = [];
    }
    return list.map((item) => VirtualRoomModel.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<VirtualRoomModel> getVirtualRoom(String id) async {
    final response = await _api.get('/api/virtual-rooms/$id/');
    final data = response.data;
    if (data is Map && data.containsKey('data')) {
      return VirtualRoomModel.fromJson(data['data'] as Map<String, dynamic>);
    }
    return VirtualRoomModel.fromJson(data as Map<String, dynamic>);
  }

  Future<VirtualRoomModel> createVirtualRoom(Map<String, dynamic> roomData) async {
    final response = await _api.post('/api/virtual-rooms/', data: roomData);
    final data = response.data;
    if (data is Map && data.containsKey('data')) {
      return VirtualRoomModel.fromJson(data['data'] as Map<String, dynamic>);
    }
    return VirtualRoomModel.fromJson(data as Map<String, dynamic>);
  }

  Future<VirtualRoomModel> updateVirtualRoom(String id, Map<String, dynamic> roomData) async {
    final response = await _api.put('/api/virtual-rooms/$id/', data: roomData);
    final data = response.data;
    if (data is Map && data.containsKey('data')) {
      return VirtualRoomModel.fromJson(data['data'] as Map<String, dynamic>);
    }
    return VirtualRoomModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteVirtualRoom(String id) async {
    await _api.delete('/api/virtual-rooms/$id/');
  }
}
