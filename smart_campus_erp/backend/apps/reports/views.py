import logging
from datetime import date, timedelta

from django.http     import HttpResponse
from rest_framework  import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response    import Response
from rest_framework.views       import APIView

from apps.academic.models       import SubjectAllocation
from apps.attendance.models     import AttendanceSession, AttendanceLog
from apps.students.models       import StudentProfile, StudentSubjectEnrollment
from apps.accounts.permissions  import (
    IsTeacher, IsStudent, IsHOD, IsPrincipal,
    IsCollegeAdmin, IsCollegeScopedStaff, IsSuperAdmin,
)
from .report_utils import (
    generate_attendance_pdf,
    generate_attendance_excel,
)

logger = logging.getLogger(__name__)


def _get_attendance_data(
    allocation_id: str,
    start_date   : date,
    end_date     : date,
    college      = None,
):
    """
    Core function: compute attendance per student for a
    subject allocation over a date range.
    Returns list of dicts.
    """
    try:
        allocation = SubjectAllocation.objects.select_related(
            'subject', 'division', 'teacher', 'college'
        ).get(id=allocation_id)
    except SubjectAllocation.DoesNotExist:
        return None, 'Subject allocation not found.'

    if college and allocation.college != college:
        return None, 'Access denied.'

    sessions = AttendanceSession.objects.filter(
        subject_allocation = allocation,
        status             = 'ended',
        actual_start__date__gte = start_date,
        actual_start__date__lte = end_date,
    )
    total_sessions = sessions.count()

    enrollments = StudentSubjectEnrollment.objects.select_related(
        'student__user',
    ).filter(
        subject_allocation = allocation,
        is_active          = True,
    )

    result = []
    for enroll in enrollments:
        student  = enroll.student
        present  = AttendanceLog.objects.filter(
            session__in = sessions,
            student     = student.user,
            status      = 'present',
        ).count()
        manual   = AttendanceLog.objects.filter(
            session__in = sessions,
            student     = student.user,
            status      = 'manual',
        ).count()
        # Count manual as present
        present_total = present + manual
        absent        = total_sessions - present_total
        percentage    = (
            round(present_total / total_sessions * 100, 1)
            if total_sessions > 0 else 0.0
        )
        result.append({
            'student_name'  : student.user.get_full_name(),
            'prn'           : student.prn,
            'roll_number'   : student.roll_number,
            'student_id'    : str(student.id),
            'total_sessions': total_sessions,
            'present'       : present_total,
            'absent'        : max(0, absent),
            'percentage'    : percentage,
            'is_at_risk'    : percentage < 75,
        })

    result.sort(key=lambda x: x['roll_number'])
    return result, allocation


# ══════════════════════════════════════════════════════════
# GET /api/reports/attendance-summary/
# ══════════════════════════════════════════════════════════

class AttendanceSummaryView(APIView):
    permission_classes = [IsTeacher | IsCollegeScopedStaff | IsSuperAdmin]

    def get(self, request):
        alloc_id   = request.query_params.get('allocation_id')
        start_str  = request.query_params.get('start_date')
        end_str    = request.query_params.get('end_date')
        threshold  = float(request.query_params.get('threshold', 75))

        if not alloc_id:
            return Response(
                {'error': 'allocation_id is required.'},
                status=400,
            )

        try:
            start = (
                date.fromisoformat(start_str)
                if start_str else date.today() - timedelta(days=90)
            )
            end = (
                date.fromisoformat(end_str)
                if end_str else date.today()
            )
        except ValueError:
            return Response(
                {'error': 'Invalid date format. Use YYYY-MM-DD.'},
                status=400,
            )

        college = (
            request.user.college
            if request.user.role != 'super_admin' else None
        )

        data, allocation = _get_attendance_data(
            alloc_id, start, end, college
        )

        if data is None:
            return Response({'error': allocation}, status=404)

        below_threshold = [r for r in data if r['is_at_risk']]
        avg_pct = (
            round(sum(r['percentage'] for r in data) / len(data), 1)
            if data else 0.0
        )

        return Response({
            'allocation': {
                'id'          : str(allocation.id),
                'subject_name': allocation.subject.name,
                'subject_code': allocation.subject.code,
                'division'    : allocation.division.name,
                'year'        : allocation.division.year_of_study,
                'teacher'     : allocation.teacher.get_full_name(),
            },
            'date_range'      : {
                'start': str(start), 'end': str(end),
            },
            'summary': {
                'total_students'  : len(data),
                'below_threshold' : len(below_threshold),
                'above_threshold' : len(data) - len(below_threshold),
                'average_percentage': avg_pct,
                'threshold'       : threshold,
            },
            'students': data,
        })


