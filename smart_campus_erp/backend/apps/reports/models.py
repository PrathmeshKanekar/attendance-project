import uuid
from django.db import models
from django.conf import settings

class GeneratedReport(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='generated_reports')
    generated_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='generated_reports')
    report_type = models.CharField(max_length=50)   # attendance / defaulter / subject / teacher
    filters_json = models.JSONField(default=dict)
    file_path = models.CharField(max_length=500)
    format = models.CharField(max_length=10, default='pdf')  # pdf / excel
    generated_at = models.DateTimeField(auto_now_add=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'reports_generated'

    def __str__(self):
        return f"{self.report_type} report by {self.generated_by.email}"
