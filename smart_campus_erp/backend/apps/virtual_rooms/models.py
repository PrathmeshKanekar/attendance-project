"""
Virtual Room Models — Production 3D Geo-fenced Attendance System
================================================================
Supports:
  • PostGIS polygon boundary (2D footprint)
  • Altitude Z-axis range per floor
  • Sensor-fused corner capture (accelerometer / gyro / magnetometer)
  • Derived spatial vectors for local-coordinate attendance validation
  • Forensic anti-spoofing log per check
"""
import uuid
from django.db import models
from django.conf import settings
from django.contrib.gis.db import models as gis_models


class VirtualRoom(models.Model):
    """
    3D Virtual Classroom with PostGIS polygon footprint + altitude range.
    """
    id          = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college     = models.ForeignKey(
        'tenants.College', on_delete=models.CASCADE, related_name='virtual_rooms'
    )
    room_name   = models.CharField(max_length=255)
    building    = models.CharField(max_length=100, blank=True)
    floor       = models.IntegerField(default=0)
    department  = models.CharField(max_length=255, blank=True)
    capacity    = models.IntegerField(default=60)

    # ── Spatial footprint (PostGIS) ─────────────────────────────────
    polygon     = gis_models.PolygonField(null=True, blank=True, srid=4326)
    centroid    = gis_models.PointField(null=True, blank=True, srid=4326)

    # ── Altitude / Z-axis ────────────────────────────────────────────
    min_altitude      = models.FloatField(default=0.0)
    max_altitude      = models.FloatField(default=50.0)

    # ── Orientation & Axes (Migration 0004 fields) ───────────────────
    x_axis_vector = models.JSONField(null=True, blank=True)
    y_axis_vector = models.JSONField(null=True, blank=True)
    z_axis_vector = models.JSONField(null=True, blank=True)

    # ── Legacy / Center mode ─────────────────────────────────────────
    center_lat    = models.FloatField(null=True, blank=True)
    center_lng    = models.FloatField(null=True, blank=True)

    # ── Advanced Spatial Metadata ────────────────────────────────────
    normalized_coordinates = models.JSONField(null=True, blank=True)
    orientation_matrix     = models.JSONField(null=True, blank=True)
    room_dimensions        = models.JSONField(null=True, blank=True)
    polygon_area           = models.FloatField(null=True, blank=True)

    is_active   = models.BooleanField(default=True)
    created_by  = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='created_virtual_rooms'
    )
    created_at  = models.DateTimeField(auto_now_add=True)
    updated_at  = models.DateTimeField(auto_now=True)

    class Meta:
        db_table  = 'virtual_rooms_virtualroom'
        ordering  = ['building', 'floor', 'room_name']

    def __str__(self):
        return f"{self.room_name} — {self.building} F{self.floor} ({self.college})"

    # Aliases and Properties for complete compatibility
    @property
    def name(self):
        return self.room_name

    @name.setter
    def name(self, val):
        self.room_name = val

    @property
    def floor_number(self):
        return self.floor

    @floor_number.setter
    def floor_number(self, val):
        self.floor = val

    @property
    def boundary_polygon(self):
        return self.polygon

    @boundary_polygon.setter
    def boundary_polygon(self, val):
        self.polygon = val

    @property
    def area(self):
        return self.polygon_area

    @area.setter
    def area(self, val):
        self.polygon_area = val

    @property
    def has_polygon(self):
        return self.polygon is not None

    @property
    def corner_count(self):
        return self.corners.count()

    @property
    def length(self):
        return (self.room_dimensions or {}).get("length")

    @property
    def width(self):
        return (self.room_dimensions or {}).get("width")

    @property
    def radius_meters(self):
        return 30.0

    @property
    def altitude_tolerance(self):
        return 4.0

    @property
    def use_polygon(self):
        return self.polygon is not None

    @property
    def spatial_vectors(self):
        class MockSpatialVector:
            def __init__(self, room):
                self.room = room
            @property
            def origin_point(self):
                corners = self.room.corners.all().order_by("corner_index")
                if corners.exists():
                    c1 = corners[0]
                    return {"lat": c1.lat, "lng": c1.lng, "alt": c1.altitude}
                return {"lat": 0.0, "lng": 0.0, "alt": 0.0}
            @property
            def x_axis_vector(self):
                return self.room.x_axis_vector
            @property
            def y_axis_vector(self):
                return self.room.y_axis_vector
            @property
            def z_axis_vector(self):
                return self.room.z_axis_vector
            @property
            def x_extent(self):
                return self.room.length or 0.0
            @property
            def y_extent(self):
                return self.room.width or 0.0
        return MockSpatialVector(self)


class RoomCorner(models.Model):
    """
    One physical corner of the room, captured on-device.
    Stores full sensor snapshot for anti-spoofing forensics.
    """
    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room         = models.ForeignKey(VirtualRoom, on_delete=models.CASCADE, related_name='corners')
    corner_index = models.IntegerField(help_text='1 to 4')

    latitude     = models.FloatField()
    longitude    = models.FloatField()
    altitude     = models.FloatField()
    accuracy     = models.FloatField()

    heading      = models.FloatField()
    pitch        = models.FloatField()
    roll         = models.FloatField()
    yaw          = models.FloatField()

    accelerometer  = models.JSONField(null=True, blank=True)
    gyroscope      = models.JSONField(null=True, blank=True)
    magnetic_field = models.JSONField(null=True, blank=True)

    timestamp    = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table      = 'virtual_rooms_roomcorner'
        ordering      = ['corner_index']
        unique_together = ('room', 'corner_index')

    def __str__(self):
        return f"Corner {self.corner_index} of {self.room.room_name}"

    @property
    def lat(self) -> float:
        return self.latitude

    @property
    def lng(self) -> float:
        return self.longitude

    @property
    def location(self):
        from django.contrib.gis.geos import Point
        return Point(self.longitude, self.latitude)


class SpatialMetadata(models.Model):
    """
    Metadata for spatial validation caching.
    """
    room = models.OneToOneField(
        VirtualRoom, on_delete=models.CASCADE, related_name='spatial_metadata'
    )
    metadata = models.JSONField(default=dict)
    last_updated = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'virtual_rooms_spatialmetadata'

    def __str__(self):
        return f"SpatialMetadata for {self.room.room_name}"


class AttendanceLocationLog(models.Model):
    """
    Immutable forensic log of every location check.
    Used for anti-spoofing audits and dispute resolution.
    """
    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room         = models.ForeignKey(VirtualRoom, on_delete=models.SET_NULL, null=True)
    user         = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True)

    submitted_lat = models.FloatField()
    submitted_lng = models.FloatField()
    submitted_alt = models.FloatField()
    gps_accuracy  = models.FloatField(null=True, blank=True)

    is_valid       = models.BooleanField()
    validation_mode = models.CharField(max_length=20)
    local_x        = models.FloatField(null=True)
    local_y        = models.FloatField(null=True)
    local_z        = models.FloatField(null=True)
    confidence     = models.FloatField(null=True)
    spoof_flags    = models.JSONField(default=list)
    sensor_snapshot = models.JSONField(null=True, blank=True)

    checked_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'virtual_rooms_attendancelocationlog'
        ordering = ['-checked_at']

    def __str__(self):
        status = 'VALID' if self.is_valid else 'INVALID'
        return f"{status} check — {self.user} @ {self.room}"