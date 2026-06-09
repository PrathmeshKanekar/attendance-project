import logging
import math
from django.utils import timezone
from django.db import transaction
from django.db.models import Q
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import VirtualRoom, RoomCorner, RoomPresence, RoomEntryLog, VirtualRoomAuditLog, VirtualRoomSecurityLog
from .serializers import VirtualRoomSerializer, RoomPresenceSerializer, DuplicateCheckSerializer
from .permissions import IsLabAssistantOrReadOnly
from .geo_utils import check_inside_room

logger = logging.getLogger(__name__)

# ─── Stale presence cleanup threshold (seconds) ───────────────────────────────
PRESENCE_STALE_SECONDS = 120  # Mark as exited if no heartbeat for 120s


def _cleanup_stale_presence():
    """Mark users as exited if no heartbeat received in PRESENCE_STALE_SECONDS."""
    cutoff = timezone.now() - timezone.timedelta(seconds=PRESENCE_STALE_SECONDS)
    stale = RoomPresence.objects.filter(is_inside=True, last_heartbeat__lt=cutoff)
    for p in stale:
        p.mark_exited()
        RoomEntryLog.objects.create(
            room=p.room, user=p.user, college=p.college,
            event=RoomEntryLog.EXIT,
            lat=p.last_lat, lng=p.last_lng, accuracy=p.last_accuracy,
            meta={'reason': 'stale_heartbeat_auto_exit'},
        )


# ─── VirtualRoom CRUD ─────────────────────────────────────────────────────────