# ══════════════════════════════════════════════════════════
# GET /api/reports/defaulters/
# ══════════════════════════════════════════════════════════

class DefaultersView(APIView):
    permission_classes = [IsTeacher | IsCollegeScopedStaff | IsSuperAdmin]

    def get(self, request):
        alloc_id  = request.query_params.get('allocation_id')
        threshold = float(request.query_params.get('threshold', 75))
        start_str = request.query_params.get('start_date')
        end_str   = request.query_params.get('end_date')

        # If no alloc_id — return defaulters across all allocations
        # for this college (for HOD/Principal)
        college = (
            request.user.college
            if request.user.role != 'super_admin' else None
        )

        try:
            start = (
                date.fromisoformat(start_str)
                if start_str else date.today() - timedelta(days=90)
            )
            end = (
                date.fromisoformat(end_str)
                if end_str else date.today()
            )
        except ValueError:
            return Response({'error': 'Invalid date format.'}, status=400)

        if alloc_id:
            data, allocation = _get_attendance_data(
                alloc_id, start, end, college
            )
            if data is None:
                return Response({'error': allocation}, status=404)

            defaulters = [r for r in data if r['percentage'] < threshold]
            return Response({
                'subject_name': allocation.subject.name,
                'threshold'   : threshold,
                'count'       : len(defaulters),
                'defaulters'  : defaulters,
            })
        else:
            # All allocations for this college/HOD
            qs = SubjectAllocation.objects.select_related(
                'subject', 'division'
            ).filter(is_active=True)
            if college:
                qs = qs.filter(college=college)
            if request.user.role == 'teacher':
                qs = qs.filter(teacher=request.user)

            all_defaulters = []
            for alloc in qs:
                data, _ = _get_attendance_data(
                    str(alloc.id), start, end, college
                )
                if data:
                    for r in data:
                        if r['percentage'] < threshold:
                            r['subject_name'] = alloc.subject.name
                            r['subject_code'] = alloc.subject.code
                            r['division']     = alloc.division.name
                            all_defaulters.append(r)

            all_defaulters.sort(key=lambda x: x['percentage'])
            return Response({
                'threshold' : threshold,
                'count'     : len(all_defaulters),
                'defaulters': all_defaulters,
            })


# ══════════════════════════════════════════════════════════
# GET /api/reports/download/pdf/
# ══════════════════════════════════════════════════════════

