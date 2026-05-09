import os
import django
import sys
from datetime import datetime, timedelta

# Set up Django environment
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
django.setup()

from apps.accounts.models import User
from apps.attendance.models import AttendanceSession
from apps.academic.models import SubjectAllocation, Subject, Department, Course
from apps.tenants.models import College
from apps.virtual_rooms.models import VirtualRoom
from apps.students.models import StudentSubjectEnrollment, StudentProfile

def seed_session():
    college = College.objects.first()
    teacher = User.objects.filter(role='teacher').first()
    student_user = User.objects.filter(email='student@globaltech.edu').first()
    student_profile = StudentProfile.objects.filter(user=student_user).first()
    
    if not teacher:
        print("No teacher found!")
        return

    department = Department.objects.first()
    course = Course.objects.first()

    subject, _ = Subject.objects.get_or_create(
        college=college,
        department=department,
        course=course,
        name="Advanced Python",
        code="CS401",
        credit_hours=4,
        subject_type='theory'
    )

    from apps.academic.models import AcademicYear, Semester, Division
    academic_year, _ = AcademicYear.objects.get_or_create(
        college=college,
        name="2026-2027",
        start_date=datetime.now().date(),
        end_date=(datetime.now() + timedelta(days=365)).date()
    )
    semester, _ = Semester.objects.get_or_create(
        college=college,
        academic_year=academic_year,
        course=course,
        semester_number=1,
        start_date=datetime.now().date(),
        end_date=(datetime.now() + timedelta(days=180)).date()
    )
    division, _ = Division.objects.get_or_create(
        college=college,
        course=course,
        semester=semester,
        name="A",
        capacity=60
    )

    allocation, _ = SubjectAllocation.objects.get_or_create(
        college=college,
        subject=subject,
        teacher=teacher,
        academic_year=academic_year,
        semester=semester,
        division=division
    )
    
    # Enroll student
    StudentSubjectEnrollment.objects.get_or_create(
        student=student_profile,
        subject_allocation=allocation,
        academic_year=academic_year
    )

    session = AttendanceSession.objects.create(
        college=college,
        subject_allocation=allocation,
        teacher=teacher,
        virtual_room=None,
        division=division,
        date=datetime.now().date(),
        scheduled_start=datetime.now().time(),
        scheduled_end=(datetime.now() + timedelta(hours=1)).time(),
        status='active'
    )
    
    print(f"Session Created: {session.id}")

if __name__ == "__main__":
    seed_session()
