import os
import django
import uuid
import random
from datetime import date, timedelta, time, datetime
import sys
from django.utils import timezone

# Set up Django environment
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.base')
django.setup()

from apps.tenants.models import College
from apps.accounts.models import User, UserRole
from apps.academic.models import Department, Course, AcademicYear, Semester, Division, Subject, SubjectAllocation
from apps.students.models import StudentProfile, StudentSubjectEnrollment
from apps.staff.models import StaffProfile, ApprovalRequest
from apps.virtual_rooms.models import VirtualRoom
from apps.attendance.models import AttendanceSession, AttendanceLog

def clear_data():
    print("Clearing existing data...")
    AttendanceLog.objects.all().delete()
    AttendanceSession.objects.all().delete()
    VirtualRoom.objects.all().delete()
    StudentSubjectEnrollment.objects.all().delete()
    StudentProfile.objects.all().delete()
    StaffProfile.objects.all().delete()
    ApprovalRequest.objects.all().delete()
    SubjectAllocation.objects.all().delete()
    Subject.objects.all().delete()
    Division.objects.all().delete()
    Semester.objects.all().delete()
    AcademicYear.objects.all().delete()
    Course.objects.all().delete()
    Department.objects.all().delete()
    User.objects.exclude(is_superuser=True).delete()
    College.objects.all().delete()

