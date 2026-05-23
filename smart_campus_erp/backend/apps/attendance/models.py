import uuid
from django.db import models
from django.conf import settings

SESSION_STATUS = [
    ('scheduled', 'Scheduled'),
    ('active', 'Active'),
    ('ended', 'Ended'),
    ('cancelled', 'Cancelled')
]

class AttendanceSession(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='attendance_sessions')
    subject_allocation = models.ForeignKey('academic.SubjectAllocation', on_delete=models.CASCADE, related_name='sessions')
    virtual_room = models.ForeignKey('virtual_rooms.VirtualRoom', on_delete=models.SET_NULL, null=True, blank=True, related_name='attendance_sessions')
    teacher = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='created_sessions')
    session_code = models.CharField(max_length=10, unique=True)  # random 6-char code
    status = models.CharField(max_length=20, choices=SESSION_STATUS, default='active')
    scheduled_start = models.DateTimeField()
    scheduled_end = models.DateTimeField()
    actual_start = models.DateTimeField(null=True, blank=True)
    actual_end = models.DateTimeField(null=True, blank=True)
    total_students = models.IntegerField(default=0)
    present_count = models.IntegerField(default=0)
    # Teacher's location at the time of session creation
    teacher_lat = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    teacher_lng = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    teacher_altitude = models.FloatField(null=True, blank=True)
    teacher_accuracy = models.FloatField(null=True, blank=True)

    radius_meters = models.FloatField(default=30.0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'attendance_session'

    def __str__(self):
        return f"Session: {self.session_code} - {self.subject_allocation}"

ATTENDANCE_STATUS = [
    ('present', 'Present'),
    ('absent', 'Absent'),
    ('manual', 'Manual'),
    ('late', 'Late')
]

class AttendanceLog(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey(AttendanceSession, on_delete=models.CASCADE, related_name='logs')
    student = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='attendance_logs')
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='attendance_logs')
    status = models.CharField(max_length=20, choices=ATTENDANCE_STATUS, default='present')
    marked_at = models.DateTimeField(auto_now_add=True)
    marked_lat = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    marked_lng = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    marked_altitude = models.FloatField(null=True, blank=True)
    device_id = models.CharField(max_length=255, blank=True)
    gps_accuracy = models.FloatField(default=0.0)
    is_mocked_gps = models.BooleanField(default=False)
    security_flags = models.JSONField(default=dict, blank=True)
    face_confidence = models.FloatField(null=True, blank=True)
    blink_count = models.IntegerField(default=0)
    compass_direction = models.FloatField(null=True, blank=True)
    device_movement = models.CharField(max_length=100, blank=True)
    is_verified_gps = models.BooleanField(default=False)
    is_verified_face = models.BooleanField(default=False)
    manual_reason = models.TextField(blank=True)
    marked_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='manually_marked')
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('session', 'student')
        db_table = 'attendance_log'

    def __str__(self):
        return f"{self.student.email} - {self.session.session_code} ({self.status})"

class ManualAttendanceRequest(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey(AttendanceSession, on_delete=models.CASCADE, related_name='manual_requests')
    student = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='attendance_manual_requests')
    reason = models.TextField()
    status = models.CharField(max_length=20, choices=[('pending', 'Pending'), ('approved', 'Approved'), ('rejected', 'Rejected')], default='pending')
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='reviewed_requests')
    reviewed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'attendance_manual_request'

    def __str__(self):
        return f"Manual Request: {self.student.email} for session {self.session.session_code}"
