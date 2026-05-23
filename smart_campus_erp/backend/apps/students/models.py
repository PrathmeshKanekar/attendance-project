import uuid
from django.db import models
from django.conf import settings

class StudentProfile(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='student_profile')
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='student_profiles')
    division = models.ForeignKey('academic.Division', on_delete=models.SET_NULL, null=True, related_name='students')
    course = models.ForeignKey('academic.Course', on_delete=models.SET_NULL, null=True, related_name='students')
    academic_year = models.ForeignKey('academic.AcademicYear', on_delete=models.SET_NULL, null=True, related_name='students')
    prn = models.CharField(max_length=50, unique=True)
    roll_number = models.CharField(max_length=20)
    year_of_study = models.IntegerField()
    date_of_birth = models.DateField(null=True, blank=True)
    APPROVAL_CHOICES = [
        ('PENDING_APPROVAL', 'Pending Approval'),
        ('APPROVED', 'Approved'),
        ('REJECTED', 'Rejected'),
    ]
    approval_status = models.CharField(max_length=20, choices=APPROVAL_CHOICES, default='PENDING_APPROVAL')
    approved_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='approved_students')
    approved_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.TextField(blank=True, null=True)
    
    is_active = models.BooleanField(default=True)
    face_registered = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'students_profile'

    def __str__(self):
        return f"{self.user.email} ({self.prn})"

class StudentSubjectEnrollment(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    student = models.ForeignKey(StudentProfile, on_delete=models.CASCADE, related_name='enrollments')
    subject_allocation = models.ForeignKey('academic.SubjectAllocation', on_delete=models.CASCADE, related_name='enrollments')
    academic_year = models.ForeignKey('academic.AcademicYear', on_delete=models.CASCADE, related_name='student_enrollments')
    enrolled_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('student', 'subject_allocation')
        db_table = 'students_subject_enrollment'

    def __str__(self):
        return f"{self.student} enrolled in {self.subject_allocation}"
