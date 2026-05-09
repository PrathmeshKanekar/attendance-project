import os
import django
import uuid
from datetime import date, timedelta, time
import sys

# Set up Django environment
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
django.setup()

from apps.tenants.models import SubscriptionPlan, College, CollegeSettings
from apps.accounts.models import User, UserRole
from apps.academic.models import Department, Course, AcademicYear, Semester, Division, Subject, SubjectAllocation
from apps.students.models import StudentProfile, StudentSubjectEnrollment
from apps.staff.models import StaffProfile, ApprovalRequest
from apps.virtual_rooms.models import VirtualRoom
from django.contrib.gis.geos import Point

def seed_master_data():
    print("Starting Master Data Seeding...")

    # 1. Subscription Plan
    plan, _ = SubscriptionPlan.objects.get_or_create(
        name="Enterprise Plan",
        defaults={
            "price_per_month": 9999.00,
            "max_students": 10000,
            "max_staff": 1000,
            "features": {"face_ai": True, "geo_fencing": True, "reports": True}
        }
    )

    # 2. College
    college, created = College.objects.get_or_create(
        code="SC-ERP-01",
        defaults={
            "name": "Smart Campus University",
            "address": "Antigravity HQ, Silicon Valley",
            "city": "Palo Alto",
            "state": "California",
            "pincode": "94301",
            "phone": "1234567890",
            "email": "admin@smartcampus.edu",
            "subscription_plan": plan,
            "subscription_start": date.today(),
            "subscription_end": date.today() + timedelta(days=365),
            "max_students": 5000,
            "max_staff": 500
        }
    )
    if created:
        CollegeSettings.objects.create(college=college, face_verification_enabled=True)

    # 3. Users (Principal First to satisfy the Gate)
    principal_user, _ = User.objects.get_or_create(
        email="principal@smartcampus.edu",
        defaults={
            "mobile": "1111111111",
            "role": UserRole.PRINCIPAL,
            "first_name": "Principal",
            "last_name": "Admin",
            "college": college,
            "is_active": True,
            "is_approved": True
        }
    )
    principal_user.set_password("password123")
    principal_user.save()

    # Manual approval for principal just in case signal created a request
    ApprovalRequest.objects.filter(requested_user=principal_user).update(status='approved')

    admin_user, _ = User.objects.get_or_create(
        email="admin@smartcampus.edu",
        defaults={
            "mobile": "2222222222",
            "role": UserRole.COLLEGE_ADMIN,
            "first_name": "College",
            "last_name": "Admin",
            "college": college,
            "is_active": True,
            "is_approved": True
        }
    )
    admin_user.set_password("password123")
    admin_user.save()

    teacher_user, _ = User.objects.get_or_create(
        email="teacher@smartcampus.edu",
        defaults={
            "mobile": "3333333333",
            "role": UserRole.TEACHER,
            "first_name": "John",
            "last_name": "Teacher",
            "college": college,
            "is_active": True,
            "is_approved": True
        }
    )
    teacher_user.set_password("password123")
    teacher_user.save()
    ApprovalRequest.objects.filter(requested_user=teacher_user).update(status='approved')

    student_user, _ = User.objects.get_or_create(
        email="student@smartcampus.edu",
        defaults={
            "mobile": "4444444444",
            "role": UserRole.STUDENT,
            "first_name": "Jane",
            "last_name": "Student",
            "prn": "STUD-2024-001",
            "college": college,
            "is_active": True,
            "is_approved": True
        }
    )
    student_user.set_password("password123")
    student_user.save()
    ApprovalRequest.objects.filter(requested_user=student_user).update(status='approved')

    # 4. Academic Structure
    dept, _ = Department.objects.get_or_create(
        college=college, name="Computer Science", code="CS", defaults={"hod": teacher_user}
    )
    
    course, _ = Course.objects.get_or_create(
        college=college, department=dept, name="B.Tech Computer Science", code="BTECH-CS",
        defaults={"duration_years": 4, "degree_type": "UG"}
    )
    
    ayear, _ = AcademicYear.objects.get_or_create(
        college=college, name="2024-25",
        defaults={"start_date": date(2024, 6, 1), "end_date": date(2025, 5, 31), "is_current": True}
    )
    
    sem, _ = Semester.objects.get_or_create(
        college=college, course=course, academic_year=ayear, semester_number=1,
        defaults={"start_date": date(2024, 6, 15), "end_date": date(2024, 11, 15)}
    )
    
    div, _ = Division.objects.get_or_create(
        college=college, course=course, semester=sem, name="Div A",
        defaults={"capacity": 60, "class_teacher": teacher_user}
    )
    
    subj, _ = Subject.objects.get_or_create(
        college=college, department=dept, course=course, name="Algorithms", code="CS101",
        defaults={"subject_type": "theory", "credit_hours": 4}
    )
    
    alloc, _ = SubjectAllocation.objects.get_or_create(
        college=college, subject=subj, teacher=teacher_user, division=div, 
        academic_year=ayear, semester=sem
    )

    # 5. Profiles
    StudentProfile.objects.get_or_create(
        user=student_user, college=college, prn_number="STUD-2024-001",
        defaults={
            "roll_number": "01", "department": dept, "course": course, 
            "current_semester": sem, "division": div, "batch_year": 2024,
            "admission_date": date.today(), "blood_group": "O+", "category": "General",
            "address": "Student Hostels", "city": "Palo Alto", "state": "California", "pincode": "94301",
            "parent_name": "Mr. Student", "parent_mobile": "0000000000", "emergency_contact": "0000000000"
        }
    )
    
    StaffProfile.objects.get_or_create(
        user=teacher_user, college=college, employee_id="EMP-101",
        defaults={
            "department": dept, "designation": "Assistant Professor", "joining_date": date.today(),
            "qualification": "Ph.D in CS", "specialization": "Distributed Systems", "experience_years": 10
        }
    )

    # 6. Virtual Room (GPS Verification Test)
    try:
        # X=Lng, Y=Lat
        room, _ = VirtualRoom.objects.get_or_create(
            college=college, name="Main Auditorium", building="Admin Block", floor_number=1, room_number="AUD-01",
            defaults={
                "center_point": Point(73.8567, 18.5204), 
                "length_meters": 50.0,
                "width_meters": 50.0,
                "height_meters": 10.0,
                "altitude_min": 0.0,
                "altitude_max": 1000.0,
                "created_by": admin_user
            }
        )
        print("VirtualRoom created successfully.")
    except Exception as e:
        print(f"Skipping VirtualRoom creation: {e} (GIS may not be configured correctly locally)")

    print("Seeding Complete!")
    print(f"Login with:")
    print(f"Principal: principal@smartcampus.edu / password123")
    print(f"Teacher:   teacher@smartcampus.edu   / password123")
    print(f"Student:   student@smartcampus.edu   / password123 (PRN: STUD-2024-001)")

if __name__ == "__main__":
    seed_master_data()