class VirtualRoomViewSet(viewsets.ModelViewSet):
    """
    CRUD for VirtualRooms.
    Only Lab Assistants can create/update/delete.
    All authenticated users in the same college can read.
    """
    queryset = VirtualRoom.objects.all().prefetch_related('corners')
    serializer_class = VirtualRoomSerializer
    permission_classes = [IsLabAssistantOrReadOnly]
    search_fields = ['name', 'building', 'department']
    ordering_fields = ['name', 'created_at', 'floor_number', 'capacity']
    filterset_fields = ['building', 'department', 'floor_number', 'is_active']

    def get_queryset(self):
        queryset = super().get_queryset()
        # Exclude soft-deleted rooms by default
        queryset = queryset.filter(is_deleted=False)
        user = self.request.user
        if user and user.is_authenticated and hasattr(user, 'college') and user.college:
            queryset = queryset.filter(college=user.college)
            if user.role == 'lab_assistant':
                from apps.accounts.rbac import get_lab_assistant_departments
                depts = get_lab_assistant_departments(user)
                dept_names_and_codes = []
                for d in depts:
                    dept_names_and_codes.append(d.name)
                    dept_names_and_codes.append(d.code)
                queryset = queryset.filter(department__in=dept_names_and_codes)
        return queryset

    @action(detail=True, methods=['get'], url_path='occupancy',
            permission_classes=[IsAuthenticated])
    def occupancy(self, request, pk=None):
        """
        GET /api/virtual-rooms/{id}/occupancy/
        Returns live occupancy count and user list for a room.
        """
        room = self.get_object()
        _cleanup_stale_presence()

        active_presence = RoomPresence.objects.filter(
            room=room, is_inside=True
        ).select_related('user').order_by('-last_heartbeat')

        users_inside = []
        for p in active_presence:
            users_inside.append({
                'user_id': str(p.user.id),
                'name': f"{p.user.first_name} {p.user.last_name}".strip(),
                'role': p.user.role,
                'last_heartbeat': p.last_heartbeat.isoformat(),
                'entered_at': p.entered_at.isoformat(),
                'last_accuracy': p.last_accuracy,
            })

        return Response({
            'room_id': str(room.id),
            'room_name': room.name,
            'total_inside': len(users_inside),
            'users': users_inside,
            'timestamp': timezone.now().isoformat(),
        })

    # ─── Duplicate Check ──────────────────────────────────────────────────────
    @action(detail=False, methods=['post'], url_path='duplicate-check',
            permission_classes=[IsAuthenticated])
    def duplicate_check(self, request):
        """
        POST /api/virtual-rooms/duplicate-check/
        Pre-save duplicate check. Returns list of conflicts.
        """
        serializer = DuplicateCheckSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        user = request.user
        college = getattr(user, 'college', None)
        if not college:
            return Response({'error': 'User has no college.'}, status=400)

        conflicts = []
        base_qs = VirtualRoom.objects.filter(college=college, is_deleted=False)

        # Check 1 — Metadata match (department + building + floor + room_number)
        if data.get('room_number'):
            meta_match = base_qs.filter(
                department__iexact=data['department'],
                building__iexact=data['building'],
                floor_number=int(data['floor']) if data['floor'].lstrip('-').isdigit() else 0,
                room_number__iexact=data['room_number'],
            ).first()
            if meta_match:
                conflicts.append({
                    'check': 'metadata_match',
                    'severity': 'hard',
                    'message': f"Room '{meta_match.name}' (#{meta_match.room_number}) already exists at this exact location.",
                    'conflicting_room_id': str(meta_match.id),
                    'conflicting_room_name': meta_match.name,
                })

        # Check 2 — Name match (department + room_name, case-insensitive)
        if data.get('room_name'):
            name_match = base_qs.filter(
                department__iexact=data['department'],
                name__iexact=data['room_name'],
            ).first()
            if name_match:
                conflicts.append({
                    'check': 'name_match',
                    'severity': 'soft',
                    'message': f"A room named '{name_match.name}' already exists in this department.",
                    'conflicting_room_id': str(name_match.id),
                    'conflicting_room_name': name_match.name,
                })

        # Check 3 — Coordinate proximity (within 3 meters)
        if data.get('center_lat') and data.get('center_lng'):
            new_lat = data['center_lat']
            new_lng = data['center_lng']
            nearby_rooms = base_qs.filter(
                center_lat__isnull=False,
                center_lng__isnull=False,
            ).exclude(center_lat=0.0, center_lng=0.0)

            for room in nearby_rooms:
                dist = _haversine_distance(new_lat, new_lng, room.center_lat, room.center_lng)
                if dist <= 3.0:
                    conflicts.append({
                        'check': 'coordinate_proximity',
                        'severity': 'soft',
                        'message': f"Room '{room.name}' is only {dist:.1f}m away from these coordinates.",
                        'conflicting_room_id': str(room.id),
                        'conflicting_room_name': room.name,
                        'distance_meters': round(dist, 1),
                    })

        has_hard = any(c['severity'] == 'hard' for c in conflicts)

        return Response({
            'has_conflicts': len(conflicts) > 0,
            'has_hard_conflicts': has_hard,
            'conflicts': conflicts,
        })

    # ─── Status Transitions ───────────────────────────────────────────────────
    @action(detail=True, methods=['post'], url_path='validate',
            permission_classes=[IsAuthenticated])
    def validate_room(self, request, pk=None):
        """POST /api/virtual-rooms/{id}/validate/ — created → validated"""
        room = self.get_object()
        if room.status != 'created':
            return Response(
                {'error': f"Cannot validate a room with status '{room.status}'. Expected 'created'."},
                status=400
            )
        room.status = 'validated'
        room.save(update_fields=['status', 'updated_at'])

        VirtualRoomAuditLog.objects.create(
            room=room, event_type='validated',
            actor=request.user,
            actor_role=getattr(request.user, 'role', ''),
            event_data=request.data if request.data else {},
        )
        return Response({'status': 'validated', 'room_id': str(room.id)})

    @action(detail=True, methods=['post'], url_path='certify',
            permission_classes=[IsAuthenticated])
    def certify_room(self, request, pk=None):
        """POST /api/virtual-rooms/{id}/certify/ — validated → certified"""
        room = self.get_object()
        user_role = getattr(request.user, 'role', '')
        if user_role not in ('college_admin', 'principal', 'super_admin'):
            return Response(
                {'error': 'Only supervisors/admins can certify rooms.'},
                status=403
            )
        if room.status != 'validated':
            return Response(
                {'error': f"Cannot certify a room with status '{room.status}'. Expected 'validated'."},
                status=400
            )
        room.status = 'certified'
        room.save(update_fields=['status', 'updated_at'])

        VirtualRoomAuditLog.objects.create(
            room=room, event_type='certified',
            actor=request.user, actor_role=user_role,
            event_data=request.data if request.data else {},
        )
        return Response({'status': 'certified', 'room_id': str(room.id)})

    @action(detail=True, methods=['post'], url_path='activate',
            permission_classes=[IsAuthenticated])
    def activate_room(self, request, pk=None):
        """POST /api/virtual-rooms/{id}/activate/ — certified → active"""
        room = self.get_object()
        if room.status != 'certified':
            return Response(
                {'error': f"Cannot activate a room with status '{room.status}'. Expected 'certified'."},
                status=400
            )
        room.status = 'active'
        room.is_active = True
        room.save(update_fields=['status', 'is_active', 'updated_at'])

        VirtualRoomAuditLog.objects.create(
            room=room, event_type='activated',
            actor=request.user,
            actor_role=getattr(request.user, 'role', ''),
            event_data=request.data if request.data else {},
        )
        return Response({'status': 'active', 'room_id': str(room.id)})

    # ─── Security Log Submission ──────────────────────────────────────────────
    @action(detail=False, methods=['post'], url_path='security-log',
            permission_classes=[IsAuthenticated])
    def security_log(self, request):
        """POST /api/virtual-rooms/security-log/ — client reports a GPS security flag."""
        flag_type = request.data.get('flag_type', 'spoofing_suspected')
        valid_flags = [c[0] for c in VirtualRoomSecurityLog.FLAG_CHOICES]
        if flag_type not in valid_flags:
            flag_type = 'spoofing_suspected'

        VirtualRoomSecurityLog.objects.create(
            room_id=request.data.get('room_id'),
            actor=request.user,
            flag_type=flag_type,
            flag_detail=request.data.get('flag_detail', {}),
            device_info=request.data.get('device_info', {}),
        )
        return Response({'logged': True})


