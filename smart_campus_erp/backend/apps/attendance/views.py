import random
import string
import logging

logger = logging.getLogger(__name__)

from django.db.models import F
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import DeviceRegistry
from apps.accounts.permissions import IsTeacher, IsStudent, IsCollegeScopedStaff, IsSuperAdmin
from apps.academic.models import SubjectAllocation
from apps.students.models import StudentProfile, StudentSubjectEnrollment
from apps.virtual_rooms.models import VirtualRoom
from apps.virtual_rooms.geo_utils import check_inside_room
from apps.face_recognition.models import FaceDescriptor
from apps.face_recognition.face_utils import verify_face

from .models import AttendanceSession, AttendanceLog
from .serializers import (
    AttendanceSessionSerializer,
    AttendanceLogSerializer,
    CreateSessionSerializer,
    MarkAttendanceSerializer,
    CheckLocationSerializer,
    ManualAttendanceSerializer,
)

logger = logging.getLogger(__name__)


def _generate_session_code() -> str:
    """Generate unique 6-char alphanumeric session code."""
    while True:
        code = ''.join(
            random.choices(string.ascii_uppercase + string.digits, k=6)
        )
        if not AttendanceSession.objects.filter(session_code=code).exists():
            return code

from django.core.cache import cache

def auto_close_expired_sessions():
    """
    Production Optimized: Closes sessions expired > 10 mins ago.
    Uses execution cooldown and optimized queries to prevent API timeouts.
    """
    # Execution cooldown (run max once per 30 seconds)
    lock_key = "attendance_auto_close_lock"
    if cache.get(lock_key):
        return
    cache.set(lock_key, True, 30)

    now = timezone.now()
    threshold = now - timezone.timedelta(minutes=10)
    
    expired_sessions = AttendanceSession.objects.filter(
        status='active',
        actual_start__lte=threshold
    ).select_related('subject_allocation', 'college')
    
    if not expired_sessions.exists():
        return

    for session in expired_sessions:
        # Use a transaction-safe update
        session.status = 'ended'
        session.actual_end = session.actual_start + timezone.timedelta(minutes=10)
        session.save(update_fields=['status', 'actual_end'])
        
        # Mark remaining enrolled students as absent (Optimized lookup)
        enrolled_user_ids = StudentSubjectEnrollment.objects.filter(
            subject_allocation=session.subject_allocation,
            is_active=True
        ).values_list('student__user_id', flat=True)
        
        marked_user_ids = AttendanceLog.objects.filter(
            session=session
        ).values_list('student_id', flat=True)
        
        absent_ids = set(enrolled_user_ids) - set(marked_user_ids)
        
        if absent_ids:
            AttendanceLog.objects.bulk_create([
                AttendanceLog(
                    session=session,
                    student_id=uid,
                    college=session.college,
                    status='absent',
                    is_verified_gps=False,
                    is_verified_face=False,
                )
                for uid in absent_ids
            ], ignore_conflicts=True)


# ══════════════════════════════════════════════════════════
# POST /api/attendance/sessions/   — Teacher creates session
# ══════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════
# GET /api/attendance/sessions/my/
# Returns all sessions created by logged-in teacher
# ══════════════════════════════════════════════════════════

