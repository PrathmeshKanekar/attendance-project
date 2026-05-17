from .models import VirtualRoom, RoomCorner
from .geo_utils import calculate_spatial_vectors

class VirtualRoomService:
    @staticmethod
    def initialize_room_spatial_data(room_id):
        """
        Recomputes spatial vectors and boundaries for a room.
        """
        room = VirtualRoom.objects.get(id=room_id)
        if room.corners.count() == 4:
            calculate_spatial_vectors(room)
            return True
        return False

    @staticmethod
    def reset_room_corners(room_id):
        """
        Clears all corners and resets room to radius-only mode.
        """
        room = VirtualRoom.objects.get(id=room_id)
        room.corners.all().delete()
        room.use_polygon = False
        room.boundary_polygon = None
        room.save()
        return True