class DownloadPDFView(APIView):
    permission_classes = [IsTeacher | IsCollegeScopedStaff | IsSuperAdmin]

    def get(self, request):
        alloc_id  = request.query_params.get('allocation_id')
        start_str = request.query_params.get('start_date')
        end_str   = request.query_params.get('end_date')
        threshold = float(request.query_params.get('threshold', 75))

        if not alloc_id:
            return Response(
                {'error': 'allocation_id is required.'},
                status=400,
            )

        try:
            start = (
                date.fromisoformat(start_str)
                if start_str else date.today() - timedelta(days=90)
            )
            end = (
                date.fromisoformat(end_str)
                if end_str else date.today()
            )
        except ValueError:
            return Response({'error': 'Invalid date format.'}, status=400)

        college = (
            request.user.college
            if request.user.role != 'super_admin' else None
        )

        data, allocation = _get_attendance_data(
            alloc_id, start, end, college
        )
        if data is None:
            return Response({'error': allocation}, status=404)

        college_name = (
            request.user.college.name
            if request.user.college else 'Smart Campus ERP'
        )

        try:
            pdf_bytes = generate_attendance_pdf(
                report_data  = data,
                title        = f'Attendance Report — {allocation.subject.name}',
                subtitle     = (
                    f'Division {allocation.division.name} · '
                    f'Year {allocation.division.year_of_study} · '
                    f'{start} to {end}'
                ),
                college_name = college_name,
                threshold    = threshold,
            )
        except Exception as exc:
            logger.error('PDF generation error: %s', exc)
            return Response(
                {'error': 'PDF generation failed. Please try again.'},
                status=500,
            )

        filename = (
            f'attendance_{allocation.subject.code}_'
            f'{start}_{end}.pdf'
        )
        response = HttpResponse(pdf_bytes, content_type='application/pdf')
        response['Content-Disposition'] = (
            f'attachment; filename="{filename}"'
        )
        response['Access-Control-Expose-Headers'] = 'Content-Disposition'
        return response


# ══════════════════════════════════════════════════════════
# GET /api/reports/download/excel/
# ══════════════════════════════════════════════════════════

class DownloadExcelView(APIView):
    permission_classes = [IsTeacher | IsCollegeScopedStaff | IsSuperAdmin]

    def get(self, request):
        alloc_id  = request.query_params.get('allocation_id')
        start_str = request.query_params.get('start_date')
        end_str   = request.query_params.get('end_date')
        threshold = float(request.query_params.get('threshold', 75))

        if not alloc_id:
            return Response(
                {'error': 'allocation_id is required.'},
                status=400,
            )

        try:
            start = (
                date.fromisoformat(start_str)
                if start_str else date.today() - timedelta(days=90)
            )
            end = (
                date.fromisoformat(end_str)
                if end_str else date.today()
            )
        except ValueError:
            return Response({'error': 'Invalid date format.'}, status=400)

        college = (
            request.user.college
            if request.user.role != 'super_admin' else None
        )

        data, allocation = _get_attendance_data(
            alloc_id, start, end, college
        )
        if data is None:
            return Response({'error': allocation}, status=404)

        college_name = (
            request.user.college.name
            if request.user.college else 'Smart Campus ERP'
        )

        try:
            excel_bytes = generate_attendance_excel(
                report_data  = data,
                title        = f'Attendance Report — {allocation.subject.code}',
                subject_name = allocation.subject.name,
                college_name = college_name,
                threshold    = threshold,
            )
        except Exception as exc:
            logger.error('Excel generation error: %s', exc)
            return Response(
                {'error': 'Excel generation failed. Please try again.'},
                status=500,
            )

        filename = (
            f'attendance_{allocation.subject.code}_'
            f'{start}_{end}.xlsx'
        )
        response = HttpResponse(
            excel_bytes,
            content_type=(
                'application/vnd.openxmlformats-officedocument'
                '.spreadsheetml.sheet'
            ),
        )
        response['Content-Disposition'] = (
            f'attachment; filename="{filename}"'
        )
        response['Access-Control-Expose-Headers'] = 'Content-Disposition'
        return response


# ══════════════════════════════════════════════════════════
# GET /api/reports/student/my-attendance/
# ══════════════════════════════════════════════════════════