class MySessionsView(APIView):
    permission_classes = [IsTeacher]

    def get(self, request):
        auto_close_expired_sessions()
        status_filter = request.query_params.get('status')
        limit         = int(request.query_params.get('limit', 30))

        qs = AttendanceSession.objects.select_related(
            'subject_allocation__subject',
            'subject_allocation__division',
            'virtual_room',
        ).filter(teacher=request.user).order_by('-created_at')

        if status_filter:
            qs = qs.filter(status=status_filter)

        qs = qs[:limit]

        data = []
        for s in qs:
            duration_minutes = None
            if s.actual_start and s.actual_end:
                delta = s.actual_end - s.actual_start
                duration_minutes = int(delta.total_seconds() / 60)
            elif s.actual_start and s.status == 'active':
                delta = timezone.now() - s.actual_start
                duration_minutes = int(delta.total_seconds() / 60)

            data.append({
                'id'             : str(s.id),
                'session_code'   : s.session_code,
                'status'         : s.status,
                'subject_name'   : s.subject_allocation.subject.name,
                'subject_code'   : s.subject_allocation.subject.code,
                'division_name'  : s.subject_allocation.division.name,
                'year_of_study'  : s.subject_allocation.division.year_of_study,
                'room_name'      : s.virtual_room.name if s.virtual_room else None,
                'total_students' : s.total_students,
                'present_count'  : s.present_count,
                'absent_count'   : max(0, s.total_students - s.present_count),
                'attendance_pct' : round(
                    s.present_count / s.total_students * 100, 1
                ) if s.total_students > 0 else 0.0,
                'scheduled_start'   : s.scheduled_start.isoformat(),
                'scheduled_end'     : s.scheduled_end.isoformat(),
                'actual_start'      : s.actual_start.isoformat() if s.actual_start else None,
                'actual_end'        : s.actual_end.isoformat()   if s.actual_end   else None,
                'duration_minutes'  : duration_minutes,
                'created_at'        : s.created_at.isoformat(),
            })

        active_count = AttendanceSession.objects.filter(
            teacher=request.user, status='active'
        ).count()

        return Response({
            'sessions'     : data,
            'total'        : len(data),
            'active_count' : active_count,
        })


# ══════════════════════════════════════════════════════════
# POST /api/attendance/sessions/
# Teacher creates and starts a new session
# ══════════════════════════════════════════════════════════

class CreateSessionView(APIView):
    permission_classes = [IsTeacher]

    def post(self, request):
        alloc_id    = request.data.get('subject_allocation_id')
        room_id     = request.data.get('virtual_room_id')
        sched_start = request.data.get('scheduled_start')
        sched_end   = request.data.get('scheduled_end')
        
        # Teacher's location fields
        t_lat       = request.data.get('teacher_lat')
        t_lng       = request.data.get('teacher_lng')
        t_alt       = float(request.data.get('teacher_altitude', 0.0))
        t_acc       = float(request.data.get('teacher_accuracy', 10.0))
        radius      = float(request.data.get('radius_meters', 30.0))

        if not alloc_id:
            return Response(
                {'error': 'subject_allocation_id is required.'},
                status=400,
            )
        if not room_id:
            return Response(
                {'error': 'virtual_room_id is required.'},
                status=400,
            )
        if not sched_start or not sched_end:
            return Response(
                {'error': 'scheduled_start and scheduled_end are required.'},
                status=400,
            )

        # Validate allocation belongs to this teacher
        try:
            allocation = SubjectAllocation.objects.select_related(
                'subject', 'division', 'college'
            ).get(
                id=alloc_id,
                teacher=request.user,
                is_active=True,
            )
        except SubjectAllocation.DoesNotExist:
            return Response(
                {'error': 'Subject allocation not found or not assigned to you.'},
                status=404,
            )

        # Validate virtual room belongs to same college
        try:
            room = VirtualRoom.objects.get(
                id=room_id,
                college=request.user.college,
                is_active=True,
            )
        except VirtualRoom.DoesNotExist:
            return Response(
                {'error': 'Virtual room not found.'},
                status=404,
            )

        # Block duplicate active sessions for same subject+division
        existing = AttendanceSession.objects.filter(
            subject_allocation=allocation,
            status='active',
        ).first()
        if existing:
            return Response(
                {
                    'error': (
                        f'An active session already exists for this subject. '
                        f'Session code: {existing.session_code}. '
                        f'Please end it before starting a new one.'
                    ),
                },
                status=400,
            )

        # Parse datetime
        from django.utils.dateparse import parse_datetime
        start_dt = parse_datetime(sched_start)
        end_dt   = parse_datetime(sched_end)

        if not start_dt or not end_dt:
            return Response(
                {'error': 'Invalid datetime format. Use ISO 8601.'},
                status=400,
            )
        if end_dt <= start_dt:
            return Response(
                {'error': 'End time must be after start time.'},
                status=400,
            )

        # Count enrolled students
        total_students = StudentSubjectEnrollment.objects.filter(
            subject_allocation=allocation,
            is_active=True,
        ).count()

        session = AttendanceSession.objects.create(
            college            = request.user.college,
            subject_allocation = allocation,
            virtual_room       = room,
            teacher            = request.user,
            session_code       = _generate_session_code(),
            status             = 'active',
            scheduled_start    = start_dt,
            scheduled_end      = end_dt,
            actual_start       = timezone.now(),
            teacher_lat        = t_lat,
            teacher_lng        = t_lng,
            teacher_altitude   = t_alt,
            teacher_accuracy   = t_acc,
            radius_meters      = radius,
            total_students     = total_students,
            present_count      = 0,
        )

        return Response(
            {
                'success'     : True,
                'session_id'  : str(session.id),
                'session_code': session.session_code,
                'subject_name': allocation.subject.name,
                'division'    : allocation.division.name,
                'room_name'   : room.name,
                'total_students': total_students,
                'message'     : (
                    f'Session started! Code: {session.session_code}. '
                    f'{total_students} students enrolled.'
                ),
            },
            status=201,
        )


