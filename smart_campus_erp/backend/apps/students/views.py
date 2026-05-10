from rest_framework import viewsets, status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from .models import StudentProfile, StudentSubjectEnrollment
from .serializers import (
    StudentProfileSerializer, 
    StudentSubjectEnrollmentSerializer,
    StudentRegistrationSerializer
)
from apps.accounts.permissions import IsCollegeScopedStaff, IsSuperAdmin
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
            # Students are auto-approved as per requirement
            student_profile = serializer.save()
            user = student_profile.user
            user.is_approved = True
            user.is_active   = True
            user.save(update_fields=['is_approved', 'is_active'])
            
            return Response({
                "success": True,
                "message": "Registration successful. Your account is now active."
            }, status=status.HTTP_201_CREATED)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