class StudentMyAttendanceView(APIView):
    permission_classes = [IsStudent]

    def get(self, request):
        enrollments = StudentSubjectEnrollment.objects.select_related(
            'subject_allocation__subject',
            'subject_allocation__teacher',
            'subject_allocation__division',
            'academic_year',
        ).filter(
            student__user = request.user,
            is_active     = True,
        )

        result = []
        for enroll in enrollments:
            allocation    = enroll.subject_allocation
            sessions      = AttendanceSession.objects.filter(
                subject_allocation = allocation,
                status             = 'ended',
            )
            total   = sessions.count()
            present = AttendanceLog.objects.filter(
                session__in = sessions,
                student     = request.user,
                status__in  = ['present', 'manual'],
            ).count()
            absent     = max(0, total - present)
            percentage = (
                round(present / total * 100, 1)
                if total > 0 else 0.0
            )

            result.append({
                'allocation_id'  : str(allocation.id),
                'subject_name'   : allocation.subject.name,
                'subject_code'   : allocation.subject.code,
                'teacher_name'   : allocation.teacher.get_full_name(),
                'division_name'  : allocation.division.name,
                'year_of_study'  : allocation.division.year_of_study,
                'total_sessions' : total,
                'present'        : present,
                'absent'         : absent,
                'percentage'     : percentage,
                'is_at_risk'     : percentage < 75,
                'academic_year'  : enroll.academic_year.name
                                   if enroll.academic_year else '',
            })

        result.sort(key=lambda x: x['subject_name'])
        return Response(result)


# ══════════════════════════════════════════════════════════
# GET /api/reports/teacher/session-history/
# ══════════════════════════════════════════════════════════

class TeacherSessionHistoryView(APIView):
    permission_classes = [IsTeacher | IsCollegeScopedStaff]

    def get(self, request):
        alloc_id = request.query_params.get('allocation_id')
        limit    = int(request.query_params.get('limit', 20))

        qs = AttendanceSession.objects.select_related(
            'subject_allocation__subject',
            'subject_allocation__division',
            'virtual_room',
        ).filter(
            teacher = request.user,
            status  = 'ended',
        )

        if alloc_id:
            qs = qs.filter(subject_allocation_id=alloc_id)

        qs = qs.order_by('-actual_start')[:limit]

        data = [
            {
                'session_id'    : str(s.id),
                'session_code'  : s.session_code,
                'subject_name'  : s.subject_allocation.subject.name,
                'division_name' : s.subject_allocation.division.name,
                'date'          : s.actual_start.date().isoformat()
                                  if s.actual_start else '',
                'start_time'    : s.actual_start.strftime('%I:%M %p')
                                  if s.actual_start else '',
                'end_time'      : s.actual_end.strftime('%I:%M %p')
                                  if s.actual_end else '',
                'total_students': s.total_students,
                'present_count' : s.present_count,
                'absent_count'  : s.total_students - s.present_count,
                'attendance_pct': round(
                    s.present_count / s.total_students * 100, 1
                ) if s.total_students > 0 else 0.0,
            }
            for s in qs
        ]

        return Response(data)


# ══════════════════════════════════════════════════════════
# GET /api/reports/college/overview/  (Principal / HOD)
# ══════════════════════════════════════════════════════════

class CollegeOverviewView(APIView):
    permission_classes = [
        IsPrincipal | IsHOD | IsSuperAdmin
    ]

    def get(self, request):
        college = request.user.college

        qs = SubjectAllocation.objects.filter(
            college   = college,
            is_active = True,
        )
        if request.user.role == 'hod':
            qs = qs.filter(
                subject__department__hod = request.user
            )

        start = date.today() - timedelta(days=90)
        end   = date.today()

        subjects_data = []
        total_students_set  = set()
        total_at_risk_set   = set()

        for alloc in qs.select_related('subject', 'division'):
            data, _ = _get_attendance_data(
                str(alloc.id), start, end, college
            )
            if not data:
                continue

            avg_pct    = (
                sum(r['percentage'] for r in data) / len(data)
                if data else 0.0
            )
            at_risk    = [r for r in data if r['is_at_risk']]
            for r in data:
                total_students_set.add(r['prn'])
            for r in at_risk:
                total_at_risk_set.add(r['prn'])

            subjects_data.append({
                'allocation_id' : str(alloc.id),
                'subject_name'  : alloc.subject.name,
                'subject_code'  : alloc.subject.code,
                'division'      : alloc.division.name,
                'year'          : alloc.division.year_of_study,
                'total_students': len(data),
                'at_risk_count' : len(at_risk),
                'avg_percentage': round(avg_pct, 1),
            })

        subjects_data.sort(key=lambda x: x['avg_percentage'])

        return Response({
            'date_range': {'start': str(start), 'end': str(end)},
            'overview'  : {
                'total_subjects'   : len(subjects_data),
                'total_students'   : len(total_students_set),
                'total_at_risk'    : len(total_at_risk_set),
                'college_avg_pct'  : round(
                    sum(s['avg_percentage'] for s in subjects_data)
                    / len(subjects_data), 1
                ) if subjects_data else 0.0,
            },
            'subjects': subjects_data,
        })


