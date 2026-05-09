import logging
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from apps.accounts.permissions import IsCollegeScopedStaff, IsSuperAdmin
from apps.students.models import StudentProfile
from .models import FaceDescriptor, FaceRegistrationImage
from .serializers import (
    FaceDescriptorSerializer,
    FaceRegisterInputSerializer,
    FaceVerifyInputSerializer,
)
from .face_utils import generate_embedding, verify_face

logger = logging.getLogger(__name__)


# ══════════════════════════════════════════════════════════
# POST /api/face/register/
# ══════════════════════════════════════════════════════════

class FaceRegisterView(APIView):
    """
    Register a student's face by generating an embedding from a photo.
    Only Lab Assistants and College Admins can call this.
    """
    permission_classes = [IsCollegeScopedStaff | IsSuperAdmin]

    def post(self, request):
        ser = FaceRegisterInputSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)

        student_id    = ser.validated_data['student_id']
        face_image_b64 = ser.validated_data['face_image_b64']

        # ── Get student profile ────────────────────────────
        try:
            profile = StudentProfile.objects.select_related(
                'user', 'college'
            ).get(id=student_id, is_active=True)
        except StudentProfile.DoesNotExist:
            return Response(
                {'error': 'Student not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        # ── College scope check ────────────────────────────
        if (request.user.role != 'super_admin'
                and profile.college != request.user.college):
            return Response(
                {'error': 'You can only register faces for students in your college.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        # ── Generate embedding ─────────────────────────────
        try:
            embedding = generate_embedding(face_image_b64)
        except ValueError as exc:
            return Response(
                {'error': str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        except Exception as exc:
            logger.error('Face embedding error: %s', exc)
            return Response(
                {'error': 'Face processing failed. Please try again.'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        # ── Save or update descriptor ──────────────────────
        descriptor, created = FaceDescriptor.objects.update_or_create(
            student=profile,
            defaults={
                'embedding'    : embedding,
                'model_used'   : 'DeepFace-Facenet',
                'registered_by': request.user,
            },
        )

        # ── Update student face_registered flag ────────────
        StudentProfile.objects.filter(id=student_id).update(
            face_registered=True
        )

        action = 'registered' if created else 're-registered'
        return Response(
            {
                'success'   : True,
                'message'   : f'Face {action} successfully for {profile.user.get_full_name()}.',
                'descriptor': FaceDescriptorSerializer(descriptor).data,
            },
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


# ══════════════════════════════════════════════════════════
# POST /api/face/verify/
# ══════════════════════════════════════════════════════════

class FaceVerifyView(APIView):
    """
    Verify a live image against a stored embedding.
    Called during attendance marking.
    Any authenticated user can call this.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        ser = FaceVerifyInputSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)

        face_image_b64 = ser.validated_data['face_image_b64']

        # ── Resolve student ────────────────────────────────
        student_id = ser.validated_data.get('student_id')

        if student_id:
            try:
                profile = StudentProfile.objects.get(
                    id=student_id, is_active=True
                )
            except StudentProfile.DoesNotExist:
                return Response(
                    {'error': 'Student not found.'},
                    status=status.HTTP_404_NOT_FOUND,
                )
        else:
            # Use the logged-in student's own profile
            try:
                profile = request.user.student_profile
            except StudentProfile.DoesNotExist:
                return Response(
                    {'error': 'No student profile found for this user.'},
                    status=status.HTTP_404_NOT_FOUND,
                )

        # ── Load stored embedding ──────────────────────────
        try:
            descriptor = FaceDescriptor.objects.get(student=profile)
        except FaceDescriptor.DoesNotExist:
            return Response(
                {
                    'match'  : False,
                    'error'  : (
                        'Face not registered for this student. '
                        'Please contact your lab assistant.'
                    ),
                },
                status=status.HTTP_404_NOT_FOUND,
            )

        # ── Verify ─────────────────────────────────────────
        result = verify_face(face_image_b64, descriptor.embedding)
        return Response(result, status=status.HTTP_200_OK)


# ══════════════════════════════════════════════════════════
# GET /api/face/status/<student_id>/
# ══════════════════════════════════════════════════════════

class FaceStatusView(APIView):
    """
    Returns the face registration status of a student.
    Used by admin/lab-assistant to show registered / not registered badge.
    """
    permission_classes = [IsCollegeScopedStaff | IsSuperAdmin]

    def get(self, request, student_id):
        try:
            profile = StudentProfile.objects.select_related('user').get(
                id=student_id, is_active=True
            )
        except StudentProfile.DoesNotExist:
            return Response({'error': 'Student not found.'}, status=404)

        if (request.user.role != 'super_admin'
                and profile.college != request.user.college):
            return Response({'error': 'Forbidden.'}, status=403)

        try:
            descriptor = FaceDescriptor.objects.get(student=profile)
            return Response({
                'student_id'     : str(profile.id),
                'student_name'   : profile.user.get_full_name(),
                'prn'            : profile.prn,
                'face_registered': True,
                'registered_at'  : descriptor.registered_at.isoformat(),
                'registered_by'  : descriptor.registered_by.get_full_name()
                                   if descriptor.registered_by else None,
                'model_used'     : descriptor.model_used,
            })
        except FaceDescriptor.DoesNotExist:
            return Response({
                'student_id'     : str(profile.id),
                'student_name'   : profile.user.get_full_name(),
                'prn'            : profile.prn,
                'face_registered': False,
                'registered_at'  : None,
                'registered_by'  : None,
                'model_used'     : None,
            })


# ══════════════════════════════════════════════════════════
# DELETE /api/face/<student_id>/
# ══════════════════════════════════════════════════════════

class FaceDeleteView(APIView):
    """Remove a student's face registration."""
    permission_classes = [IsCollegeScopedStaff | IsSuperAdmin]

    def delete(self, request, student_id):
        try:
            profile = StudentProfile.objects.get(
                id=student_id, is_active=True
            )
        except StudentProfile.DoesNotExist:
            return Response({'error': 'Student not found.'}, status=404)

        if (request.user.role != 'super_admin'
                and profile.college != request.user.college):
            return Response({'error': 'Forbidden.'}, status=403)

        deleted, _ = FaceDescriptor.objects.filter(student=profile).delete()
        if deleted:
            StudentProfile.objects.filter(id=student_id).update(
                face_registered=False
            )
            return Response({
                'success': True,
                'message': f'Face registration removed for '
                           f'{profile.user.get_full_name()}.',
            })
        return Response(
            {'error': 'No face registration found for this student.'},
            status=404,
        )


# ══════════════════════════════════════════════════════════
# GET /api/face/list/
# ══════════════════════════════════════════════════════════

class FaceRegistrationListView(APIView):
    """
    List all students with their face registration status.
    Returns both registered and unregistered students.
    """
    permission_classes = [IsCollegeScopedStaff | IsSuperAdmin]

    def get(self, request):
        qs = StudentProfile.objects.select_related(
            'user', 'college', 'division', 'face_descriptor'
        ).filter(is_active=True)

        if request.user.role != 'super_admin':
            qs = qs.filter(college=request.user.college)

        # Filters
        registered = request.query_params.get('registered')
        division   = request.query_params.get('division')
        search     = request.query_params.get('search', '')

        if registered is not None:
            qs = qs.filter(face_registered=registered.lower() == 'true')
        if division:
            qs = qs.filter(division_id=division)
        if search:
            from django.db.models import Q
            qs = qs.filter(
                Q(prn__icontains=search)
                | Q(user__first_name__icontains=search)
                | Q(user__last_name__icontains=search)
            )

        qs = qs.order_by('user__first_name')

        data = []
        for profile in qs:
            descriptor = None
            try:
                descriptor = profile.face_descriptor
            except FaceDescriptor.DoesNotExist:
                pass

            data.append({
                'student_id'    : str(profile.id),
                'name'          : profile.user.get_full_name(),
                'email'         : profile.user.email,
                'prn'           : profile.prn,
                'roll_number'   : profile.roll_number,
                'year_of_study' : profile.year_of_study,
                'division_name' : profile.division.name if profile.division else None,
                'face_registered': profile.face_registered,
                'registered_at' : descriptor.registered_at.isoformat()
                                  if descriptor else None,
                'registered_by' : descriptor.registered_by.get_full_name()
                                  if descriptor and descriptor.registered_by else None,
            })

        total       = len(data)
        registered_count = sum(1 for d in data if d['face_registered'])

        return Response({
            'students'        : data,
            'total'           : total,
            'registered_count': registered_count,
            'pending_count'   : total - registered_count,
        })
