from celery import shared_task
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.utils import timezone
from .models import GeneratedReport
from .generators.attendance_report import AttendanceReportGenerator
from apps.notifications.models import Notification

@shared_task
def generate_student_report_pdf(student_id, month, year, report_id, notify_user=True):
    """
    Task to generate PDF report and save it.
    """
    try:
        report = GeneratedReport.objects.get(id=report_id)
        generator = AttendanceReportGenerator(report.college.id)
        
        pdf_bytes = generator.student_report_pdf(student_id, month, year)
        
        filename = f"reports/attendance_{student_id}_{month}_{year}_{timezone.now().timestamp()}.pdf"
        file_path = default_storage.save(filename, ContentFile(pdf_bytes))
        file_url = default_storage.url(file_path)
        
        report.file_url = file_url
        report.status = GeneratedReport.ReportStatus.READY
        report.completed_at = timezone.now()
        report.save()
        
        if notify_user:
            Notification.objects.create(
                college=report.college,
                recipient=report.requested_by,
                notification_type='approval_result', # or custom report_ready
                title="Report Ready",
                body=f"Your monthly attendance report for {month}/{year} is ready for download."
            )
    except Exception as e:
        if 'report' in locals():
            report.status = GeneratedReport.ReportStatus.FAILED
            report.save()

@shared_task  
def generate_college_analytics(college_id):
    """
    Nightly task: compute all stats for dashboard caching.
    """
    # Logic to compute stats and save to Redis/Cache
    pass
