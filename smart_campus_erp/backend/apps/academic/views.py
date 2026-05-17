from django.db import IntegrityError
from django.utils import timezone
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from apps.accounts.permissions import (
    IsCollegeScopedStaff, IsSuperAdmin, IsLabAssistant, IsCollegeAdmin,
    IsPrincipal,
)
from .models import (
    Department, Course, AcademicYear,
    Division, Subject, SubjectAllocation,
)
from .serializers import (
    DepartmentSerializer, CourseSerializer,
    AcademicYearSerializer, DivisionSerializer,
    SubjectSerializer, SubjectAllocationSerializer,
    BulkEnrollSerializer,
)


def college_scope(user, qs, field='college'):
    if not user or user.is_anonymous:
        return qs.none()
    if user.role == 'super_admin':
        return qs
    return qs.filter(**{field: user.college})


# ══════════════════════════════════════════════════════════
# DEPARTMENTS
# ══════════════════════════════════════════════════════════

class DepartmentListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = college_scope(
            request.user,
            Department.objects.select_related('hod').filter(is_active=True)
        )
        search = request.query_params.get('search', '')
        if search:
            qs = qs.filter(name__icontains=search)
        qs = qs.order_by('name')
        return Response(DepartmentSerializer(qs, many=True).data)

    def post(self, request):
        if request.user.role not in ['college_admin', 'super_admin']:
            return Response({'error': 'Only Administrators can create departments.'}, status=status.HTTP_403_FORBIDDEN)
        
        data = request.data.copy()
        if request.user.role != 'super_admin':
            data['college'] = str(request.user.college.id)

        # Validate college field exists
        if 'college' not in data:
            return Response(
                {'error': 'college is required'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        ser = DepartmentSerializer(data=data)
        if ser.is_valid():
            try:
                dept = ser.save(college=request.user.college
                                if request.user.role != 'super_admin'
                                else ser.validated_data.get('college'))
                return Response(
                    DepartmentSerializer(dept).data,
                    status=status.HTTP_201_CREATED,
                )
            except IntegrityError:
                return Response(
                    {'error': 'A department with this code already exists.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
        return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)


class DepartmentDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def _get_dept(self, request, pk):
        try:
            dept = Department.objects.get(pk=pk)
        except Department.DoesNotExist:
            return None
        if (request.user.role != 'super_admin'
                and dept.college != request.user.college):
            return None
        return dept

    def get(self, request, pk):
        dept = self._get_dept(request, pk)
        if not dept:
            return Response({'error': 'Not found'}, status=404)
        return Response(DepartmentSerializer(dept).data)

    def put(self, request, pk):
        if request.user.role not in ['college_admin', 'super_admin']:
            return Response({'error': 'Only Administrators can edit departments.'}, status=status.HTTP_403_FORBIDDEN)
        
        dept = self._get_dept(request, pk)
        if not dept:
            return Response({'error': 'Not found'}, status=404)
        ser = DepartmentSerializer(dept, data=request.data, partial=True)
        if ser.is_valid():
            ser.save()
            return Response(ser.data)
        return Response(ser.errors, status=400)

    def delete(self, request, pk):
        if request.user.role not in ['college_admin', 'super_admin']:
            return Response({'error': 'Only Administrators can deactivate departments.'}, status=status.HTTP_403_FORBIDDEN)
            
        dept = self._get_dept(request, pk)
        if not dept:
            return Response({'error': 'Not found'}, status=404)
        dept.is_active = False
        dept.save(update_fields=['is_active'])
        return Response(
            {'success': True, 'message': 'Department deactivated.'},
            status=status.HTTP_200_OK,
        )


# ══════════════════════════════════════════════════════════
# COURSES
# ══════════════════════════════════════════════════════════

class CourseListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = college_scope(
            request.user,
            Course.objects.select_related('department').filter(is_active=True),
        )
        dept_id = request.query_params.get('department')
        if dept_id:
            qs = qs.filter(department_id=dept_id)
        return Response(CourseSerializer(qs.order_by('name'), many=True).data)

    def post(self, request):
        if request.user.role not in ['college_admin', 'super_admin']:
            return Response({'error': 'Only Administrators can create courses.'}, status=status.HTTP_403_FORBIDDEN)
            
        college = (request.user.college
                   if request.user.role != 'super_admin'
                   else None)
        
        # Ensure the department belongs to the same college
        dept_id = request.data.get('department')
        if dept_id and college:
            try:
                Department.objects.get(id=dept_id, college=college)
            except Department.DoesNotExist:
                return Response(
                    {'error': 'Invalid department for your college.'},
                    status=400
                )

        ser = CourseSerializer(data=request.data)
        if ser.is_valid():
            try:
                course = ser.save(college=college)
                return Response(
                    CourseSerializer(course).data,
                    status=status.HTTP_201_CREATED,
                )
            except IntegrityError:
                return Response(
                    {'error': 'A course with this code already exists in this college.'},
                    status=400,
                )
        return Response(ser.errors, status=400)


class CourseDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def _get(self, request, pk):
        try:
            c = Course.objects.select_related('department').get(pk=pk)
        except Course.DoesNotExist:
            return None
        if request.user.role != 'super_admin' and c.college != request.user.college:
            return None
        return c

    def get(self, request, pk):
        c = self._get(request, pk)
        if not c:
            return Response({'error': 'Not found'}, status=404)
        return Response(CourseSerializer(c).data)

    def put(self, request, pk):
        if request.user.role not in ['college_admin', 'super_admin']:
            return Response({'error': 'Only Administrators can edit courses.'}, status=status.HTTP_403_FORBIDDEN)
            
        c = self._get(request, pk)
        if not c:
            return Response({'error': 'Not found'}, status=404)
        
        # Verify department if updated
        dept_id = request.data.get('department')
        if dept_id and c.college:
            try:
                Department.objects.get(id=dept_id, college=c.college)
            except Department.DoesNotExist:
                return Response({'error': 'Invalid department.'}, status=400)

        ser = CourseSerializer(c, data=request.data, partial=True)
        if ser.is_valid():
            ser.save()
            return Response(ser.data)
        return Response(ser.errors, status=400)

    def delete(self, request, pk):
        if request.user.role not in ['college_admin', 'super_admin']:
            return Response({'error': 'Only Administrators can deactivate courses.'}, status=status.HTTP_403_FORBIDDEN)
            
        c = self._get(request, pk)
        if not c:
            return Response({'error': 'Not found'}, status=404)
        c.is_active = False
        c.save(update_fields=['is_active'])
        return Response({'success': True})


# ══════════════════════════════════════════════════════════
# ACADEMIC YEARS (Managed ONLY by College Admin)
# ══════════════════════════════════════════════════════════

class AcademicYearListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = college_scope(
            request.user,
            AcademicYear.objects.all(),
        ).order_by('-start_date')
        return Response(AcademicYearSerializer(qs, many=True).data)

    def post(self, request):
        if request.user.role not in ['college_admin', 'super_admin']:
            return Response({'error': 'Only Administrators can create academic years.'}, status=status.HTTP_403_FORBIDDEN)
        ser = AcademicYearSerializer(data=request.data)
        if ser.is_valid():
            college = request.user.college
            # Validate overlapping active years if setting as current
            if ser.validated_data.get('is_current', False):
                AcademicYear.objects.filter(college=college, is_current=True).update(is_current=False)
            
            try:
                year = ser.save(college=college)
                return Response(
                    AcademicYearSerializer(year).data,
                    status=status.HTTP_201_CREATED,
                )
            except IntegrityError:
                return Response({'error': 'An academic year with this name already exists.'}, status=400)
        return Response(ser.errors, status=400)

class AcademicYearDetailView(APIView):
    permission_classes = [IsCollegeAdmin | IsSuperAdmin]

    def _get(self, request, pk):
        try:
            return AcademicYear.objects.get(pk=pk, college=request.user.college)
        except AcademicYear.DoesNotExist:
            return None

    def get(self, request, pk):
        year = self._get(request, pk)
        if not year: return Response({'error': 'Not found'}, status=404)
        return Response(AcademicYearSerializer(year).data)

    def put(self, request, pk):
        year = self._get(request, pk)
        if not year: return Response({'error': 'Not found'}, status=404)
        ser = AcademicYearSerializer(year, data=request.data, partial=True)
        if ser.is_valid():
            ser.save()
            return Response(ser.data)
        return Response(ser.errors, status=400)

    def delete(self, request, pk):
        year = self._get(request, pk)
        if not year: return Response({'error': 'Not found'}, status=404)
        # Check if used in divisions
        if year.divisions.exists():
            return Response({'error': 'Cannot delete academic year in use by divisions.'}, status=400)
        year.delete()
        return Response({'success': True})

class SetCurrentAcademicYearView(APIView):
    permission_classes = [IsCollegeAdmin | IsSuperAdmin]

    def post(self, request, pk):
        try:
            year = AcademicYear.objects.get(pk=pk, college=request.user.college)
        except AcademicYear.DoesNotExist:
            return Response({'error': 'Not found'}, status=404)
        
        # Unset all others for this college
        AcademicYear.objects.filter(
            college=year.college, is_current=True
        ).update(is_current=False)
        
        year.is_current = True
        year.save(update_fields=['is_current'])
        return Response({'success': True, 'message': f'{year.name} set as current.'})


# ══════════════════════════════════════════════════════════
# DIVISIONS
# ══════════════════════════════════════════════════════════

class DivisionListCreateView(APIView):
    def get_permissions(self):
        if self.request.method == 'GET':
            return [] # AllowAny for registration flow
        return [IsLabAssistant()]

    def get(self, request):
        college_id = request.query_params.get('college_id')
        
        if request.user.is_authenticated:
            qs = college_scope(
                request.user,
                Division.objects.select_related(
                    'course', 'academic_year', 'class_coordinator'
                ).filter(is_active=True),
            )
        elif college_id:
            qs = Division.objects.select_related(
                'course', 'academic_year', 'class_coordinator'
            ).filter(college_id=college_id, is_active=True)
        else:
            return Response([])
        course_id       = request.query_params.get('course')
        academic_year_id = request.query_params.get('academic_year')
        year_of_study   = request.query_params.get('year_of_study')

        if course_id:
            qs = qs.filter(course_id=course_id)
        if academic_year_id:
            qs = qs.filter(academic_year_id=academic_year_id)
        if year_of_study:
            qs = qs.filter(year_of_study=year_of_study)

        return Response(
            DivisionSerializer(qs.order_by('course__name', 'year_of_study', 'name'), many=True).data
        )

    def post(self, request):
        ser = DivisionSerializer(data=request.data)
        if ser.is_valid():
            college = (request.user.college
                       if request.user.role != 'super_admin'
                       else None)
            try:
                div = ser.save(college=college)
                return Response(
                    DivisionSerializer(div).data,
                    status=status.HTTP_201_CREATED,
                )
            except IntegrityError:
                return Response(
                    {'error': 'This division already exists for the selected course, year, and academic year.'},
                    status=400,
                )
        return Response(ser.errors, status=400)


class DivisionDetailView(APIView):
    permission_classes = [IsLabAssistant]

    def _get(self, request, pk):
        try:
            d = Division.objects.select_related(
                'course', 'academic_year', 'class_coordinator'
            ).get(pk=pk)
        except Division.DoesNotExist:
            return None
        if request.user.role != 'super_admin' and d.college != request.user.college:
            return None
        return d

    def put(self, request, pk):
        d = self._get(request, pk)
        if not d:
            return Response({'error': 'Not found'}, status=404)
        ser = DivisionSerializer(d, data=request.data, partial=True)
        if ser.is_valid():
            ser.save()
            return Response(ser.data)
        return Response(ser.errors, status=400)

    def delete(self, request, pk):
        d = self._get(request, pk)
        if not d:
            return Response({'error': 'Not found'}, status=404)
        d.is_active = False
        d.save(update_fields=['is_active'])
        return Response({'success': True})


# ══════════════════════════════════════════════════════════
# SUBJECTS
# ══════════════════════════════════════════════════════════

class SubjectListCreateView(APIView):
    permission_classes = [IsCollegeScopedStaff | IsSuperAdmin]

    def get(self, request):
        qs = college_scope(
            request.user,
            Subject.objects.select_related('department', 'course').filter(is_active=True),
        )
        dept_id       = request.query_params.get('department')
        course_id     = request.query_params.get('course')
        year_of_study = request.query_params.get('year_of_study')
        is_lab        = request.query_params.get('is_lab')
        search        = request.query_params.get('search', '')

        if dept_id:
            qs = qs.filter(department_id=dept_id)
        if course_id:
            qs = qs.filter(course_id=course_id)
        if year_of_study:
            qs = qs.filter(year_of_study=year_of_study)
        if is_lab is not None:
            qs = qs.filter(is_lab=is_lab.lower() == 'true')
        if search:
            qs = qs.filter(name__icontains=search)

        return Response(
            SubjectSerializer(qs.order_by('year_of_study', 'semester', 'name'), many=True).data
        )

    def post(self, request):
        ser = SubjectSerializer(data=request.data)
        if ser.is_valid():
            college = (request.user.college
                       if request.user.role != 'super_admin'
                       else None)
            try:
                subj = ser.save(college=college)
                return Response(
                    SubjectSerializer(subj).data,
                    status=status.HTTP_201_CREATED,
                )
            except IntegrityError:
                return Response(
                    {'error': 'A subject with this code already exists.'},
                    status=400,
                )
        return Response(ser.errors, status=400)


class SubjectDetailView(APIView):
    permission_classes = [IsCollegeScopedStaff | IsSuperAdmin]

    def _get(self, request, pk):
        try:
            s = Subject.objects.get(pk=pk)
        except Subject.DoesNotExist:
            return None
        if request.user.role != 'super_admin' and s.college != request.user.college:
            return None
        return s

    def put(self, request, pk):
        s = self._get(request, pk)
        if not s:
            return Response({'error': 'Not found'}, status=404)
        ser = SubjectSerializer(s, data=request.data, partial=True)
        if ser.is_valid():
            ser.save()
            return Response(ser.data)
        return Response(ser.errors, status=400)

    def delete(self, request, pk):
        s = self._get(request, pk)
        if not s:
            return Response({'error': 'Not found'}, status=404)
        s.is_active = False
        s.save(update_fields=['is_active'])
        return Response({'success': True})


# ══════════════════════════════════════════════════════════
# SUBJECT ALLOCATIONS
# ══════════════════════════════════════════════════════════

class SubjectAllocationListCreateView(APIView):
    permission_classes = [IsCollegeScopedStaff | IsSuperAdmin]

    def get(self, request):
        qs = college_scope(
            request.user,
            SubjectAllocation.objects.select_related(
                'subject', 'teacher', 'division', 'academic_year'
            ).filter(is_active=True),
        )
        teacher_id      = request.query_params.get('teacher')
        division_id     = request.query_params.get('division')
        academic_year_id = request.query_params.get('academic_year')

        if teacher_id:
            qs = qs.filter(teacher_id=teacher_id)
        if division_id:
            qs = qs.filter(division_id=division_id)
        if academic_year_id:
            qs = qs.filter(academic_year_id=academic_year_id)

        return Response(
            SubjectAllocationSerializer(qs.order_by('subject__name'), many=True).data
        )

    def post(self, request):
        ser = SubjectAllocationSerializer(data=request.data)
        if ser.is_valid():
            college = (request.user.college
                       if request.user.role != 'super_admin'
                       else None)
            try:
                alloc = ser.save(college=college)
                return Response(
                    SubjectAllocationSerializer(alloc).data,
                    status=status.HTTP_201_CREATED,
                )
            except IntegrityError:
                return Response(
                    {'error': 'This subject is already allocated to this teacher for this division and year.'},
                    status=400,
                )
        return Response(ser.errors, status=400)


class SubjectAllocationDetailView(APIView):
    permission_classes = [IsCollegeScopedStaff | IsSuperAdmin]

    def _get(self, request, pk):
        try:
            a = SubjectAllocation.objects.get(pk=pk)
        except SubjectAllocation.DoesNotExist:
            return None
        if request.user.role != 'super_admin' and a.college != request.user.college:
            return None
        return a

    def delete(self, request, pk):
        a = self._get(request, pk)
        if not a:
            return Response({'error': 'Not found'}, status=404)
        a.is_active = False
        a.save(update_fields=['is_active'])
        return Response({'success': True})


# ══════════════════════════════════════════════════════════
# TEACHER — MY ALLOCATIONS
# ══════════════════════════════════════════════════════════

class MyAllocationsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = SubjectAllocation.objects.select_related(
            'subject', 'division', 'academic_year'
        ).filter(teacher=request.user, is_active=True)
        return Response(
            SubjectAllocationSerializer(qs, many=True).data
        )


# ══════════════════════════════════════════════════════════
# STUDENT ENROLLMENTS
# ══════════════════════════════════════════════════════════

class BulkEnrollView(APIView):
    permission_classes = [IsCollegeScopedStaff | IsSuperAdmin]

    def post(self, request):
        ser = BulkEnrollSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=400)

        alloc_id    = ser.validated_data['subject_allocation_id']
        student_ids = ser.validated_data['student_ids']

        try:
            allocation = SubjectAllocation.objects.get(
                id=alloc_id, is_active=True
            )
        except SubjectAllocation.DoesNotExist:
            return Response({'error': 'Subject allocation not found.'}, status=404)

        if (request.user.role != 'super_admin'
                and allocation.college != request.user.college):
            return Response({'error': 'Forbidden'}, status=403)

        from apps.students.models import StudentProfile, StudentSubjectEnrollment

        enrolled_count = 0
        skipped_count  = 0
        errors         = []

        for student_id in student_ids:
            try:
                profile = StudentProfile.objects.get(
                    id=student_id,
                    is_active=True,
                )
                _, created = StudentSubjectEnrollment.objects.get_or_create(
                    student=profile,
                    subject_allocation=allocation,
                    defaults={
                        'academic_year': allocation.academic_year,
                        'is_active'    : True,
                    },
                )
                if created:
                    enrolled_count += 1
                else:
                    skipped_count += 1
            except StudentProfile.DoesNotExist:
                errors.append(str(student_id))

        return Response({
            'success'        : True,
            'enrolled_count' : enrolled_count,
            'skipped_count'  : skipped_count,  # already enrolled
            'invalid_ids'    : errors,
            'message'        : (
                f'{enrolled_count} students enrolled. '
                f'{skipped_count} already enrolled.'
            ),
        })


class EnrollmentListView(APIView):
    """List enrolled students for a subject allocation."""
    permission_classes = [IsCollegeScopedStaff | IsSuperAdmin]

    def get(self, request):
        alloc_id = request.query_params.get('subject_allocation_id')
        if not alloc_id:
            return Response(
                {'error': 'subject_allocation_id is required'},
                status=400,
            )
        from apps.students.models import StudentSubjectEnrollment
        qs = StudentSubjectEnrollment.objects.select_related(
            'student__user', 'subject_allocation__subject',
        ).filter(
            subject_allocation_id=alloc_id,
            is_active=True,
        )
        data = [
            {
                'enrollment_id': str(e.id),
                'student_id'   : str(e.student.id),
                'student_name' : e.student.user.get_full_name(),
                'prn'          : e.student.prn,
                'roll_number'  : e.student.roll_number,
                'enrolled_at'  : e.enrolled_at.isoformat(),
            }
            for e in qs
        ]
        return Response(data)


# ══════════════════════════════════════════════════════════
# STUDENTS LIST (for enrollment picker)
# ══════════════════════════════════════════════════════════

class StudentsListView(APIView):
    permission_classes = [IsCollegeScopedStaff | IsSuperAdmin]

    def get(self, request):
        from apps.students.models import StudentProfile
        qs = StudentProfile.objects.select_related(
            'user', 'division', 'course'
        ).filter(is_active=True)

        if request.user.role != 'super_admin':
            qs = qs.filter(college=request.user.college)

        division_id   = request.query_params.get('division')
        year_of_study = request.query_params.get('year_of_study')
        search        = request.query_params.get('search', '')

        if division_id:
            qs = qs.filter(division_id=division_id)
        if year_of_study:
            qs = qs.filter(year_of_study=year_of_study)
        if search:
            from django.db.models import Q
            qs = qs.filter(
                Q(prn__icontains=search)
                | Q(user__first_name__icontains=search)
                | Q(user__last_name__icontains=search)
            )

        data = [
            {
                'id'          : str(s.id),
                'name'        : s.user.get_full_name(),
                'email'       : s.user.email,
                'prn'         : s.prn,
                'roll_number' : s.roll_number,
                'year_of_study': s.year_of_study,
                'division_name': s.division.name if s.division else None,
                'course_name' : s.course.name if s.course else None,
                'face_registered': s.face_registered,
            }
            for s in qs.order_by('roll_number')
        ]
        return Response(data)
