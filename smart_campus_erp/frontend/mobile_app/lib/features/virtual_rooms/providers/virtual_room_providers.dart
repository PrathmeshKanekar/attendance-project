import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/virtual_room_model.dart';
import '../repositories/virtual_room_repository.dart';

// Provider for listing, adding, editing, and deleting virtual rooms
final virtualRoomsListProvider = StateNotifierProvider<VirtualRoomsListNotifier, AsyncValue<List<VirtualRoomModel>>>((ref) {
  final repo = ref.read(virtualRoomRepositoryProvider);
  return VirtualRoomsListNotifier(repo);
});

class VirtualRoomsListNotifier extends StateNotifier<AsyncValue<List<VirtualRoomModel>>> {
  final VirtualRoomRepository _repo;

  VirtualRoomsListNotifier(this._repo) : super(const AsyncValue.loading()) {
    loadRooms();
  }

  Future<void> loadRooms() async {
    state = const AsyncValue.loading();
    try {
      final list = await _repo.getVirtualRooms();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addRoom(Map<String, dynamic> roomData) async {
    try {
      final newRoom = await _repo.createVirtualRoom(roomData);
      state.whenData((list) {
        state = AsyncValue.data([...list, newRoom]);
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> editRoom(String id, Map<String, dynamic> roomData) async {
    try {
      final updatedRoom = await _repo.updateVirtualRoom(id, roomData);
      state.whenData((list) {
        state = AsyncValue.data(list.map((r) => r.id == id ? updatedRoom : r).toList());
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteRoom(String id) async {
    try {
      await _repo.deleteVirtualRoom(id);
      state.whenData((list) {
        state = AsyncValue.data(list.where((r) => r.id != id).toList());
      });
    } catch (e) {
      rethrow;
    }
  }
}


// State class for room corner capture
class RoomCaptureState {
  final List<RoomCornerModel?> corners;
  final bool isCapturing;
  final int readingCount;
  final String statusMessage;

  RoomCaptureState({
    required this.corners,
    required this.isCapturing,
    required this.readingCount,
    required this.statusMessage,
  });

  factory RoomCaptureState.initial() {
    return RoomCaptureState(
      corners: List<RoomCornerModel?>.filled(4, null),
      isCapturing: false,
      readingCount: 0,
      statusMessage: 'Ready to capture corners.',
    );
  }

  RoomCaptureState copyWith({
    List<RoomCornerModel?>? corners,
    bool? isCapturing,
    int? readingCount,
    String? statusMessage,
  }) {
    return RoomCaptureState(
      corners: corners ?? this.corners,
      isCapturing: isCapturing ?? this.isCapturing,
      readingCount: readingCount ?? this.readingCount,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

// Provider for capturing 4 classroom corners with GPS averaging
final roomCaptureProvider = StateNotifierProvider.autoDispose<RoomCaptureNotifier, RoomCaptureState>((ref) {
  return RoomCaptureNotifier();
});

class RoomCaptureNotifier extends StateNotifier<RoomCaptureState> {
  RoomCaptureNotifier() : super(RoomCaptureState.initial());

  void setExistingCorners(List<RoomCornerModel> existingCorners) {
    final list = List<RoomCornerModel?>.filled(4, null);
    for (var c in existingCorners) {
      if (c.cornerIndex >= 1 && c.cornerIndex <= 4) {
        list[c.cornerIndex - 1] = c;
      }
    }
    state = state.copyWith(corners: list);
  }

  void reset() {
    state = RoomCaptureState.initial();
  }

  Future<void> captureCorner(int index) async {
    if (index < 1 || index > 4) return;
    
    state = state.copyWith(
      isCapturing: true,
      readingCount: 0,
      statusMessage: 'Checking GPS services...',
    );

    try {
      // Check service and permission
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled on your device.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied.');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied. Please enable them in settings.');
      }

      double sumLat = 0.0;
      double sumLng = 0.0;
      double sumAlt = 0.0;
      double sumHeading = 0.0;
      double sumAccuracy = 0.0;

      // Take 3 readings with 1 second delay
      for (int i = 1; i <= 3; i++) {
        state = state.copyWith(
          readingCount: i,
          statusMessage: 'Capturing corner $index: Reading $i of 3...',
        );
        
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        
        sumLat += position.latitude;
        sumLng += position.longitude;
        sumAlt += position.altitude;
        sumHeading += position.heading;
        sumAccuracy += position.accuracy;

        if (i < 3) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      // Average the coordinates
      double avgLat = sumLat / 3.0;
      double avgLng = sumLng / 3.0;
      double avgAlt = sumAlt / 3.0;
      double avgHeading = sumHeading / 3.0;
      double avgAccuracy = sumAccuracy / 3.0;

      final list = List<RoomCornerModel?>.from(state.corners);
      list[index - 1] = RoomCornerModel(
        cornerIndex: index,
        latitude: avgLat,
        longitude: avgLng,
        altitude: avgAlt,
        heading: avgHeading,
        accuracy: avgAccuracy,
      );

      state = state.copyWith(
        corners: list,
        isCapturing: false,
        readingCount: 0,
        statusMessage: 'Corner $index captured!',
      );
    } catch (e) {
      state = state.copyWith(
        isCapturing: false,
        readingCount: 0,
        statusMessage: 'Failed to capture Corner $index: ${e.toString()}',
      );
      rethrow;
    }
  }
}
