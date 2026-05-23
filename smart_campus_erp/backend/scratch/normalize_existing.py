import os
import django
import sys

backend_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if backend_root not in sys.path:
    sys.path.insert(0, backend_root)

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
django.setup()

from django.contrib.auth import get_user_model
from apps.accounts.models import DeviceRegistry

User = get_user_model()

print("Normalizing Users...")
for u in User.objects.all():
    if u.device_id:
        print(f"Normalizing user: {u.email} ({u.device_id})")
        u.save(update_fields=['device_id'])

print("Normalizing DeviceRegistries...")
for d in DeviceRegistry.objects.all():
    print(f"Normalizing device registry for: {d.user.email} ({d.device_id})")
    d.save()

print("All done!")