# ══════════════════════════════════════════════════════════
# POST /api/attendance/sessions/{id}/end/
# Teacher ends an active session
# ══════════════════════════════════════════════════════════

class EndSessionView(APIView):
    permission_classes = [IsTeacher]

    def post(self, request, session_id):
        try:
            session = AttendanceSession.objects.select_related(
                'subject_allocation__subject',
            ).get(
                id=session_id,
                teacher=request.user,
                status='active',
            )
        except AttendanceSession.DoesNotExist:
            return Response(
                {'error': 'Active session not found.'},
                status=404,
            )

        session.status     = 'ended'
        session.actual_end = timezone.now()
        session.save(update_fields=['status', 'actual_end'])

        # Auto-mark absent for students who did not mark attendance
        enrolled_user_ids = StudentSubjectEnrollment.objects.filter(
            subject_allocation=session.subject_allocation,
            is_active=True,
        ).values_list('student__user_id', flat=True)

        marked_user_ids = AttendanceLog.objects.filter(
            session=session
        ).values_list('student_id', flat=True)

        absent_ids = set(enrolled_user_ids) - set(marked_user_ids)

        if absent_ids:
            AttendanceLog.objects.bulk_create([
                AttendanceLog(
                    session          = session,
                    student_id       = uid,
                    college          = session.college,
                    status           = 'absent',
                    is_verified_gps  = False,
                    is_verified_face = False,
                )
                for uid in absent_ids
            ], ignore_conflicts=True)

        return Response({
            'success'      : True,
            'message'      : 'Session ended successfully.',
            'present_count': session.present_count,
            'absent_count' : len(absent_ids),
            'total'        : session.total_students,
        })


# ══════════════════════════════════════════════════════════
# GET /api/attendance/sessions/active/
# ══════════════════════════════════════════════════════════

