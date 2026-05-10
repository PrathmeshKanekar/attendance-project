import os
import django
import uuid
import random
from datetime import date, timedelta, datetime
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

def seed_real_data():
    print("Starting Production-Level Seeding (Real Data)...")

    # 1. Clear Inconsistent Data
    print("Clearing old dummy records...")
    AttendanceLog.objects.all().delete()
    AttendanceSession.objects.all().delete()
    VirtualRoom.objects.all().delete()
    StudentProfile.objects.all().delete()
    StaffProfile.objects.all().delete()
    User.objects.exclude(is_superuser=True).delete()
    SubjectAllocation.objects.all().delete()
    Subject.objects.all().delete()
    Division.objects.all().delete()
    Semester.objects.all().delete()
    Course.objects.all().delete()
    Department.objects.all().delete()
    College.objects.all().delete()

    # 2. Permanent Super Admin (Protected)
    if not User.objects.filter(email="superadmin@app.com").exists():
        User.objects.create_superuser(
            email="superadmin@app.com",
            password="admin@123",
            first_name="App",
            last_name="SuperAdmin"
        )
    else:
        # Reset password to ensure it's known
        sa = User.objects.get(email="superadmin@app.com")
        sa.set_password("admin@123")
        sa.save()

    # 3. Main Institutional Identity
    college = College.objects.create(
        code="SC-UNIVERSITY-2024",
        name="Smart Campus Global University",
        address="Academic Ridge, Innovation Drive, Palo Alto, CA 94301",
        email_domain="smartcampus.edu",
        phone="+1-650-555-0100",
        is_active=True
    )

    # 3. Academic Calendar
    ayear = AcademicYear.objects.create(
        college=college, 
        name="Academic Year 2024-25",
        start_date=date(2024, 6, 1), 
        end_date=date(2025, 5, 31), 
        is_current=True
    )

    # 4. Departments & Faculty
    depts_config = [
        {"name": "School of Computer Science", "code": "SCS", "head": "Alan Turing"},
        {"name": "School of AI & Robotics", "code": "SAIR", "head": "Geoffrey Hinton"},
        {"name": "Department of Data Science", "code": "DDS", "head": "Grace Hopper"}
    ]

    # Principal Setup
    principal = User.objects.create(
        email="principal@smartcampus.edu",
        first_name="Dr. Robert", last_name="Oppenheimer",
        role=UserRole.PRINCIPAL, college=college, phone="+1-650-111-0000",
        is_active=True, is_approved=True
    )
    principal.set_password("password123")
    principal.save()

    for d_cfg in depts_config:
        dept = Department.objects.create(college=college, name=d_cfg['name'], code=d_cfg['code'])
        course = Course.objects.create(
            college=college, department=dept, 
            name=f"B.S. in {d_cfg['name'].split('of ')[-1]}", 
            code=f"BS-{d_cfg['code']}", 
            duration_years=4
        )
        
        sem = Semester.objects.create(
            college=college, course=course, academic_year=ayear, 
            semester_number=1, start_date=date(2024, 6, 15), end_date=date(2024, 11, 30)
        )
        
        div = Division.objects.create(
            college=college, course=course, academic_year=ayear, 
            name="Alpha-1", year_of_study=1, capacity=60
        )

        # Create Teacher for this Dept
        t_first, t_last = d_cfg['head'].split(' ')
        teacher = User.objects.create(
            email=f"{t_first.lower()}.{t_last.lower()}@smartcampus.edu",
            first_name=t_first, last_name=t_last,
            role=UserRole.TEACHER, college=college, phone=f"+1-650-222-{random.randint(1000, 9999)}",
            is_active=True, is_approved=True
        )
        teacher.set_password("password123")
        teacher.save()
        
        StaffProfile.objects.create(
            user=teacher, college=college, department=dept,
            employee_id=f"FAC-{d_cfg['code']}-001",
            designation="Distinguished Professor", qualification="Ph.D, Research Fellow",
            specialization=d_cfg['name'], experience_years=20, joining_date=date(2015, 8, 15)
        )

        # Assign a core subject
        subj = Subject.objects.create(
            college=college, department=dept, course=course,
            name=f"Introduction to {d_cfg['code']}", code=f"{d_cfg['code']}-101", 
            year_of_study=1, semester=1, credits=4
        )

        SubjectAllocation.objects.create(
            college=college, subject=subj, teacher=teacher, division=div, academic_year=ayear
        )

        # 5. Add Students to this Division
        for i in range(1, 6):
            s_first, s_last = f"Student_{d_cfg['code']}", f"Num_{i}"
            s_user = User.objects.create(
                email=f"s{d_cfg['code'].lower()}{i}@smartcampus.edu",
                first_name=s_first, last_name=s_last,
                role=UserRole.STUDENT, college=college, phone=f"+1-650-333-{d_cfg['code']}{i}",
                is_active=True, is_approved=True
            )
            s_user.set_password("password123")
            s_user.save()

            StudentProfile.objects.create(
                user=s_user, college=college, division=div, course=course, academic_year=ayear,
                prn=f"PRN-{d_cfg['code']}-2024-{i:03d}", roll_number=str(i), 
                year_of_study=1, face_registered=True
            )

    # 6. Realistic 3D Virtual Classrooms (Stanford Memorial Church Area)
    # Centroid: 37.4277, -122.1702
    base_lat, base_lng = 37.4277, -122.1702

    # Room 1: High-Tech 3D Polygon Classroom
    Room_A = VirtualRoom.objects.create(
        college=college, name="Turing Lecture Hall (A1)", building="Innovation Center", floor_number=1,
        department="School of Computer Science", center_lat=base_lat, center_lng=base_lng,
        use_polygon=True, min_altitude=45.0, max_altitude=65.0,
        corner_coordinates=[
            {"lat": base_lat + 0.0003, "lng": base_lng - 0.0003, "alt": 52.0}, # NW
            {"lat": base_lat + 0.0003, "lng": base_lng + 0.0003, "alt": 52.0}, # NE
            {"lat": base_lat - 0.0003, "lng": base_lng + 0.0003, "alt": 52.0}, # SE
            {"lat": base_lat - 0.0003, "lng": base_lng - 0.0003, "alt": 52.0}, # SW
        ],
        estimated_area=2500.0, created_by=principal
    )

    # Room 2: Polygon Lab (Irregular Shape)
    Room_B = VirtualRoom.objects.create(
        college=college, name="Hinton Robotics Lab", building="Innovation Center", floor_number=1,
        department="School of AI & Robotics", center_lat=base_lat + 0.001, center_lng=base_lng + 0.001,
        use_polygon=True, min_altitude=45.0, max_altitude=65.0,
        corner_coordinates=[
            {"lat": base_lat + 0.0012, "lng": base_lng + 0.0008, "alt": 52.0},
            {"lat": base_lat + 0.0012, "lng": base_lng + 0.0012, "alt": 52.0},
            {"lat": base_lat + 0.0008, "lng": base_lng + 0.0012, "alt": 52.0},
            {"lat": base_lat + 0.0008, "lng": base_lng + 0.0008, "alt": 52.0},
        ],
        estimated_area=1200.0, created_by=principal
    )

    # 7. Live Sessions
    now = timezone.now()
    turing = User.objects.get(email="alan.turing@smartcampus.edu")
    scs_alloc = SubjectAllocation.objects.filter(teacher=turing).first()

    AttendanceSession.objects.create(
        college=college,
        subject_allocation=scs_alloc,
        teacher=turing,
        virtual_room=Room_A,
        session_code="SCS101",
        status='active',
        scheduled_start=now - timedelta(minutes=10),
        scheduled_end=now + timedelta(minutes=50),
        actual_start=now - timedelta(minutes=9),
        radius_meters=35.0,
        teacher_lat=base_lat, teacher_lng=base_lng
    )

    print("\nSEEDING COMPLETE: Realistic Data Inserted.")
    print(f"SuperAdmin: superadmin@app.com / admin@123")
    print(f"Principal:  principal@smartcampus.edu / password123")
    print(f"Teacher:    alan.turing@smartcampus.edu / password123")
    print(f"Student:    sscs1@smartcampus.edu / password123")
    print(f"Location:   Stanford Campus (37.4277, -122.1702)")

if __name__ == "__main__":
    seed_real_data()
