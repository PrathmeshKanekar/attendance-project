import uuid
from django.db import models

class College(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=255)
    code = models.CharField(max_length=50, unique=True)
    email_domain = models.CharField(max_length=100, unique=True)
    address = models.TextField()
    phone = models.CharField(max_length=20, blank=True)
    logo_url = models.CharField(max_length=500, blank=True, null=True, default='')
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'tenants_college'

    def __str__(self):
        return f"{self.name} ({self.code})"
