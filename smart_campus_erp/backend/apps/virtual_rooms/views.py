from django.db       import IntegrityError
from rest_framework  import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response    import Response
from rest_framework.views       import APIView

from apps.accounts.permissions  import (
    IsCollegeScopedStaff, IsSuperAdmin, IsTeacher,
)
from apps.attendance.models     import AttendanceSession
from .geo_utils                 import check_inside_room, haversine_distance
from .models                    import VirtualRoom
from .serializers               import (
    VirtualRoomSerializer,
    CheckLocationInputSerializer,
)


def _scope(user, qs):
    """Apply college scoping to queryset."""
    if user.role == 'super_admin':
        return qs
    return qs.filter(college=user.college)


# ══════════════════════════════════════════════════════════
# GET /api/virtual-rooms/
# POST /api/virtual-rooms/
# ══════════════════════════════════════════════════════════

class VirtualRoomListCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = _scope(
            request.user,
            VirtualRoom.objects.select_related(
                'college', 'created_by'
            ).filter(is_active=True),
        )

        search   = request.query_params.get('search', '')
        building = request.query_params.get('building', '')
        floor    = request.query_params.get('floor')

        if search:
            qs = qs.filter(name__icontains=search)
        if building:
            qs = qs.filter(building__icontains=building)
        if floor is not None:
            qs = qs.filter(floor_number=floor)

        qs = qs.order_by('building', 'floor_number', 'name')

        return Response(VirtualRoomSerializer(qs, many=True).data)

    def post(self, request):
        permission = IsCollegeScopedStaff | IsSuperAdmin
        # Manual permission check
        if not (
            request.user.is_authenticated and (
                request.user.role in [
                    'college_admin', 'principal', 'hod',
                    'lab_assistant', 'super_admin', 'teacher',
                ]
            )
        ):
            return Response(
                {'error': 'Permission denied.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        ser = VirtualRoomSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)

        college = (
            request.user.college
            if request.user.role != 'super_admin'
            else None
        )

        room = ser.save(
            college    = college,
            created_by = request.user,
        )

        return Response(
            VirtualRoomSerializer(room).data,
            status=status.HTTP_201_CREATED,
        )


# ══════════════════════════════════════════════════════════
# GET /api/virtual-rooms/{id}/
# PUT /api/virtual-rooms/{id}/
# DELETE /api/virtual-rooms/{id}/
# ══════════════════════════════════════════════════════════

class VirtualRoomDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def _get_room(self, request, room_id):
        try:
            room = VirtualRoom.objects.select_related(
                'college', 'created_by'
            ).get(id=room_id)
        except VirtualRoom.DoesNotExist:
            return None
        if (
            request.user.role != 'super_admin'
            and room.college != request.user.college
        ):
            return None
        return room

    def get(self, request, room_id):
        room = self._get_room(request, room_id)
        if not room:
            return Response({'error': 'Room not found.'}, status=404)
        return Response(VirtualRoomSerializer(room).data)

    def put(self, request, room_id):
        room = self._get_room(request, room_id)
        if not room:
            return Response({'error': 'Room not found.'}, status=404)

        if request.user.role not in [
            'college_admin', 'principal', 'hod',
            'lab_assistant', 'super_admin', 'teacher',
        ]:
            return Response({'error': 'Permission denied.'}, status=403)

        ser = VirtualRoomSerializer(room, data=request.data, partial=True)
        if ser.is_valid():
            ser.save()
            return Response(ser.data)
        return Response(ser.errors, status=400)

    def delete(self, request, room_id):
        room = self._get_room(request, room_id)
        if not room:
            return Response({'error': 'Room not found.'}, status=404)

        if request.user.role not in [
            'college_admin', 'principal', 'lab_assistant', 'super_admin',
        ]:
            return Response({'error': 'Permission denied.'}, status=403)

        # Prevent deletion if room has active sessions
        active_sessions = AttendanceSession.objects.filter(
            virtual_room = room,
            status       = 'active',
        ).count()

        if active_sessions > 0:
            return Response(
                {
                    'error': (
                        f'Cannot delete room. '
                        f'{active_sessions} active session(s) are using it.'
                    )
                },
                status=400,
            )

        room.is_active = False
        room.save(update_fields=['is_active'])

        return Response({
            'success': True,
            'message': f'Room "{room.name}" deactivated successfully.',
        })


# ══════════════════════════════════════════════════════════
# POST /api/virtual-rooms/{id}/check-location/
# ══════════════════════════════════════════════════════════

class CheckLocationView(APIView):
    """
    Test if given GPS coordinates are inside this virtual room.
    Used for setup/testing by admin and during attendance.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, room_id):
        room = None
        try:
            room = VirtualRoom.objects.get(id=room_id)
        except VirtualRoom.DoesNotExist:
            return Response({'error': 'Room not found.'}, status=404)

        if (
            request.user.role != 'super_admin'
            and room.college != request.user.college
        ):
            return Response({'error': 'Forbidden.'}, status=403)

        ser = CheckLocationInputSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=400)

        data = ser.validated_data
        geo  = check_inside_room(
            float(data['lat']),
            float(data['lng']),
            float(data['altitude']),
            room,
        )

        return Response({
            'room_id'             : str(room.id),
            'room_name'           : room.name,
            'is_inside'           : geo['inside'],
            'inside_2d'           : geo['inside_2d'],
            'altitude_ok'         : geo['altitude_ok'],
            'distance_from_center': geo['distance_from_center'],
            'distance_to_boundary': geo['distance_to_boundary'],
            'room_radius_meters'  : room.radius_meters,
            'room_center'         : {
                'lat': float(room.center_lat),
                'lng': float(room.center_lng),
            },
            'tested_point'        : {
                'lat'     : data['lat'],
                'lng'     : data['lng'],
                'altitude': data['altitude'],
            },
        })


# ══════════════════════════════════════════════════════════
# GET /api/virtual-rooms/{id}/stats/
# ══════════════════════════════════════════════════════════

class RoomStatsView(APIView):
    """Usage statistics for a virtual room."""
    permission_classes = [IsAuthenticated]

    def get(self, request, room_id):
        try:
            room = VirtualRoom.objects.get(id=room_id)
        except VirtualRoom.DoesNotExist:
            return Response({'error': 'Room not found.'}, status=404)

        if (
            request.user.role != 'super_admin'
            and room.college != request.user.college
        ):
            return Response({'error': 'Forbidden.'}, status=403)

        sessions = AttendanceSession.objects.filter(virtual_room=room)

        total_sessions  = sessions.count()
        active_sessions = sessions.filter(status='active').count()
        ended_sessions  = sessions.filter(status='ended').count()

        avg_attendance = 0.0
        if ended_sessions > 0:
            from django.db.models import Avg, ExpressionWrapper, FloatField
            from django.db.models import F as DjF
            ended = sessions.filter(status='ended')
            total_students_sum  = sum(s.total_students  for s in ended)
            total_present_sum   = sum(s.present_count   for s in ended)
            if total_students_sum > 0:
                avg_attendance = round(
                    total_present_sum / total_students_sum * 100, 1
                )

        # Last 5 sessions
        recent = sessions.select_related(
            'subject_allocation__subject',
            'teacher',
        ).order_by('-created_at')[:5]

        recent_data = [
            {
                'session_code'  : s.session_code,
                'subject_name'  : s.subject_allocation.subject.name,
                'teacher_name'  : s.teacher.get_full_name(),
                'status'        : s.status,
                'present_count' : s.present_count,
                'total_students': s.total_students,
                'created_at'    : s.created_at.isoformat(),
            }
            for s in recent
        ]

        return Response({
            'room_id'          : str(room.id),
            'room_name'        : room.name,
            'total_sessions'   : total_sessions,
            'active_sessions'  : active_sessions,
            'ended_sessions'   : ended_sessions,
            'avg_attendance_pct': avg_attendance,
            'recent_sessions'  : recent_data,
        })
