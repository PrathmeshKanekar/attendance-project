from rest_framework import viewsets, status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from django.db import transaction
from django.utils import timezone
from django.shortcuts import get_object_or_404
from .models import StudentProfile, StudentSubjectEnrollment
from .serializers import (
    StudentProfileSerializer, 
    StudentSubjectEnrollmentSerializer,
    StudentRegistrationSerializer,
    LabAssistantPendingStudentSerializer
)
from apps.accounts.permissions import IsCollegeScopedStaff, IsSuperAdmin, IsLabAssistant
from apps.face_recognition.face_utils import generate_embedding
from apps.face_recognition.models import FaceDescriptor

class StudentProfileViewSet(viewsets.ModelViewSet):
    queryset = StudentProfile.objects.all()
    serializer_class = StudentProfileSerializer
    permission_classes = [IsAuthenticated]

class StudentSubjectEnrollmentViewSet(viewsets.ModelViewSet):
    queryset = StudentSubjectEnrollment.objects.all()
    serializer_class = StudentSubjectEnrollmentSerializer
    permission_classes = [IsAuthenticated]

class StudentRegistrationView(APIView):
    """
    Public endpoint for students to register their details and face data.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = StudentRegistrationSerializer(data=request.data)
        if serializer.is_valid():
            student_profile = serializer.save()
            user = student_profile.user
            user.is_approved = False  # Requires Lab Assistant approval
            user.is_active   = True   # Allowed to exist, but not log in/access attendance until approved
            user.save(update_fields=['is_approved', 'is_active'])
            
            student_profile.approval_status = 'PENDING_APPROVAL'
            student_profile.save(update_fields=['approval_status'])
            
            return Response({
                "success": True,
                "message": "Registration submitted successfully. Waiting for Lab Assistant approval."
            }, status=status.HTTP_201_CREATED)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class LabAssistantPendingStudentsView(APIView):
    """
    Returns pending students belonging to the same college as the logged-in Lab Assistant.
    """
    permission_classes = [IsAuthenticated, IsLabAssistant]

    def get(self, request):
        college = request.user.college
        if not college:
            return Response({"error": "Lab Assistant is not assigned to any college."}, status=status.HTTP_400_BAD_REQUEST)
        
        # Get pending students for same college
        pending_students = StudentProfile.objects.filter(
            college=college,
            approval_status='PENDING_APPROVAL'
        ).select_related('user', 'college', 'course', 'division')
        
        serializer = LabAssistantPendingStudentSerializer(pending_students, many=True, context={'request': request})
        return Response(serializer.data, status=status.HTTP_200_OK)


class LabAssistantApproveStudentView(APIView):
    """
    Approve student registration and activate their login/attendance access.
    """
    permission_classes = [IsAuthenticated, IsLabAssistant]

    @transaction.atomic
    def post(self, request, student_id):
        college = request.user.college
        if not college:
            return Response({"error": "Lab Assistant is not assigned to any college."}, status=status.HTTP_400_BAD_REQUEST)
            
        student_profile = get_object_or_404(StudentProfile, id=student_id, college=college)
        
        if student_profile.approval_status == 'APPROVED':
            return Response({"error": "Student is already approved."}, status=status.HTTP_400_BAD_REQUEST)
            
        # Update Student Profile
        student_profile.approval_status = 'APPROVED'
        student_profile.approved_by = request.user
        student_profile.approved_at = timezone.now()
        student_profile.is_active = True
        student_profile.save(update_fields=['approval_status', 'approved_by', 'approved_at', 'is_active'])
        
        # Update User
        user = student_profile.user
        user.is_approved = True
        user.is_active = True
        user.save(update_fields=['is_approved', 'is_active'])
        
        return Response({
            "success": True,
            "message": f"Student {user.get_full_name()} approved successfully."
        }, status=status.HTTP_200_OK)


class LabAssistantRejectStudentView(APIView):
    """
    Reject student registration and deactivate their login.
    """
    permission_classes = [IsAuthenticated, IsLabAssistant]

    @transaction.atomic
    def post(self, request, student_id):
        college = request.user.college
        if not college:
            return Response({"error": "Lab Assistant is not assigned to any college."}, status=status.HTTP_400_BAD_REQUEST)
            
        student_profile = get_object_or_404(StudentProfile, id=student_id, college=college)
        
        if student_profile.approval_status == 'REJECTED':
            return Response({"error": "Student is already rejected."}, status=status.HTTP_400_BAD_REQUEST)
            
        rejection_reason = request.data.get('rejection_reason', '').strip()
        
        # Update Student Profile
        student_profile.approval_status = 'REJECTED'
        student_profile.rejection_reason = rejection_reason
        student_profile.is_active = False
        student_profile.save(update_fields=['approval_status', 'rejection_reason', 'is_active'])
        
        # Update User
        user = student_profile.user
        user.is_approved = False
        user.is_active = False
        user.save(update_fields=['is_approved', 'is_active'])
        
        return Response({
            "success": True,
            "message": f"Student {user.get_full_name()} rejected."
        }, status=status.HTTP_200_OK)
