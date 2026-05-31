import os
import django
import sys

# Ensure backend root is in sys.path
backend_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if backend_root not in sys.path:
    sys.path.insert(0, backend_root)

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
django.setup()

from django.contrib.auth import get_user_model
from apps.accounts.models import DeviceRegistry
from apps.students.models import StudentProfile

User = get_user_model()

print("--- USERS ---")
for u in User.objects.all():
    print(f"User ID: {u.id}, Email: {u.email}, Role: {u.role}, DeviceID: '{u.device_id}', IsApproved: {u.is_approved}, IsActive: {u.is_active}")

print("\n--- STUDENT PROFILES ---")
for p in StudentProfile.objects.all():
    print(f"Profile ID: {p.id}, User Email: {p.user.email}, PRN: {p.prn}, Status: {p.approval_status}, Active: {p.is_active}")

print("\n--- DEVICE REGISTRY ---")
for d in DeviceRegistry.objects.all():
    print(f"Registry ID: {d.id}, User Email: {d.user.email}, DeviceID: '{d.device_id}', Active: {d.is_active}, Platform: {d.platform}")
