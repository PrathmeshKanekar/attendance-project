import uuid
from django.db import models
from django.conf import settings
from django.utils import timezone

class VirtualRoom(models.Model):
    STATUS_CHOICES = [
        ('draft', 'Draft'),
        ('created', 'Created'),
        ('validated', 'Validated'),
        ('certified', 'Certified'),
        ('active', 'Active'),
        ('deactivated', 'Deactivated'),
    ]
    LOCATION_METHOD_CHOICES = [
        ('gps', 'GPS Capture'),
        ('manual', 'Manual Coordinates'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='virtual_rooms')
    name = models.CharField(max_length=255)
    building = models.CharField(max_length=255, blank=True, default='')
    department = models.CharField(max_length=255, blank=True, default='')
    floor_number = models.IntegerField(default=0)
    capacity = models.IntegerField(default=60)

    # ── New creation workflow fields ────────────────────────────────────────
    room_number = models.CharField(max_length=50, blank=True, default='')
    description = models.TextField(blank=True, default='')
    location_method = models.CharField(max_length=10, choices=LOCATION_METHOD_CHOICES, default='gps')
    gps_accuracy = models.FloatField(null=True, blank=True)
    gps_health_score = models.FloatField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='draft')
    boundary_geojson = models.JSONField(default=dict, blank=True)
    width_meters = models.FloatField(default=10.0)
    length_meters = models.FloatField(default=12.0)
    is_deleted = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)
    
    # Geographic centroid
    center_lat = models.FloatField(null=True, blank=True)
    center_lng = models.FloatField(null=True, blank=True)
    
    # Pre-calculated High-Precision Spatial Metrics
    area_sq_meters = models.FloatField(default=0.0)
    perimeter_meters = models.FloatField(default=0.0)
    orientation_degrees = models.FloatField(default=0.0)
    reconstruction_quality = models.FloatField(default=100.0)
    
    # Scalable JSON field for SLAM, Unity AR anchors, BLE Beacons, and WiFi fingerprints
    spatial_metadata = models.JSONField(default=dict, blank=True)
    
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='created_rooms')
    created_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = 'virtual_room'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['college', 'department']),
            models.Index(fields=['college', 'status']),
            models.Index(fields=['is_deleted']),
        ]

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
    
    # Store complete accelerometer, gyroscope and compass readings during capture
    sensor_telemetry = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = 'room_corner'
        ordering = ['room', 'corner_index']
        unique_together = ('room', 'corner_index')

    def __str__(self):
        return f"{self.room.name} - Corner {self.corner_index} ({self.latitude}, {self.longitude})"


