import uuid
import json
from django.db import models
from django.conf import settings


class VirtualRoom(models.Model):
    """
    3D Virtual Classroom model supporting polygon-based boundary validation.

    Supports two validation modes:
    - Legacy: center_lat/center_lng + radius_meters (circular)
    - Polygon: 4 captured corner coordinates forming a 3D classroom boundary

    The polygon mode is activated when corner_coordinates is populated.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='virtual_rooms')
    name = models.CharField(max_length=255)
    building = models.CharField(max_length=100, blank=True)
    floor_number = models.IntegerField(default=0)
    department = models.CharField(max_length=255, blank=True)
    capacity = models.IntegerField(default=60)

    # ── Legacy center-based fields (kept for backward compatibility) ──
    center_lat = models.DecimalField(max_digits=10, decimal_places=7)
    center_lng = models.DecimalField(max_digits=10, decimal_places=7)
    radius_meters = models.FloatField(default=30.0)

    # ── Altitude / Z-axis ──
    min_altitude = models.FloatField(default=0.0)
    max_altitude = models.FloatField(default=50.0)

    # ── 3D Polygon Boundary (4 corners) ──
    # Stored as JSON: [{"lat": ..., "lng": ..., "alt": ..., "accuracy": ...}, ...]
    corner_coordinates = models.JSONField(
        null=True, blank=True,
        help_text='JSON array of 4 corner GPS coordinates [{lat, lng, alt, accuracy}, ...]'
    )

    # ── Room Dimensions (auto-calculated from corners) ──
    estimated_length = models.FloatField(null=True, blank=True, help_text='Meters')
    estimated_width = models.FloatField(null=True, blank=True, help_text='Meters')
    estimated_area = models.FloatField(null=True, blank=True, help_text='Square meters')
    room_orientation = models.FloatField(null=True, blank=True, help_text='Compass heading degrees')

    # ── Validation mode ──
    use_polygon = models.BooleanField(
        default=False,
        help_text='If True, uses polygon boundary. If False, uses radius-based.'
    )

    is_active = models.BooleanField(default=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='created_virtual_rooms')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'virtual_rooms_virtualroom'

    def __str__(self):
        return f"{self.name} ({self.college.name})"

    @property
    def has_polygon(self):
        """Check if this room has valid polygon data."""
        return (
            self.use_polygon
            and self.corner_coordinates is not None
            and len(self.corner_coordinates) >= 3
        )

    def get_corners(self):
        """Return corner coordinates as a list of (lat, lng) tuples."""
        if not self.corner_coordinates:
            return []
        return [
            (float(c['lat']), float(c['lng']))
            for c in self.corner_coordinates
        ]

    def get_altitude_range(self):
        """Get altitude range from corners or from explicit fields."""
        if self.corner_coordinates:
            alts = [float(c.get('alt', 0)) for c in self.corner_coordinates if c.get('alt') is not None]
            if alts:
                return min(alts) - 5.0, max(alts) + 5.0  # 5m buffer per floor
        return float(self.min_altitude), float(self.max_altitude)