def seed_production():
    print("Starting Production-Level Seeding...")

    # 1. College
    college = College.objects.create(
        code="SCE-2024",
        name="Smart Campus Institute of Engineering",
        address="University Avenue, Palo Alto, CA 94301",
        email_domain="smartcampus.edu",
        phone="+1-650-555-0199",
        is_active=True
    )

    # 2. Academic Infrastructure
    ayear = AcademicYear.objects.create(
        college=college, name="Academic Year 2024-25",
        start_date=date(2024, 6, 1), end_date=date(2025, 5, 31), is_current=True
    )

    depts = [
        {"name": "Computer Science & Engineering", "code": "CSE"},
        {"name": "Information Technology", "code": "IT"},
        {"name": "Electronics & Communication", "code": "ECE"}
    ]

    for d in depts:
        dept = Department.objects.create(college=college, name=d['name'], code=d['code'])
        course = Course.objects.create(college=college, department=dept, name=f"B.Tech in {d['code']}", code=f"BTECH-{d['code']}", duration_years=4)
        
        sem = Semester.objects.create(college=college, course=course, academic_year=ayear, semester_number=1, start_date=date(2024, 6, 15), end_date=date(2024, 11, 30))
        
        # Division model uses class_coordinator and year_of_study
        div = Division.objects.create(college=college, course=course, academic_year=ayear, name="Section A", year_of_study=1, capacity=60)

    # 3. Principal
    principal = User.objects.create(
        email="principal@smartcampus.edu",
        first_name="Dr. Arthur", last_name="Vance",
        role=UserRole.PRINCIPAL, college=college, phone="+1-650-111-2222",
        is_active=True, is_approved=True
    )
    principal.set_password("password123")
    principal.save()

    # 4. Teachers & Subjects (CS Focus)
    cs_dept = Department.objects.get(code="CSE")
    cs_course = Course.objects.get(code="BTECH-CSE")
    cs_div = Division.objects.get(course=cs_course, name="Section A")
    cs_sem = Semester.objects.get(course=cs_course, semester_number=1)

    teachers_data = [
        {"email": "john.smith@smartcampus.edu", "first": "John", "last": "Smith", "subj_name": "Data Structures", "subj_code": "CS-101"},
        {"email": "sarah.connor@smartcampus.edu", "first": "Sarah", "last": "Connor", "subj_name": "Operating Systems", "subj_code": "CS-201"},
        {"email": "alan.turing@smartcampus.edu", "first": "Alan", "last": "Turing", "subj_name": "Theory of Computation", "subj_code": "CS-301"}
    ]

    for t in teachers_data:
        t_user = User.objects.create(
            email=t['email'], first_name=t['first'], last_name=t['last'],
            role=UserRole.TEACHER, college=college, phone=f"+1-650-555-{random.randint(1000, 9999)}",
            is_active=True, is_approved=True
        )
        t_user.set_password("password123")
        t_user.save()
        
        StaffProfile.objects.create(
            user=t_user, college=college, department=cs_dept,
            employee_id=f"EMP-{random.randint(1000, 9999)}",
            designation="Assistant Professor", qualification="Ph.D in CSE",
            specialization="Algorithms", experience_years=8, joining_date=date(2020, 1, 1)
        )

        subj = Subject.objects.create(
            college=college, department=cs_dept, course=cs_course,
            name=t['subj_name'], code=t['subj_code'], year_of_study=1, semester=1, credits=4
        )

        SubjectAllocation.objects.create(
            college=college, subject=subj, teacher=t_user, division=cs_div, academic_year=ayear
        )

    # 5. Students
    student_names = [
        ("Alice", "Johnson"), ("Bob", "Miller"), ("Charlie", "Davis"), ("Diana", "Prince"), ("Edward", "Norton")
    ]
    for i, (f, l) in enumerate(student_names):
        s_user = User.objects.create(
            email=f"{f.lower()}.{l.lower()}@smartcampus.edu",
            first_name=f, last_name=l,
            role=UserRole.STUDENT, college=college, phone=f"+1-650-999-{1000+i}",
            is_active=True, is_approved=True
        )
        s_user.set_password("password123")
        s_user.save()

        StudentProfile.objects.create(
            user=s_user, college=college, division=cs_div, course=cs_course, academic_year=ayear,
            prn=f"PRN-2024-{100+i}", roll_number=str(i+1), year_of_study=1, face_registered=True
        )

    # 6. Realistic Virtual Rooms (Stanford Coordinates)
    # Location: Stanford Memorial Church area
    base_lat, base_lng = 37.4277, -122.1702

    # Room 1: High-Accuracy 3D Polygon Room
    Room_A = VirtualRoom.objects.create(
        college=college, name="Grand Hall 101", building="Science Block", floor_number=1,
        department="Computer Science", center_lat=base_lat, center_lng=base_lng,
        use_polygon=True, min_altitude=50.0, max_altitude=65.0,
        corner_coordinates=[
            {"lat": base_lat + 0.0002, "lng": base_lng - 0.0002, "alt": 55.0}, # NW
            {"lat": base_lat + 0.0002, "lng": base_lng + 0.0002, "alt": 55.0}, # NE
            {"lat": base_lat - 0.0002, "lng": base_lng + 0.0002, "alt": 55.0}, # SE
            {"lat": base_lat - 0.0002, "lng": base_lng - 0.0002, "alt": 55.0}, # SW
        ],
        estimated_area=1600.0, created_by=principal
    )

    # Room 2: Legacy Circular Room
    Room_B = VirtualRoom.objects.create(
        college=college, name="Seminar Room 202", building="Arts Block", floor_number=2,
        department="Information Technology", center_lat=base_lat + 0.001, center_lng=base_lng + 0.001,
        radius_meters=35.0, use_polygon=False, created_by=principal
    )

    # 7. Active Attendance Sessions
    # Create an ongoing session for John Smith in Room A
    john = User.objects.get(email="john.smith@smartcampus.edu")
    ds_subj = Subject.objects.get(code="CS-101")
    ds_alloc = SubjectAllocation.objects.get(subject=ds_subj, teacher=john)

    now = timezone.now()
    session = AttendanceSession.objects.create(
        college=college,
        subject_allocation=ds_alloc,
        teacher=john,
        virtual_room=Room_A,
        session_code="DS-LIVE",
        status='active',
        scheduled_start=now - timedelta(minutes=15),
        scheduled_end=now + timedelta(minutes=45),
        actual_start=now - timedelta(minutes=14),
        radius_meters=30.0,
        teacher_lat=base_lat, teacher_lng=base_lng
    )

    print("Production Seeding Complete!")
    print(f"Principal: principal@smartcampus.edu / password123")
    print(f"Teacher:   john.smith@smartcampus.edu / password123")
    print(f"Student:   alice.johnson@smartcampus.edu / password123")
    print(f"Active Session: {session.session_code} (Room: {Room_A.name})")

if __name__ == "__main__":
    clear_data()
    seed_production()