class RoomPresence(models.Model):
    """
    Live occupancy tracker. One active row per user currently inside a room.
    Row is updated on each heartbeat; exited when exit_time is set.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room = models.ForeignKey(
        'VirtualRoom', on_delete=models.CASCADE, related_name='presence_records'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='room_presence'
    )
    college = models.ForeignKey(
        'tenants.College', on_delete=models.CASCADE, related_name='room_presence'
    )

    # Location at last heartbeat
    last_lat = models.DecimalField(max_digits=10, decimal_places=7)
    last_lng = models.DecimalField(max_digits=10, decimal_places=7)
    last_accuracy = models.FloatField(default=10.0)

    # Lifecycle
    entered_at = models.DateTimeField(auto_now_add=True)
    exit_time = models.DateTimeField(null=True, blank=True)
    last_heartbeat = models.DateTimeField(auto_now=True)

    is_inside = models.BooleanField(default=True)  # False when exited
    device_id = models.CharField(max_length=255, blank=True)

    class Meta:
        db_table = 'room_presence'
        # One active presence record per user per room at a time
        unique_together = ('room', 'user', 'entered_at')
        indexes = [
            models.Index(fields=['room', 'is_inside']),
            models.Index(fields=['user', 'is_inside']),
        ]

    def mark_exited(self):
        self.is_inside = False
        self.exit_time = timezone.now()
        self.save(update_fields=['is_inside', 'exit_time'])

    def __str__(self):
        status = 'inside' if self.is_inside else 'exited'
        return f"{self.user.email} — {self.room.name} ({status})"


class RoomEntryLog(models.Model):
    """
    Immutable audit log of every entry and exit event.
    Presence model is mutable; this is the permanent record.
    """
    ENTRY = 'entry'
    EXIT = 'exit'
    HEARTBEAT = 'heartbeat'
    EVENT_CHOICES = [(ENTRY, 'Entry'), (EXIT, 'Exit'), (HEARTBEAT, 'Heartbeat')]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room = models.ForeignKey(
        'VirtualRoom', on_delete=models.CASCADE, related_name='entry_logs'
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='room_entry_logs'
    )
    college = models.ForeignKey(
        'tenants.College', on_delete=models.CASCADE, related_name='room_entry_logs'
    )
    event = models.CharField(max_length=20, choices=EVENT_CHOICES)
    lat = models.DecimalField(max_digits=10, decimal_places=7)
    lng = models.DecimalField(max_digits=10, decimal_places=7)
    accuracy = models.FloatField(default=10.0)
    is_polygon_validated = models.BooleanField(default=False)
    timestamp = models.DateTimeField(auto_now_add=True)
    device_id = models.CharField(max_length=255, blank=True)
    meta = models.JSONField(default=dict, blank=True)  # validation_mode, slack, etc.

    class Meta:
        db_table = 'room_entry_log'
        ordering = ['-timestamp']
        indexes = [
            models.Index(fields=['room', 'event', 'timestamp']),
            models.Index(fields=['user', 'timestamp']),
        ]

    def __str__(self):
        return f"{self.event.upper()}: {self.user.email} @ {self.room.name}"


# ─── Append-Only Audit Log ─────────────────────────────────────────────────────

class VirtualRoomAuditLog(models.Model):
    """Immutable audit trail for all virtual room lifecycle events."""
    EVENT_CHOICES = [
        ('created', 'Created'),
        ('validated', 'Validated'),
        ('certified', 'Certified'),
        ('activated', 'Activated'),
        ('deactivated', 'Deactivated'),
        ('duplicate_blocked', 'Duplicate Blocked'),
        ('security_flagged', 'Security Flagged'),
        ('edit', 'Edited'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room = models.ForeignKey(
        VirtualRoom, on_delete=models.CASCADE,
        related_name='audit_logs', null=True, blank=True,
    )
    event_type = models.CharField(max_length=30, choices=EVENT_CHOICES)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='room_audit_actions',
    )
    actor_role = models.CharField(max_length=50, blank=True, default='')
    event_data = models.JSONField(default=dict, blank=True)
    device_info = models.JSONField(default=dict, blank=True)
    gps_snapshot = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'virtual_room_audit_log'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['room', 'event_type']),
            models.Index(fields=['actor', 'created_at']),
        ]
        # Conceptual: append-only, no UPDATE/DELETE in application code

    def __str__(self):
        return f"{self.event_type}: Room {self.room_id} by {self.actor_id}"


class VirtualRoomSecurityLog(models.Model):
    """Immutable security event log for GPS anti-spoof detections."""
    FLAG_CHOICES = [
        ('mock_location', 'Mock Location Detected'),
        ('fake_gps', 'Fake GPS App Detected'),
        ('coordinate_jump', 'Impossible Coordinate Jump'),
        ('rapid_oscillation', 'Rapid Coordinate Oscillation'),
        ('suspicious_coordinates', 'Suspicious Coordinates'),
        ('invalid_geometry', 'Invalid Geometry'),
        ('spoofing_suspected', 'Spoofing Suspected'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room = models.ForeignKey(
        VirtualRoom, on_delete=models.CASCADE,
        related_name='security_logs', null=True, blank=True,
    )
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='room_security_flags',
    )
    flag_type = models.CharField(max_length=30, choices=FLAG_CHOICES)
    flag_detail = models.JSONField(default=dict, blank=True)
    device_info = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'virtual_room_security_log'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['room', 'flag_type']),
            models.Index(fields=['actor', 'created_at']),
        ]

    def __str__(self):
        return f"{self.flag_type}: Room {self.room_id} by {self.actor_id}"
