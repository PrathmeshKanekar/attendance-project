import uuid
from django.db import models
from django.conf import settings

class VirtualRoom(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='virtual_rooms')
    name = models.CharField(max_length=255)
    building = models.CharField(max_length=100, blank=True)
    floor_number = models.IntegerField(default=0)
    center_lat = models.DecimalField(max_digits=10, decimal_places=7)
    center_lng = models.DecimalField(max_digits=10, decimal_places=7)
    radius_meters = models.FloatField(default=30.0)
    min_altitude = models.FloatField(default=0.0)
    max_altitude = models.FloatField(default=50.0)
    is_active = models.BooleanField(default=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='created_virtual_rooms')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'virtual_rooms_virtualroom'

    def __str__(self):
        return f"{self.name} ({self.college.name})"
