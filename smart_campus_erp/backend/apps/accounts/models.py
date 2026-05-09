import uuid
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin, BaseUserManager
from django.db import models

ROLE_CHOICES = [
    ('super_admin', 'Super Admin'),
    ('college_admin', 'College Admin'),
    ('principal', 'Principal'),
    ('hod', 'HOD'),
    ('teacher', 'Teacher'),
    ('student', 'Student'),
    ('lab_assistant', 'Lab Assistant'),
]

class UserRole(models.TextChoices):
    SUPER_ADMIN = 'super_admin', 'Super Admin'
    COLLEGE_ADMIN = 'college_admin', 'College Admin'
    PRINCIPAL = 'principal', 'Principal'
    HOD = 'hod', 'HOD'
    TEACHER = 'teacher', 'Teacher'
    STUDENT = 'student', 'Student'
    LAB_ASSISTANT = 'lab_assistant', 'Lab Assistant'
    OFFICE_STAFF = 'office_staff', 'Office Staff'
    OTHER_STAFF = 'other_staff', 'Other Staff'


class UserManager(BaseUserManager):
    def create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError('The Email field must be set')
        # Consistently lowercase the entire email to avoid case-sensitivity login issues
        email = email.strip().lower()
        user = self.model(email=email, **extra_fields)
        if password:
            user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)
        extra_fields.setdefault('is_approved', True)
        extra_fields.setdefault('role', 'super_admin')
        return self.create_user(email, password, **extra_fields)

class User(AbstractBaseUser, PermissionsMixin):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True)
    first_name = models.CharField(max_length=100, blank=True)
    last_name = models.CharField(max_length=100, blank=True)
    phone = models.CharField(max_length=20, blank=True)
    role = models.CharField(max_length=30, choices=ROLE_CHOICES, default='student')
    college = models.ForeignKey('tenants.College', null=True, blank=True, on_delete=models.SET_NULL, related_name='users')
    profile_photo = models.CharField(max_length=500, blank=True)
    is_active = models.BooleanField(default=False)
    is_approved = models.BooleanField(default=False)
    approved_by = models.ForeignKey('self', null=True, blank=True, on_delete=models.SET_NULL, related_name='approved_users')
    approved_at = models.DateTimeField(null=True, blank=True)
    is_staff = models.BooleanField(default=False)
    device_id = models.CharField(max_length=255, blank=True)
    last_login_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []

    class Meta:
        db_table = 'accounts_user'

    def __str__(self):
        return f"{self.email} ({self.role})"

    def get_full_name(self):
        """Returns first_name + last_name with a space in between."""
        full_name = f"{self.first_name} {self.last_name}".strip()
        return full_name if full_name else self.email

    def get_short_name(self):
        """Returns the first name."""
        return self.first_name if self.first_name else self.email

    @property
    def initials(self):
        """Returns user initials for UI avatars."""
        first = self.first_name[0] if self.first_name else ""
        last = self.last_name[0] if self.last_name else ""
        if not first and not last:
            return self.email[0].upper()
        return f"{first}{last}".upper()


class DeviceRegistry(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='devices')
    device_id = models.CharField(max_length=255)
    device_name = models.CharField(max_length=255, blank=True)
    platform = models.CharField(max_length=20)  # android / ios
    is_active = models.BooleanField(default=True)
    registered_at = models.DateTimeField(auto_now_add=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('user', 'device_id')
        db_table = 'accounts_device_registry'

    def __str__(self):
        return f"{self.user.email} - {self.device_id}"