# ══════════════════════════════════════════════════════════
# GET /api/reports/summary/
# ══════════════════════════════════════════════════════════

class DashboardSummaryView(APIView):
    """Simple summary stats for dashboard top cards."""
    permission_classes = [IsTeacher | IsCollegeScopedStaff | IsStudent | IsSuperAdmin]

    def get(self, request):
        college = request.user.college
        role    = request.user.role

        qs = AttendanceSession.objects.filter(status='ended')
        if college and role != 'super_admin':
            qs = qs.filter(college=college)

        if role == 'teacher':
            qs = qs.filter(teacher=request.user)
        elif role == 'student':
            # Enrollments for this student
            alloc_ids = StudentSubjectEnrollment.objects.filter(
                student__user = request.user,
                is_active     = True
            ).values_list('subject_allocation_id', flat=True)
            qs = qs.filter(subject_allocation_id__in=alloc_ids)

        total_sessions = qs.count()
        
        # Avg attendance
        avg_pct = 0.0
        if total_sessions > 0:
            from django.db.models import Avg, F
            # Approximate avg of averages
            results = [
                (s.present_count / s.total_students * 100)
                for s in qs if s.total_students > 0
            ]
            if results:
                avg_pct = round(sum(results) / len(results), 1)

        return Response({
            'total_sessions': total_sessions,
            'average_attendance': avg_pct,
            'active_students': StudentProfile.objects.filter(college=college).count() if college else 0,
            'at_risk_count': 0, # Placeholder for more complex logic
        })


# ══════════════════════════════════════════════════════════
# GET /api/reports/trends/
# ══════════════════════════════════════════════════════════

class AttendanceTrendsView(APIView):
    """Weekly/Monthly attendance trends for charts."""
    permission_classes = [IsTeacher | IsCollegeScopedStaff | IsStudent | IsSuperAdmin]

    def get(self, request):
        days = int(request.query_params.get('days', 30))
        start_date = date.today() - timedelta(days=days)

        college = request.user.college
        role    = request.user.role

        sessions = AttendanceSession.objects.filter(
            status='ended',
            actual_start__date__gte=start_date
        )
        
        if college and role != 'super_admin':
            sessions = sessions.filter(college=college)

        if role == 'teacher':
            sessions = sessions.filter(teacher=request.user)
        elif role == 'student':
            alloc_ids = StudentSubjectEnrollment.objects.filter(
                student__user = request.user,
                is_active     = True
            ).values_list('subject_allocation_id', flat=True)
            sessions = sessions.filter(subject_allocation_id__in=alloc_ids)

        # Group by date
        trends = {}
        for s in sessions:
            d_str = s.actual_start.date().isoformat()
            if d_str not in trends:
                trends[d_str] = {'total': 0, 'present': 0}
            trends[d_str]['total']   += s.total_students
            trends[d_str]['present'] += s.present_count

        data = []
        for d, vals in sorted(trends.items()):
            pct = round(vals['present'] / vals['total'] * 100, 1) if vals['total'] > 0 else 0
            data.append({
                'date': d,
                'percentage': pct,
                'present': vals['present'],
                'total': vals['total'],
            })

        return Response(data)
