from celery import shared_task
from django.utils import timezone
from django.db.models import Count, Q
from .models import Notification
from .fcm import FCMService
from .sms import SMSService
from apps.accounts.models import User
from apps.attendance.models import AttendanceLog, AttendanceSession
from apps.students.models import StudentProfile

@shared_task
def send_low_attendance_alerts():
    """
    Find all students below minimum attendance percentage and alert.
    """
    fcm = FCMService()
    students = StudentProfile.objects.filter(is_active=True)
    
    for student in students:
        # Placeholder for complex calculation logic
        # For each subject, check percentage
        # if < threshold:
        fcm.send_to_user(
            student.user.id, 
            "Low Attendance Alert", 
            "Your attendance is below the minimum required percentage."
        )

@shared_task
def send_daily_attendance_summary():
    """
    Compiles daily summary and sends to Principal and HODs.
    """
    today = timezone.now().date()
    # Implementation logic for aggregation
    pass

@shared_task
def send_absence_sms(student_id, session_id):
    """
    Sends SMS to parent when student is marked absent.
    """
    try:
        student = StudentProfile.objects.get(user_id=student_id)
        session = AttendanceSession.objects.get(id=session_id)
        sms = SMSService()
        
        sms.send_attendance_alert(
            student.parent_mobile,
            student.user.get_full_name(),
            session.subject_allocation.subject.name,
            session.date
        )
    except Exception:
        pass