class ActiveSessionsView(APIView):
    permission_classes = [IsTeacher | IsCollegeScopedStaff | IsStudent | IsSuperAdmin]

    def get(self, request):
        auto_close_expired_sessions()
        user = request.user
        now = timezone.now()

        if user.role == 'student':
            try:
                student_profile = user.student_profile
                student_division = student_profile.division
            except AttributeError:
                return Response({'error': 'Student profile not found.'}, status=404)

            if not student_division:
                return Response({'error': 'Student not assigned to any division.'}, status=400)

            # High Performance Query: select_related everything to avoid N+1
            sessions = AttendanceSession.objects.select_related(
                'teacher',
                'subject_allocation__subject',
                'subject_allocation__teacher',
                'subject_allocation__division',
                'virtual_room',
            ).filter(
                status = 'active',
                college = user.college,
                subject_allocation__division = student_division,
                actual_start__gt = now - timezone.timedelta(minutes=10)
            ).order_by('-actual_start')

            if not sessions.exists():
                return Response([])

            # Pre-fetch existing marks for this student
            marked_session_ids = set(AttendanceLog.objects.filter(
                student = user,
                session__in = sessions
            ).values_list('session_id', flat=True))

            # Eligibility Optimization:
            # 1. My explicit enrollments
            alloc_ids = [s.subject_allocation_id for s in sessions]
            my_enrolled_alloc_ids = set(StudentSubjectEnrollment.objects.filter(
                student = student_profile,
                subject_allocation_id__in = alloc_ids,
                is_active = True
            ).values_list('subject_allocation_id', flat=True))

            # 2. Identify Elective vs Core subjects
            # Allocations with ANY enrollments are treated as Electives
            allocs_with_enrollments = set(StudentSubjectEnrollment.objects.filter(
                subject_allocation_id__in = alloc_ids,
                is_active = True
            ).values_list('subject_allocation_id', flat=True))

            result = []
            for s in sessions:
                # Student is eligible if: 
                # They are explicitly enrolled OR subject is Core (no explicit enrollments defined)
                is_eligible = (s.subject_allocation_id in my_enrolled_alloc_ids) or \
                              (s.subject_allocation_id not in allocs_with_enrollments)
                
                if is_eligible:
                    data = AttendanceSessionSerializer(s).data
                    data['already_marked'] = s.id in marked_session_ids
                    result.append(data)

            return Response(result)

        elif user.role in ('teacher', 'lab_assistant'):
            sessions = AttendanceSession.objects.select_related(
                'subject_allocation__subject',
                'subject_allocation__division',
                'virtual_room',
            ).filter(
                status  = 'active',
                teacher = user,
            )
            return Response(
                AttendanceSessionSerializer(sessions, many=True).data
            )

        else:
            # HOD / Principal / Admin — see all active sessions for college
            sessions = AttendanceSession.objects.select_related(
                'subject_allocation__subject',
                'subject_allocation__division',
                'virtual_room',
                'teacher',
            ).filter(
                status  = 'active',
                college = user.college,
            )
            return Response(
                AttendanceSessionSerializer(sessions, many=True).data
            )


# ══════════════════════════════════════════════════════════
# POST /api/attendance/check-location/
# ══════════════════════════════════════════════════════════

