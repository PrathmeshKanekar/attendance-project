"""
views.py — Virtual Room REST API Views
========================================
Optimized with select_related/prefetch_related, proper error handling,
and full CRUD + spatial operations.
"""
import logging
from rest_framework import viewsets, status, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from django.db.models import Prefetch
from .models import VirtualRoom, RoomCorner, AttendanceLocationLog
from .serializers import VirtualRoomSerializer, RoomCaptureSerializer, CheckLocationSerializer
from .permissions import IsCollegeAdminOrStaff
from .geo_utils import check_inside_room

logger = logging.getLogger(__name__)


class VirtualRoomViewSet(viewsets.ModelViewSet):
    serializer_class = VirtualRoomSerializer
    permission_classes = [IsCollegeAdminOrStaff]

    def get_queryset(self):
        user = self.request.user
        if not user.is_authenticated:
            return VirtualRoom.objects.none()

        qs = VirtualRoom.objects.select_related(
            'college', 'created_by'
        ).prefetch_related(
            Prefetch('corners', queryset=RoomCorner.objects.order_by('corner_index')),
        )

        if user.role == 'super_admin':
            return qs.all()
        return qs.filter(college=user.college)

    def perform_create(self, serializer):
        serializer.save(
            college=self.request.user.college,
            created_by=self.request.user
        )

    def perform_update(self, serializer):
        serializer.save()

    @action(detail=False, methods=['post'], url_path='capture-corner')
    def capture_corner(self, request):
        """Capture a single corner for incremental room setup."""
        serializer = RoomCaptureSerializer(data=request.data)
        if serializer.is_valid():
            try:
                corner = serializer.save()
                room = corner.room
                return Response({
                    "status": "Corner captured successfully",
                    "corner_index": corner.corner_index,
                    "corner_count": room.corners.count(),
                    "room_finalized": room.use_polygon,
                }, status=status.HTTP_200_OK)
            except Exception as e:
                logger.error("Corner capture failed: %s", e)
                return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=['post'], url_path='check-location')
    def check_location(self, request, pk=None):
        """Check if a GPS coordinate is inside this room's boundaries."""
        return self._perform_location_check(request, pk)

    @action(detail=True, methods=['post'], url_path='validate-attendance')
    def validate_attendance(self, request, pk=None):
        """Validate student location for attendance marking."""
        return self._perform_location_check(request, pk)

    def _perform_location_check(self, request, pk):
        try:
            room = self.get_object()
        except Exception:
            return Response({"error": "Room not found"}, status=status.HTTP_404_NOT_FOUND)

        serializer = CheckLocationSerializer(data=request.data)
        if serializer.is_valid():
            try:
                result = check_inside_room(
                    student_lat=serializer.validated_data['lat'],
                    student_lng=serializer.validated_data['lng'],
                    student_alt=serializer.validated_data['altitude'],
                    room=room,
                    gps_accuracy=serializer.validated_data.get('gps_accuracy', 10.0),
                    sensors=serializer.validated_data.get('sensors', {}),
                )

                # Log the attempt to the forensic table
                try:
                    AttendanceLocationLog.objects.create(
                        room=room,
                        user=request.user if request.user.is_authenticated else None,
                        submitted_lat=serializer.validated_data['lat'],
                        submitted_lng=serializer.validated_data['lng'],
                        submitted_alt=serializer.validated_data['altitude'],
                        gps_accuracy=serializer.validated_data.get('gps_accuracy', 10.0),
                        is_valid=result.get('is_valid', False),
                        validation_mode=result.get('validation_mode', 'unknown'),
                        inside_2d=result.get('inside_2d'),
                        altitude_ok=result.get('altitude_ok'),
                        local_x=result.get('local_x'),
                        local_y=result.get('local_y'),
                        local_z=result.get('local_z'),
                        confidence=result.get('confidence'),
                        spoof_flags=result.get('spoof_flags', []),
                        sensor_snapshot=serializer.validated_data.get('sensors'),
                    )
                except Exception as log_err:
                    logger.warning("Failed to log attendance check: %s", log_err)

                return Response(result, status=status.HTTP_200_OK)
            except Exception as e:
                logger.error("Location check failed for room %s: %s", pk, e)
                return Response(
                    {"error": "Location validation failed", "detail": str(e)},
                    status=status.HTTP_500_INTERNAL_SERVER_ERROR,
                )
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=['delete'], url_path='reset-corners')
    def reset_corners(self, request, pk=None):
        """Reset all captured corners and revert room to radius-only mode."""
        room = self.get_object()
        room.corners.all().delete()
        room.boundary_polygon = None
        room.centroid = None
        room.use_polygon = False
        room.normalized_coordinates = None
        room.orientation_matrix = None
        room.room_dimensions = None
        room.length = None
        room.width = None
        room.area = None
        room.save()

        # Delete spatial vectors too
        try:
            room.spatial_vectors.delete()
        except Exception:
            pass

        return Response({
            "status": "Corners reset and room reverted to radius mode"
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['get'])
    def stats(self, request, pk=None):
        """Get room usage statistics."""
        room = self.get_object()
        logs = AttendanceLocationLog.objects.filter(room=room)
        total = logs.count()
        valid = logs.filter(is_valid=True).count()
        return Response({
            "total_checks": total,
            "valid_checks": valid,
            "validation_rate": round(valid / total * 100, 1) if total > 0 else 0,
            "area": room.area,
            "has_polygon": room.has_polygon,
            "corner_count": room.corner_count,
        })

    @action(detail=True, methods=['get'])
    def preview(self, request, pk=None):
        """Get room spatial data for UI preview rendering."""
        room = self.get_object()

        # Extract corner coordinates for polygon rendering
        corners_data = []
        polygon_coords = []

        for corner in room.corners.order_by('corner_index'):
            corners_data.append({
                "index": corner.corner_index,
                "lat": corner.lat,
                "lng": corner.lng,
                "altitude": corner.altitude,
                "accuracy": corner.accuracy,
                "heading": corner.heading,
            })
            polygon_coords.append({"lat": corner.lat, "lng": corner.lng})

        # Get spatial vectors if available
        spatial_data = None
        try:
            sv = room.spatial_vectors
            spatial_data = {
                "origin": sv.origin_point,
                "x_axis": sv.x_axis_vector,
                "y_axis": sv.y_axis_vector,
                "z_axis": sv.z_axis_vector,
                "x_extent": sv.x_extent,
                "y_extent": sv.y_extent,
            }
        except Exception:
            pass

        return Response({
            "room_id": str(room.id),
            "room_name": room.name,
            "building": room.building,
            "floor_number": room.floor_number,
            "has_polygon": room.has_polygon,
            "corners": corners_data,
            "polygon": polygon_coords,
            "normalized_coordinates": room.normalized_coordinates or [],
            "orientation_matrix": room.orientation_matrix,
            "dimensions": {
                "length": room.length,
                "width": room.width,
                "height": (room.room_dimensions or {}).get("height"),
            },
            "area": room.area,
            "altitude_range": {
                "min": room.min_altitude,
                "max": room.max_altitude,
                "tolerance": room.altitude_tolerance,
            },
            "magnetic_heading": room.magnetic_heading,
            "spatial_vectors": spatial_data,
            "center": {
                "lat": room.center_lat,
                "lng": room.center_lng,
            },
        })