import uuid
from django.db import models
from django.conf import settings

class VirtualRoom(models.Model):
    """
    Simple geo-coordinate based virtual room system.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey(
        'tenants.College', on_delete=models.CASCADE, related_name='virtual_rooms',
        null=True, blank=True
    )
    name = models.CharField(max_length=255)
    building = models.CharField(max_length=100, blank=True, null=True)
    department = models.CharField(max_length=255, blank=True, null=True)
    floor_number = models.IntegerField(default=0)
    capacity = models.IntegerField(default=60)
    
    # Auto-calculated center coordinates from the 4 corners
    center_lat = models.FloatField(default=0.0)
    center_lng = models.FloatField(default=0.0)
    
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='created_virtual_rooms'
    )
    created_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = 'virtual_rooms_virtualroom'
        ordering = ['building', 'floor_number', 'name']

    def __str__(self):
        return f"{self.name} — {self.building} F{self.floor_number}"

    # Properties for backward compatibility with other components
    @property
    def room_name(self):
        return self.name

    @property
    def floor(self):
        return self.floor_number

    @property
    def has_polygon(self):
        return self.corners.count() >= 4


class RoomCorner(models.Model):
    """
    Exactly 4 corners of a VirtualRoom captured directly from the mobile app GPS.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room = models.ForeignKey(VirtualRoom, on_delete=models.CASCADE, related_name='corners')
    corner_index = models.IntegerField(help_text='1 to 4')
    
    latitude = models.FloatField()
    longitude = models.FloatField()
    altitude = models.FloatField(default=0.0)
    heading = models.FloatField(default=0.0)
    accuracy = models.FloatField(default=0.0)

    class Meta:
        db_table = 'virtual_rooms_roomcorner'
        ordering = ['corner_index']
        unique_together = ('room', 'corner_index')

    def __str__(self):
        return f"Corner {self.corner_index} of {self.room.name}"