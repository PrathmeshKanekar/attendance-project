import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../models/virtual_room_model.dart';
import '../repositories/virtual_room_repository.dart';

final virtualRoomRepositoryProvider = Provider<VirtualRoomRepository>((ref) {
  final api = ref.read(apiClientProvider);
  return VirtualRoomRepository(api);
});

class VirtualRoomsState {
  final bool isLoading;
  final List<VirtualRoomModel> rooms;
  final String? error;

  const VirtualRoomsState({
    this.isLoading = false,
    this.rooms = const [],
    this.error,
  });

  VirtualRoomsState copyWith({
    bool? isLoading,
    List<VirtualRoomModel>? rooms,
    String? error,
  }) {
    return VirtualRoomsState(
      isLoading: isLoading ?? this.isLoading,
      rooms: rooms ?? this.rooms,
      error: error,
    );
  }
}

class VirtualRoomsNotifier extends StateNotifier<VirtualRoomsState> {
  final VirtualRoomRepository _repo;

  VirtualRoomsNotifier(this._repo) : super(const VirtualRoomsState()) {
    fetchRooms();
  }

  Future<void> fetchRooms() async {
    state = state.copyWith(isLoading: true, error: null);
    final result = await _repo.getRooms();
    result.fold(
      (err) => state = state.copyWith(isLoading: false, error: err),
      (list) => state = state.copyWith(isLoading: false, rooms: list),
    );
  }

  Future<bool> addRoom(Map<String, dynamic> data) async {
    state = state.copyWith(isLoading: true, error: null);
    final result = await _repo.createRoom(data);
    return result.fold(
      (err) {
        state = state.copyWith(isLoading: false, error: err);
        return false;
      },
      (room) {
        state = state.copyWith(
          isLoading: false,
          rooms: [room, ...state.rooms],
        );
        return true;
      },
    );
  }

  Future<bool> editRoom(String id, Map<String, dynamic> data) async {
    state = state.copyWith(isLoading: true, error: null);
    final result = await _repo.updateRoom(id, data);
    return result.fold(
      (err) {
        state = state.copyWith(isLoading: false, error: err);
        return false;
      },
      (updatedRoom) {
        state = state.copyWith(
          isLoading: false,
          rooms: state.rooms.map((r) => r.id == id ? updatedRoom : r).toList(),
        );
        return true;
      },
    );
  }

  Future<bool> removeRoom(String id) async {
    state = state.copyWith(isLoading: true, error: null);
    final result = await _repo.deleteRoom(id);
    return result.fold(
      (err) {
        state = state.copyWith(isLoading: false, error: err);
        return false;
      },
      (_) {
        state = state.copyWith(
          isLoading: false,
          rooms: state.rooms.where((r) => r.id != id).toList(),
        );
        return true;
      },
    );
  }
}

final virtualRoomsProvider = StateNotifierProvider<VirtualRoomsNotifier, VirtualRoomsState>((ref) {
  final repo = ref.read(virtualRoomRepositoryProvider);
  return VirtualRoomsNotifier(repo);
});

// Provider to get a single room by ID from the state
final singleVirtualRoomProvider = Provider.family<VirtualRoomModel?, String>((ref, id) {
  final state = ref.watch(virtualRoomsProvider);
  final rooms = state.rooms.where((r) => r.id == id);
  if (rooms.isNotEmpty) return rooms.first;
  return null;
});
