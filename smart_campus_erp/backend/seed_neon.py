import os
import django
import uuid
from datetime import date, timedelta
import sys

# Set up Django environment
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.base')
django.setup()

from apps.tenants.models import College
from apps.accounts.models import User, UserRole
from apps.academic.models import Department, Course, AcademicYear, Semester, Division, Subject, SubjectAllocation
from apps.students.models import StudentProfile, StudentSubjectEnrollment
from apps.staff.models import StaffProfile, ApprovalRequest

def seed_neon():
    print("Starting Neon Database Seeding...")

    # 1. College
    college, created = College.objects.get_or_create(
        code="SC-ERP-01",
        defaults={
            "name": "Smart Campus University",
            "address": "Silicon Valley, CA",
            "phone": "1234567890",
            "email_domain": "smartcampus.edu",
            "is_active": True
        }
    )
    print(f"College: {college.name} ({'Created' if created else 'Exists'})")

    # 2. Users (Principal First)
    principal_user, created = User.objects.get_or_create(
        email="principal@smartcampus.edu",
        defaults={
            "phone": "1111111111",
            "role": UserRole.PRINCIPAL,
            "first_name": "Principal",
            "last_name": "Admin",
            "college": college,
            "is_active": True,
            "is_approved": True
        }
    )
    if created:
        principal_user.set_password("password123")
        principal_user.save()
    
    # Approve Principal
    ApprovalRequest.objects.filter(requested_user=principal_user).update(status='approved')
    print(f"Principal: {principal_user.email} ({'Created' if created else 'Exists'})")

    teacher_user, created = User.objects.get_or_create(
        email="teacher@smartcampus.edu",
        defaults={
            "phone": "3333333333",
            "role": UserRole.TEACHER,
            "first_name": "John",
            "last_name": "Teacher",
            "college": college,
            "is_active": True,
            "is_approved": True
        }
    )
    if created:
        teacher_user.set_password("password123")
        teacher_user.save()
    ApprovalRequest.objects.filter(requested_user=teacher_user).update(status='approved')
    print(f"Teacher: {teacher_user.email} ({'Created' if created else 'Exists'})")

    student_user, created = User.objects.get_or_create(
        email="student@smartcampus.edu",
        defaults={
            "phone": "4444444444",
            "role": UserRole.STUDENT,
            "first_name": "Jane",
            "last_name": "Student",
            "college": college,
            "is_active": True,
            "is_approved": True
        }
    )
    if created:
        student_user.set_password("password123")
        student_user.save()
    ApprovalRequest.objects.filter(requested_user=student_user).update(status='approved')
    print(f"Student: {student_user.email} ({'Created' if created else 'Exists'})")

    # 3. Academic Structure
    dept, _ = Department.objects.get_or_create(
        college=college, name="Computer Science", code="CS", defaults={"hod": teacher_user}
    )
    
    course, _ = Course.objects.get_or_create(
        college=college, department=dept, name="B.Tech CS", code="BTECH-CS",
        defaults={"duration_years": 4}
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
        college=college, course=course, academic_year=ayear, name="Div A", year_of_study=1,
        defaults={"capacity": 60, "class_coordinator": teacher_user}
    )
    
    subj, _ = Subject.objects.get_or_create(
        college=college, department=dept, course=course, name="Algorithms", code="CS101",
        defaults={"year_of_study": 1, "semester": 1, "credits": 4}
    )
    
    alloc, _ = SubjectAllocation.objects.get_or_create(
        college=college, subject=subj, teacher=teacher_user, division=div, 
        academic_year=ayear
    )

    # 4. Profiles
    StudentProfile.objects.get_or_create(
        user=student_user, 
        defaults={
            "college": college,
            "division": div,
            "course": course,
            "academic_year": ayear,
            "prn": "STUD-2024-001",
            "roll_number": "01",
            "year_of_study": 1,
            "is_active": True
        }
    )
    
    StaffProfile.objects.get_or_create(
        user=teacher_user,
        defaults={
            "college": college,
            "employee_id": "EMP-101",
            "department": dept,
            "designation": "Assistant Professor",
            "joining_date": date.today(),
            "qualification": "Ph.D in CS",
            "specialization": "AI",
            "experience_years": 5,
            "is_active": True
        }
    )

    print("Seeding Complete!")
    print(f"Login with: principal@smartcampus.edu / password123")

if __name__ == "__main__":
    seed_neon()
