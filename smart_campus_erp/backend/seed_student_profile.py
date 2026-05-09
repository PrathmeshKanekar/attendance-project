import os
import django
import sys
from datetime import date

# Set up Django environment
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
django.setup()

from apps.accounts.models import User
from apps.students.models import StudentProfile
from apps.tenants.models import College
from apps.academic.models import Department, Course

def seed_student_profile():
    try:
        user = User.objects.get(email="student@globaltech.edu")
        college = College.objects.first()
        
        department, _ = Department.objects.get_or_create(
            college=college,
            name="Computer Science",
            code="CS",
            defaults={"description": "CS Dept"}
        )
        
        course, _ = Course.objects.get_or_create(
            department=department,
            college=college,
            name="B.Tech Computer Science",
            code="BTECH-CS",
            defaults={"duration_years": 4}
        )

        profile, created = StudentProfile.objects.get_or_create(
            user=user,
            defaults={
                "college": college,
                "prn_number": "22CS001",
                "roll_number": "101",
                "department": department,
                "course": course,
                "admission_date": date.today(),
                "batch_year": 2022,
                "blood_group": "O+",
                "address": "123 Student St",
                "city": "Mumbai",
                "state": "MH",
                "pincode": "400002",
                "parent_name": "Mr. Johnson",
                "parent_mobile": "9999999999",
                "emergency_contact": "9999999998",
                "category": "General"
            }
        )
        
        print(f"StudentProfile ID: {profile.id}")
        user.prn = "22CS001"
        user.save()
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    seed_student_profile()
