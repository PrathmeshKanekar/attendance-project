import os
import django
import sys

# Set up Django environment
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.base')
django.setup()

from apps.accounts.models import User, UserRole

def seed_superadmin():
    print("Seeding Super Admin Credentials...")
    
    email = "superadmin@smartcampus.edu"
    password = "password123"
    
    user, created = User.objects.get_or_create(
        email=email,
        defaults={
            "first_name": "Super",
            "last_name": "Admin",
            "role": UserRole.SUPER_ADMIN,
            "is_staff": True,
            "is_superuser": True,
            "is_active": True,
            "is_approved": True,
        }
    )
    
    user.set_password(password)
    user.save()
    
    if created:
        print(f"Super Admin created: {email} / {password}")
    else:
        print(f"Super Admin credentials updated: {email} / {password}")

if __name__ == "__main__":
    seed_superadmin()