def _haversine_distance(lat1, lng1, lat2, lng2):
    """Calculate distance in meters between two points using haversine."""
    R = 6371000  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


# ─── Room Presence Heartbeat ──────────────────────────────────────────────────

class RoomPresenceHeartbeatView(APIView):
    """
    POST /api/virtual-rooms/{room_id}/presence/heartbeat/

    Called every 10–15s by the Flutter app while the user is on an attendance
    or session screen. The backend re-validates the polygon and updates the
    presence record, returning is_inside so the app can react.

    Body: { lat, lng, accuracy, device_id }
    Returns: { is_inside, distance_to_boundary, validation_mode, stale_exited_count }
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id):
        try:
            room = VirtualRoom.objects.prefetch_related('corners').get(
                id=room_id,
                college=request.user.college,
                is_active=True,
            )
        except VirtualRoom.DoesNotExist:
            return Response({'error': 'Room not found.'}, status=404)

        lat = request.data.get('lat')
        lng = request.data.get('lng')
        accuracy = float(request.data.get('accuracy', 15.0))
        device_id = request.data.get('device_id', '')

        if lat is None or lng is None:
            return Response({'error': 'lat and lng are required.'}, status=400)

        try:
            lat = float(lat)
            lng = float(lng)
        except (TypeError, ValueError):
            return Response({'error': 'lat/lng must be numbers.'}, status=400)

        # ── Server-side polygon check ──────────────────────────────────────
        geo = check_inside_room(
            student_lat=lat, student_lng=lng, student_alt=0.0,
            room=room, gps_accuracy=accuracy,
        )
        is_inside = geo['is_valid']

        # ── Update or create presence record ──────────────────────────────
        with transaction.atomic():
            presence = RoomPresence.objects.filter(
                room=room, user=request.user, is_inside=True
            ).first()

            if is_inside:
                if presence:
                    # Update existing record
                    presence.last_lat = lat
                    presence.last_lng = lng
                    presence.last_accuracy = accuracy
                    presence.device_id = device_id
                    presence.last_heartbeat = timezone.now()
                    presence.save(update_fields=[
                        'last_lat', 'last_lng', 'last_accuracy',
                        'device_id', 'last_heartbeat'
                    ])
                else:
                    # New entry — create record + log entry event
                    presence = RoomPresence.objects.create(
                        room=room, user=request.user,
                        college=request.user.college,
                        last_lat=lat, last_lng=lng,
                        last_accuracy=accuracy, device_id=device_id,
                        is_inside=True,
                    )
                    RoomEntryLog.objects.create(
                        room=room, user=request.user,
                        college=request.user.college,
                        event=RoomEntryLog.ENTRY,
                        lat=lat, lng=lng, accuracy=accuracy,
                        is_polygon_validated=geo['inside_2d'],
                        device_id=device_id,
                        meta={
                            'validation_mode': geo['validation_mode'],
                            'slack_used': geo['slack_used'],
                            'distance_to_centre': geo['distance_to_centre'],
                        },
                    )
            else:
                # User is outside — mark existing presence as exited
                if presence:
                    presence.mark_exited()
                    RoomEntryLog.objects.create(
                        room=room, user=request.user,
                        college=request.user.college,
                        event=RoomEntryLog.EXIT,
                        lat=lat, lng=lng, accuracy=accuracy,
                        is_polygon_validated=False,
                        device_id=device_id,
                        meta={
                            'reason': geo['reason'],
                            'distance_to_boundary': geo['distance_to_boundary'],
                        },
                    )

        # ── Stale cleanup (cheap — runs only on heartbeat calls) ───────────
        stale_cutoff = timezone.now() - timezone.timedelta(seconds=PRESENCE_STALE_SECONDS)
        stale_count = RoomPresence.objects.filter(
            room=room, is_inside=True, last_heartbeat__lt=stale_cutoff
        ).count()

        return Response({
            'is_inside': is_inside,
            'inside_2d': geo.get('inside_2d', False),
            'distance_to_boundary': geo.get('distance_to_boundary', 0.0),
            'distance_to_centre': geo.get('distance_to_centre', 0.0),
            'validation_mode': geo.get('validation_mode', 'denied'),
            'reason': geo.get('reason', ''),
            'slack_used': geo.get('slack_used', 0.0),
            'stale_users_cleaned': stale_count,
            'timestamp': timezone.now().isoformat(),
        })


# ─── Teacher Heartbeat for Session ───────────────────────────────────────────

class TeacherSessionHeartbeatView(APIView):
    """
    POST /api/attendance/sessions/{session_id}/teacher-heartbeat/

    Teacher pings every 15s while session is active.
    If teacher has left the room polygon:
      - session is paused (status='paused')
      - students are notified via session status
    If teacher is back inside:
      - session auto-resumes

    Body: { lat, lng, accuracy }
    Returns: { session_status, is_inside, action_taken }
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, session_id):
        from apps.attendance.models import AttendanceSession

        try:
            session = AttendanceSession.objects.select_related(
                'virtual_room', 'teacher'
            ).get(
                id=session_id,
                teacher=request.user,
            )
        except AttendanceSession.DoesNotExist:
            return Response({'error': 'Session not found.'}, status=404)

        if session.status not in ('active', 'paused'):
            return Response({
                'session_status': session.status,
                'is_inside': False,
                'action_taken': 'none',
                'message': f'Session is already {session.status}.'
            })

        lat = request.data.get('lat')
        lng = request.data.get('lng')
        accuracy = float(request.data.get('accuracy', 15.0))

        if lat is None or lng is None:
            return Response({'error': 'lat and lng are required.'}, status=400)

        room = session.virtual_room
        if not room:
            # No polygon — cannot validate, keep session active
            return Response({
                'session_status': session.status,
                'is_inside': True,
                'action_taken': 'none',
                'message': 'No room polygon configured; assuming inside.',
            })

        geo = check_inside_room(
            student_lat=float(lat), student_lng=float(lng), student_alt=0.0,
            room=room, gps_accuracy=accuracy,
        )
        is_inside = geo['is_valid']

        action_taken = 'none'
        if not is_inside and session.status == 'active':
            session.status = 'paused'
            session.save(update_fields=['status'])
            action_taken = 'session_paused'
            logger.warning(
                'SESSION PAUSED: teacher %s left room %s | session %s | dist_boundary=%.1fm',
                request.user.email, room.name, session.session_code,
                geo.get('distance_to_boundary', 0),
            )
        elif is_inside and session.status == 'paused':
            session.status = 'active'
            session.save(update_fields=['status'])
            action_taken = 'session_resumed'
            logger.info(
                'SESSION RESUMED: teacher %s returned to room %s | session %s',
                request.user.email, room.name, session.session_code,
            )

        return Response({
            'session_status': session.status,
            'is_inside': is_inside,
            'action_taken': action_taken,
            'distance_to_boundary': geo.get('distance_to_boundary', 0.0),
            'validation_mode': geo.get('validation_mode', 'denied'),
            'timestamp': timezone.now().isoformat(),
        })
