from django.db import models
from django.conf import settings

class StaffProfile(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='staff_profile')
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='staff')
    employee_id = models.CharField(max_length=20, unique=True)
    department = models.ForeignKey('academic.Department', on_delete=models.SET_NULL, null=True, blank=True, related_name='staff')
    designation = models.CharField(max_length=100) # e.g. Professor
    qualification = models.CharField(max_length=255)
    specialization = models.CharField(max_length=255)
    experience_years = models.IntegerField()
    joining_date = models.DateField()
    is_class_teacher = models.BooleanField(default=False)
    class_teacher_division = models.ForeignKey('academic.Division', on_delete=models.SET_NULL, null=True, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.user.get_full_name()} ({self.employee_id})"

