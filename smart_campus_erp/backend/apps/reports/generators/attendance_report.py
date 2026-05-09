import pandas as pd
from io import BytesIO
from django.utils import timezone
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet
from apps.tenants.models import College
from apps.attendance.models import AttendanceLog, AttendanceSession
from apps.students.models import StudentProfile
from apps.academic.models import SubjectAllocation

class AttendanceReportGenerator:
    def __init__(self, college_id):
        self.college = College.objects.get(id=college_id)
        self.styles = getSampleStyleSheet()

    def student_monthly_report(self, student_id, month, year):
        """
        Query attendance logs and return a DataFrame.
        """
        logs = AttendanceLog.objects.filter(
            student_id=student_id,
            session__date__month=month,
            session__date__year=year
        ).select_related('session__subject_allocation__subject')
        
        data = []
        for log in logs:
            data.append({
                'Date': log.session.date,
                'Subject': log.session.subject_allocation.subject.name,
                'Status': log.status
            })
            
        return pd.DataFrame(data)

    def student_report_pdf(self, student_id, month, year):
        """
        Generates a PDF report for a student.
        """
        student = StudentProfile.objects.select_related('user').get(user_id=student_id)
        df = self.student_monthly_report(student_id, month, year)
        
        buffer = BytesIO()
        doc = SimpleDocTemplate(buffer, pagesize=A4)
        elements = []
        
        # Header
        elements.append(Paragraph(f"Monthly Attendance Report - {month}/{year}", self.styles['Title']))
        elements.append(Paragraph(f"College: {self.college.name}", self.styles['Normal']))
        elements.append(Paragraph(f"Student: {student.user.get_full_name()} ({student.prn_number})", self.styles['Normal']))
        elements.append(Spacer(1, 20))
        
        if not df.empty:
            # Aggregate stats
            stats = df.groupby('Subject')['Status'].value_counts().unstack().fillna(0)
            if 'present' not in stats.columns: stats['present'] = 0
            
            # Table Data
            table_data = [['Subject', 'Total Classes', 'Attended', 'Percentage']]
            for subject, row in stats.iterrows():
                total = row.sum()
                present = row.get('present', 0)
                perc = (present / total * 100) if total > 0 else 0
                table_data.append([subject, int(total), int(present), f"{perc:.2f}%"])
            
            # Create Table
            t = Table(table_data)
            t.setStyle(TableStyle([
                ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
                ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
                ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
                ('GRID', (0, 0), (-1, -1), 1, colors.black)
            ]))
            elements.append(t)
        else:
            elements.append(Paragraph("No attendance data found for this period.", self.styles['Normal']))
            
        doc.build(elements)
        return buffer.getvalue()

    def division_report(self, division_id, date_from, date_to):
        """
        Matrix of all students in division vs dates.
        """
        logs = AttendanceLog.objects.filter(
            session__division_id=division_id,
            session__date__range=[date_from, date_to]
        ).select_related('student', 'session')
        
        data = []
        for log in logs:
            data.append({
                'Student': log.student.get_full_name(),
                'Date': log.session.date,
                'Status': log.status
            })
            
        df = pd.DataFrame(data)
        if not df.empty:
            return df.pivot(index='Student', columns='Date', values='Status')
        return pd.DataFrame()

    def defaulter_list(self, college_id, threshold_percentage):
        # Implementation for defaulter list
        return pd.DataFrame()

    def teacher_performance_report(self, college_id, academic_year_id):
        # Implementation for teacher performance
        return pd.DataFrame()

    def export_to_excel(self, dataframe, filename):
        buffer = BytesIO()
        with pd.ExcelWriter(buffer, engine='openpyxl') as writer:
            dataframe.to_excel(writer, index=True, sheet_name='Report')
        return buffer.getvalue()
