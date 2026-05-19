import uuid
from django.db import models
from django.conf import settings

class VirtualRoom(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='virtual_rooms')
    name = models.CharField(max_length=255)
    building = models.CharField(max_length=255, blank=True, default='')
    department = models.CharField(max_length=255, blank=True, default='')
    floor_number = models.IntegerField(default=0)
    capacity = models.IntegerField(default=60)
    center_lat = models.FloatField(null=True, blank=True)
    center_lng = models.FloatField(null=True, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='created_rooms')
    created_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = 'virtual_room'
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.name} ({self.building})"

    @property
    def has_polygon(self):
        return self.corners.count() == 4

class RoomCorner(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room = models.ForeignKey(VirtualRoom, on_delete=models.CASCADE, related_name='corners')
    corner_index = models.IntegerField()
    latitude = models.FloatField()
    longitude = models.FloatField()
    altitude = models.FloatField(default=0.0)
    heading = models.FloatField(default=0.0)
    accuracy = models.FloatField(default=0.0)
    accuracy_meters = models.FloatField(default=0.0)

    class Meta:
        db_table = 'room_corner'
        ordering = ['room', 'corner_index']
        unique_together = ('room', 'corner_index')

    def __str__(self):
        return f"{self.room.name} - Corner {self.corner_index} ({self.latitude}, {self.longitude})"
