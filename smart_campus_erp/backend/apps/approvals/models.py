import uuid
from django.db import models
from django.conf import settings
from apps.accounts.models import ROLE_CHOICES

class ApprovalRequest(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='tenant_approval_requests')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='user_approval_requests')
    requested_role = models.CharField(max_length=30, choices=ROLE_CHOICES)
    status = models.CharField(max_length=20, choices=[('pending', 'Pending'), ('approved', 'Approved'), ('rejected', 'Rejected')], default='pending')
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='approvals_reviewed_by')

    reviewed_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'approvals_request'

    def __str__(self):
        return f"Request by {self.user.email} for {self.requested_role} - {self.status}"
