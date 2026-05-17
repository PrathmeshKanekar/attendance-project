// domain/repositories/i_virtual_room_repository.dart
// ─────────────────────────────────────────────────────────────────────────────
// Abstract Repository contract defining all room data and check activities.
// ─────────────────────────────────────────────────────────────────────────────

import '../../data/models/virtual_room_model.dart';

abstract class IVirtualRoomRepository {
  Future<List<VirtualRoom>> getAllRooms();
  Future<VirtualRoom> getRoomDetail(String roomId);
  Future<VirtualRoom> createRoom(Map<String, dynamic> data);
  Future<VirtualRoom> updateRoom(String roomId, Map<String, dynamic> data);
  Future<void> deleteRoom(String roomId);
  Future<Map<String, dynamic>> checkLocation(String roomId, Map<String, dynamic> data);
  Future<Map<String, dynamic>> captureCorner(Map<String, dynamic> payload);
  Future<void> resetCorners(String roomId);
  Future<Map<String, dynamic>> getRoomStats(String roomId);
  Future<Map<String, dynamic>> getRoomPreview(String roomId);
}