class CheckLocationView(APIView):
    """
    Pre-check: is the student inside the virtual room?
    Called before opening camera. Fast, no face check.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        ser = CheckLocationSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=400)

        data = ser.validated_data

        try:
            session = AttendanceSession.objects.select_related(
                'virtual_room',
                'subject_allocation__subject',
            ).get(
                id     = data['session_id'],
                status = 'active',
            )
        except AttendanceSession.DoesNotExist:
            return Response(
                {'error': 'Session not found or not active.'},
                status=404,
            )

        # Determine effective room (use VirtualRoom if assigned, otherwise fallback to teacher-centered MockRoom)
        room = session.virtual_room
        if not room:
            center_lat = float(session.teacher_lat or 0)
            center_lng = float(session.teacher_lng or 0)
            
            class MockRoom:
                def __init__(self, clat, clng, rad):
                    self.center_lat = clat
                    self.center_lng = clng
                    self.min_altitude = 0.0
                    self.max_altitude = 50.0
                    self.radius_meters = rad
                    self.has_polygon = False

            effective_room = MockRoom(center_lat, center_lng, session.radius_meters)
        else:
            effective_room = room
            center_lat = float(room.center_lat)
            center_lng = float(room.center_lng)

        geo = check_inside_room(
            float(data['lat']),
            float(data['lng']),
            float(data['altitude']),
            effective_room,
            horizontal_accuracy=float(data.get('accuracy', 10.0)),
            custom_radius=float(session.radius_meters),
        )

        logger.info(
            'GEO-CHECK: user=%s session=%s | '
            'student=(%.7f, %.7f, alt=%.1f) | '
            'center=(%.7f, %.7f) radius_used=%.1fm | '
            'distance=%.2fm inside=%s alt_ok=%s',
            request.user.email, session.session_code,
            float(data['lat']), float(data['lng']), float(data['altitude']),
            center_lat, center_lng, 
            geo['radius_used'],
            geo['distance_from_center'], geo['inside'], geo['altitude_ok'],
        )

        return Response({
            'is_inside'           : geo['inside'],
            'inside_2d'           : geo['inside_2d'],
            'altitude_ok'         : geo['altitude_ok'],
            'distance_to_boundary': geo['distance_to_boundary'],
            'distance_from_center': geo['distance_from_center'],
            'radius_used'         : geo['radius_used'],
            'validation_mode'     : geo['validation_mode'],
            'accuracy_slack'      : geo['accuracy_slack_applied'],
            'session_code'        : session.session_code,
            'subject_name'        : session.subject_allocation.subject.name,
            'room_name'           : room.name if room else 'Classroom Area',
        })


# ══════════════════════════════════════════════════════════
# GET /api/attendance/sessions/{id}/validate/
# Student checks if session is still valid before starting flow
# ══════════════════════════════════════════════════════════

class ValidateSessionView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, session_id):
        try:
            session = AttendanceSession.objects.select_related(
                'subject_allocation__subject',
                'virtual_room',
            ).get(id=session_id)
        except AttendanceSession.DoesNotExist:
            return Response({'error': 'Session not found.'}, status=404)

        if session.status != 'active':
            return Response({
                'error': f'Session is {session.status}. Please wait for teacher or contact admin.',
                'status': session.status
            }, status=400)

        # Check if student belongs to the session's Division/Year
        if request.user.role == 'student':
            try:
                profile = request.user.student_profile
                if profile.division != session.subject_allocation.division or \
                   profile.year_of_study != session.subject_allocation.division.year_of_study:
                    return Response({'error': 'Unauthorized. This session is not for your Year/Division.'}, status=403)
            except AttributeError:
                return Response({'error': 'Student profile not found.'}, status=404)

        return Response({
            'id': str(session.id),
            'status': session.status,
            'subject_name': session.subject_allocation.subject.name,
            'room_name': session.virtual_room.name if session.virtual_room else 'N/A',
            'session_code': session.session_code,
            'is_valid': True
        })


# ══════════════════════════════════════════════════════════
# POST /api/attendance/mark/   — 5-step pipeline
# ══════════════════════════════════════════════════════════

class MarkAttendanceView(APIView):
    permission_classes = [IsStudent]

    def post(self, request):
        ser = MarkAttendanceSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=400)

        data = ser.validated_data

        # ── STEP 1: Session validation ─────────────────────
        try:
            session = AttendanceSession.objects.select_related(
                'subject_allocation__subject',
                'virtual_room',
                'college',
            ).get(
                id     = data['session_id'],
                status = 'active',
            )
        except AttendanceSession.DoesNotExist:
            return Response(
                {'error': 'Session not found or not active.'},
                status=404,
            )

        # Check if student belongs to the session's Division/Year
        try:
            profile = request.user.student_profile
        except AttributeError:
            return Response({'error': 'Student profile not found.'}, status=404)

        if profile.division != session.subject_allocation.division:
            return Response(
                {'error': 'You do not belong to this Division.'},
                status=403,
            )
        
        if profile.year_of_study != session.subject_allocation.division.year_of_study:
            return Response(
                {'error': 'You do not belong to this Year.'},
                status=403,
            )

        # ── STEP 1.5: Enrollment Check ─────────────────────
        # Eligibility Logic: 
        # 1. Student is explicitly enrolled
        # 2. OR the student belongs to the division and there are NO explicit enrollments 
        #    for this allocation (treating it as a Core/Auto-enrolled subject)
        
        is_eligible = StudentSubjectEnrollment.objects.filter(
            student            = profile,
            subject_allocation = session.subject_allocation,
            is_active          = True
        ).exists()

        if not is_eligible:
            # Fallback for Core subjects
            has_any_enrollments = StudentSubjectEnrollment.objects.filter(
                subject_allocation = session.subject_allocation,
                is_active = True
            ).exists()
            if not has_any_enrollments:
                is_eligible = True

        if not is_eligible:
            return Response(
                {'error': 'You are not enrolled in this subject and it requires manual enrollment.'},
                status=403,
            )

        # ── STEP 2: Geo validation ─────────────────────────
        room = session.virtual_room
        center_lat = float(room.center_lat) if room else float(session.teacher_lat or 0)
        center_lng = float(room.center_lng) if room else float(session.teacher_lng or 0)
        
        if not room and (not session.teacher_lat or not session.teacher_lng):
            return Response(
                {'error': 'No geo-reference (room or teacher GPS) found for this session.'},
                status=400,
            )

        # Mock room if needed
        class MockRoom:
            def __init__(self, clat, clng, ralt_min, ralt_max, rad):
                self.center_lat = clat
                self.center_lng = clng
                self.min_altitude = 0.0
                self.max_altitude = 50.0
                self.radius_meters = rad

        effective_room = room if room else MockRoom(center_lat, center_lng, 0.0, 50.0, session.radius_meters)

        geo = check_inside_room(
            float(data['lat']),
            float(data['lng']),
            float(data['altitude']),
            effective_room,
            horizontal_accuracy=float(data.get('accuracy', 10.0)),
            custom_radius=float(session.radius_meters),
        )

        # ── EXTRA SECURITY: Teacher-Student Proximity Check ──
        # Even if the room is big, teacher and student should be in same general area
        if session.teacher_lat and session.teacher_lng:
            from apps.virtual_rooms.geo_utils import haversine_distance
            dist_to_teacher = haversine_distance(
                data['lat'], data['lng'],
                session.teacher_lat, session.teacher_lng
            )
            # Max allowed distance from teacher: 150m (standard classroom/hall size + buffer)
            if dist_to_teacher > 150.0:
                return Response({
                    'error': 'You are too far from the teacher\'s verified location.',
                    'details': f'Distance: {dist_to_teacher:.1f}m'
                }, status=403)

        if not geo['inside']:
            reason = []
            if not geo['inside_2d']:
                reason.append(
                    f'You are {geo["distance_to_boundary"]}m outside '
                    f'the classroom boundary.'
                )
            if not geo['altitude_ok']:
                reason.append('You appear to be on the wrong floor.')
            return Response(
                {
                    'error'               : ' '.join(reason) or 'Outside classroom.',
                    'distance_to_boundary': geo['distance_to_boundary'],
                    'inside_2d'           : geo['inside_2d'],
                    'altitude_ok'         : geo['altitude_ok'],
                    'step_failed'         : 'geo',
                },
                status=403,
            )

        # ── STEP 3: Duplicate check ────────────────────────
        if AttendanceLog.objects.filter(
            session = session,
            student = request.user,
        ).exists():
            return Response(
                {'error': 'You have already marked attendance for this session.'},
                status=409,
            )

        # ── STEP 4: Device check ───────────────────────────
        device_id = data['device_id']
        device_ok = DeviceRegistry.objects.filter(
            user      = request.user,
            device_id = device_id,
            is_active = True,
        ).exists()

        if not device_ok:
            return Response(
                {
                    'error': (
                        'This device is not registered for your account. '
                        'Please register your device first.'
                    ),
                    'step_failed': 'device',
                },
                status=403,
            )

        # ── STEP 5: Blink liveness check ──────────────────
        blink_count = data['blink_count']
        if blink_count < 3:
            return Response(
                {
                    'error'      : (
                        f'Liveness check failed. '
                        f'You blinked {blink_count} time(s). '
                        f'Please blink exactly 3 times.'
                    ),
                    'step_failed': 'liveness',
                },
                status=403,
            )

        # ── STEP 5b: Face recognition ──────────────────────
        try:
            profile    = request.user.student_profile
            descriptor = FaceDescriptor.objects.get(student=profile)
        except StudentProfile.DoesNotExist:
            return Response(
                {'error': 'Student profile not found.', 'step_failed': 'face'},
                status=403,
            )
        except FaceDescriptor.DoesNotExist:
            return Response(
                {
                    'error': (
                        'Your face is not registered. '
                        'Please contact your lab assistant to register your face.'
                    ),
                    'step_failed': 'face',
                },
                status=403,
            )

        face_result = verify_face(data['face_image_b64'], descriptor.embedding)

        if not face_result['match']:
            return Response(
                {
                    'error'      : face_result['reason'],
                    'confidence' : face_result['confidence'],
                    'step_failed': 'face',
                },
                status=403,
            )

        # ── ALL STEPS PASSED → Mark present ───────────────
        log = AttendanceLog.objects.create(
            session          = session,
            student          = request.user,
            college          = session.college,
            status           = 'present',
            marked_lat       = data['lat'],
            marked_lng       = data['lng'],
            marked_altitude  = data['altitude'],
            device_id        = device_id,
            face_confidence  = face_result['confidence'],
            blink_count      = blink_count,
            compass_direction = data.get('compass_direction', 0.0),
            device_movement   = data.get('device_movement', ''),
            is_verified_gps  = True,
            is_verified_face = True,
            ip_address       = request.META.get('REMOTE_ADDR'),
        )

        # Increment present count atomically
        AttendanceSession.objects.filter(id=session.id).update(
            present_count=F('present_count') + 1
        )

        return Response(
            {
                'success'       : True,
                'status'        : 'present',
                'marked_at'     : log.marked_at.isoformat(),
                'subject_name'  : session.subject_allocation.subject.name,
                'session_code'  : session.session_code,
                'face_confidence': face_result['confidence'],
                'message'       : (
                    f'Attendance marked successfully for '
                    f'{session.subject_allocation.subject.name}.'
                ),
            },
            status=200,
        )


# ══════════════════════════════════════════════════════════
# POST /api/attendance/manual/   — Teacher manual attendance
# ══════════════════════════════════════════════════════════

class ManualAttendanceView(APIView):
    permission_classes = [IsTeacher | IsCollegeScopedStaff]

    def post(self, request):
        ser = ManualAttendanceSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=400)

        data = ser.validated_data

        try:
            session = AttendanceSession.objects.get(
                id      = data['session_id'],
                teacher = request.user,
            )
        except AttendanceSession.DoesNotExist:
            return Response({'error': 'Session not found.'}, status=404)

        from django.contrib.auth import get_user_model
        User = get_user_model()
        try:
            student_user = User.objects.get(
                id     = data['student_id'],
                role   = 'student',
                college= request.user.college,
            )
        except User.DoesNotExist:
            return Response({'error': 'Student not found.'}, status=404)

        log, created = AttendanceLog.objects.get_or_create(
            session = session,
            student = student_user,
            defaults={
                'college'        : session.college,
                'status'         : 'manual',
                'manual_reason'  : data['reason'],
                'marked_by'      : request.user,
                'is_verified_gps': False,
                'is_verified_face': False,
            },
        )

        if not created:
            # Update existing log to manual
            log.status        = 'manual'
            log.manual_reason = data['reason']
            log.marked_by     = request.user
            log.save(update_fields=['status', 'manual_reason', 'marked_by'])

        return Response({
            'success': True,
            'message': f'Manual attendance marked for '
                       f'{student_user.get_full_name()}.',
        })


# ══════════════════════════════════════════════════════════
# GET /api/attendance/sessions/{id}/logs/
# ══════════════════════════════════════════════════════════

class SessionLogsView(APIView):
    permission_classes = [IsTeacher | IsCollegeScopedStaff]

    def get(self, request, session_id):
        try:
            session = AttendanceSession.objects.get(
                id      = session_id,
                college = request.user.college,
            )
        except AttendanceSession.DoesNotExist:
            return Response({'error': 'Session not found.'}, status=404)

        # Production Requirement: Teacher should see all students in the division
        # Get all students enrolled/assigned to this division
        from apps.students.models import StudentProfile
        all_students = StudentProfile.objects.filter(
            division = session.subject_allocation.division,
            is_active = True
        ).select_related('user')

        logs = AttendanceLog.objects.select_related(
            'student', 'marked_by'
        ).filter(session=session).order_by('marked_at')
        
        marked_student_ids = logs.values_list('student_id', flat=True)
        pending_students = all_students.exclude(user_id__in=marked_student_ids)

        return Response({
            'session'         : AttendanceSessionSerializer(session).data,
            'logs'            : AttendanceLogSerializer(logs, many=True).data,
            'pending_students': [
                {
                    'id': str(s.user.id),
                    'name': s.user.get_full_name(),
                    'prn': s.prn,
                    'roll_number': s.roll_number
                } for s in pending_students
            ],
            'present_count'   : logs.filter(status='present').count(),
            'absent_count'    : logs.filter(status='absent').count(),
            'manual_count'    : logs.filter(status='manual').count(),
            'total_in_division': all_students.count(),
        })
