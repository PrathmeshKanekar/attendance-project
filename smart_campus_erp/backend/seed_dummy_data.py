import os
import django
from datetime import date, timedelta
import sys

# Set up Django environment
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
django.setup()

from apps.tenants.models import SubscriptionPlan, College, CollegeSettings
from apps.accounts.models import User, UserRole

def seed_data():
    print("Creating Subscription Plan...")
    plan, created = SubscriptionPlan.objects.get_or_create(
        name="Premium Plan",
        defaults={
            "price_per_month": 5000.00,
            "max_students": 5000,
            "max_staff": 500,
            "features": {"gps": True, "sms": True}
        }
    )

    print("Creating Dummy College...")
    college, created = College.objects.get_or_create(
        code="DUMMY-01",
        defaults={
            "name": "Global Tech Institute",
            "address": "123 Tech Park",
            "city": "Mumbai",
            "state": "Maharashtra",
            "pincode": "400001",
            "phone": "9876543210",
            "email": "info@globaltech.edu",
            "subscription_plan": plan,
            "subscription_start": date.today(),
            "subscription_end": date.today() + timedelta(days=365),
            "max_students": 1000,
            "max_staff": 100
        }
    )
    
    if created:
        CollegeSettings.objects.create(college=college)

    print("Creating Dummy Users...")
    users = [
        {"email": "admin@globaltech.edu", "mobile": "9999999901", "role": UserRole.COLLEGE_ADMIN, "first_name": "System", "last_name": "Admin"},
        {"email": "principal@globaltech.edu", "mobile": "9999999902", "role": UserRole.PRINCIPAL, "first_name": "Dr. John", "last_name": "Doe"},
        {"email": "teacher@globaltech.edu", "mobile": "9999999903", "role": UserRole.TEACHER, "first_name": "Alice", "last_name": "Smith"},
        {"email": "student@globaltech.edu", "mobile": "9999999904", "role": UserRole.STUDENT, "first_name": "Bob", "last_name": "Johnson"},
    ]

    for u_data in users:
        user, u_created = User.objects.get_or_create(
            email=u_data["email"],
            defaults={
                "mobile": u_data["mobile"],
                "role": u_data["role"],
                "first_name": u_data["first_name"],
                "last_name": u_data["last_name"],
                "college": college,
                "is_active": True,
                "is_approved": True
            }
        )
        if u_created:
            user.set_password("password123")
            user.save()
            print(f"Created {u_data['role']}: {u_data['email']} / password123")
        else:
            print(f"{u_data['role']} already exists: {u_data['email']}")

    print("Dummy data seeding complete!")

if __name__ == "__main__":
    seed_data()
