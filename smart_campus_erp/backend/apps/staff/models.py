from django.db import models
from django.conf import settings
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.utils import timezone
from django.core.exceptions import ValidationError

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

class ApprovalRequest(models.Model):
    class ApprovalStatus(models.TextChoices):
        PENDING = 'pending', 'Pending'
        APPROVED = 'approved', 'Approved'
        REJECTED = 'rejected', 'Rejected'
        
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='approval_requests')
    requested_user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='user_approvals')
    requested_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='created_approvals')
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='reviewed_approvals')
    status = models.CharField(max_length=20, choices=ApprovalStatus.choices, default=ApprovalStatus.PENDING)
    rejection_reason = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)

    def save(self, *args, **kwargs):
        if self.status == self.ApprovalStatus.APPROVED and not self.reviewed_at:
            # Check: if college has no Principal yet, reject approval requests for Teacher/HOD/Staff
            # except if the requested user IS the principal or it's a college admin
            if self.requested_user.role in ['teacher', 'hod', 'other_staff']:
                has_principal = self.college.users.filter(role='principal', is_active=True).exists()
                if not has_principal:
                    raise ValidationError("College must have an active Principal before approving other staff.")
            
            self.reviewed_at = timezone.now()
            # Activate user
            user = self.requested_user
            user.is_active = True
            user.is_approved = True
            user.approved_by = self.reviewed_by
            user.approved_at = self.reviewed_at
            user.save()
            
        elif self.status == self.ApprovalStatus.REJECTED and not self.reviewed_at:
            self.reviewed_at = timezone.now()
            
        super().save(*args, **kwargs)

    def __str__(self):
        return f"Request for {self.requested_user.email} - {self.status}"

# Signals to enforce automatic approval request creation
@receiver(post_save, sender=settings.AUTH_USER_MODEL)
def create_approval_request(sender, instance, created, **kwargs):
    if created:
        # Rules: No approval request for super_admin and college_admin
        if instance.role not in ['super_admin', 'college_admin']:
            # For HOD/Teacher/Student etc
            if instance.college:
                # We need to know who created this user. 
                # This is tricky in a signal. Usually handled in the View or a Service.
                # However, for the sake of the rule enforcement:
                ApprovalRequest.objects.create(
                    college=instance.college,
                    requested_user=instance,
                    requested_by=instance # Defaulting to self if unknown, ideally set by view
                )
