from django.db import models
from django.conf import settings
import uuid

class AuditLog(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, null=True, blank=True, related_name='audit_logs')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='audit_logs')
    
    action = models.CharField(max_length=100, db_index=True) # e.g. 'attendance.mark'
    resource_type = models.CharField(max_length=100) # e.g. 'AttendanceLog'
    resource_id = models.CharField(max_length=255)
    
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    device_id = models.CharField(max_length=255, blank=True)
    user_agent = models.CharField(max_length=500, blank=True)
    
    request_data = models.JSONField(null=True, blank=True)
    response_status = models.IntegerField(null=True, blank=True)
    
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ['-timestamp']

    def __str__(self):
        return f"{self.action} by {self.user} at {self.timestamp}"
