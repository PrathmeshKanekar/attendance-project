import uuid
from django.db import models
from django.conf import settings

class Notification(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, null=True, blank=True, related_name='notifications')
    recipient = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='notifications')
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='sent_notifications')
    title = models.CharField(max_length=255)
    message = models.TextField()
    notif_type = models.CharField(max_length=50)  # approval / attendance / alert / system
    is_read = models.BooleanField(default=False)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'notifications_notification'

    def __str__(self):
        return f"{self.title} to {self.recipient.email}"

class NoticeBoard(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='notices')
    title = models.CharField(max_length=255)
    content = models.TextField()
    target_roles = models.JSONField(default=list) # ['student', 'teacher']
    target_departments = models.ManyToManyField('academic.Department', blank=True, related_name='notices')
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='notices')
    is_active = models.BooleanField(default=True)
    publish_at = models.DateTimeField()
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'notifications_noticeboard'

    def __str__(self):
        return self.title

