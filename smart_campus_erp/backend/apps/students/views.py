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
    queryset = StudentProfile.objects.select_related('user', 'college', 'division', 'course', 'academic_year')
    serializer_class = StudentProfileSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        qs = self.queryset
        if not user.is_authenticated:
            return qs.none()
        if user.role == 'lab_assistant':
            from apps.accounts.rbac import filter_by_assigned_department
            qs = filter_by_assigned_department(user, qs, 'course__department')
        elif user.role in ['college_admin', 'principal', 'hod', 'teacher']:
            qs = qs.filter(college=user.college)
        return qs

class StudentSubjectEnrollmentViewSet(viewsets.ModelViewSet):
    queryset = StudentSubjectEnrollment.objects.select_related(
        'student',
        'student__user',
        'subject_allocation',
        'subject_allocation__subject',
        'subject_allocation__division',
        'subject_allocation__teacher',
        'academic_year'
    )
    serializer_class = StudentSubjectEnrollmentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        qs = self.queryset
        if not user.is_authenticated:
            return qs.none()
        if user.role == 'lab_assistant':
            from apps.accounts.rbac import filter_by_assigned_department
            qs = filter_by_assigned_department(user, qs, 'student__course__department')
        elif user.role in ['college_admin', 'principal', 'hod', 'teacher']:
            qs = qs.filter(student__college=user.college)
        return qs

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
        
        # Apply department level RBAC
        from apps.accounts.rbac import filter_by_assigned_department
        pending_students = filter_by_assigned_department(request.user, pending_students, 'course__department')
        
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
        
        # Security check: Lab Assistant can only approve students in assigned departments
        if request.user.role == 'lab_assistant':
            from apps.accounts.rbac import get_lab_assistant_departments
            assigned_depts = get_lab_assistant_departments(request.user)
            if student_profile.course.department not in assigned_depts:
                return Response({"error": "You do not have permission to manage students in this department."}, status=status.HTTP_403_FORBIDDEN)
        
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

        # In-App Notification Hook
        from apps.notifications.models import Notification
        Notification.objects.create(
            college=student_profile.college,
            recipient=user,
            sender=request.user,
            title="Registration Approved 🎉",
            message=f"Welcome to Smart Campus ERP! Your student account for PRN {student_profile.prn} has been verified and approved.",
            notif_type="approval"
        )
        
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
        
        # Security check: Lab Assistant can only reject students in assigned departments
        if request.user.role == 'lab_assistant':
            from apps.accounts.rbac import get_lab_assistant_departments
            assigned_depts = get_lab_assistant_departments(request.user)
            if student_profile.course.department not in assigned_depts:
                return Response({"error": "You do not have permission to manage students in this department."}, status=status.HTTP_403_FORBIDDEN)
        
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

        # In-App Notification Hook
        from apps.notifications.models import Notification
        Notification.objects.create(
            college=student_profile.college,
            recipient=user,
            sender=request.user,
            title="Registration Rejected ⚠️",
            message=f"Your registration was rejected. Reason: {rejection_reason}",
            notif_type="approval"
        )
        
        return Response({
            "success": True,
            "message": f"Student {user.get_full_name()} rejected."
        }, status=status.HTTP_200_OK)


class LabAssistantBlockStudentView(APIView):
    """
    Block student registration and disable login access.
    """
    permission_classes = [IsAuthenticated, IsLabAssistant]

    @transaction.atomic
    def post(self, request, student_id):
        college = request.user.college
        if not college:
            return Response({"error": "Lab Assistant is not assigned to any college."}, status=status.HTTP_400_BAD_REQUEST)
            
        student_profile = get_object_or_404(StudentProfile, id=student_id, college=college)
        
        # Security check: Lab Assistant can only block students in assigned departments
        if request.user.role == 'lab_assistant':
            from apps.accounts.rbac import get_lab_assistant_departments
            assigned_depts = get_lab_assistant_departments(request.user)
            if student_profile.course.department not in assigned_depts:
                return Response({"error": "You do not have permission to manage students in this department."}, status=status.HTTP_403_FORBIDDEN)
        
        # Update Student Profile
        student_profile.approval_status = 'BLOCKED'
        student_profile.is_active = False
        student_profile.save(update_fields=['approval_status', 'is_active'])
        
        # Update User
        user = student_profile.user
        user.is_approved = False
        user.is_active = False
        user.save(update_fields=['is_approved', 'is_active'])

        # In-App Notification Hook
        from apps.notifications.models import Notification
        Notification.objects.create(
            college=student_profile.college,
            recipient=user,
            sender=request.user,
            title="Account Blocked ⛔",
            message="Your student profile has been blocked due to compliance or identity verification failure.",
            notif_type="approval"
        )
        
        return Response({
            "success": True,
            "message": f"Student {user.get_full_name()} blocked successfully."
        }, status=status.HTTP_200_OK)


class StudentDuplicateCheckView(APIView):
    """
    Public API view to check if an email, PRN, or enrollment number is already registered.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        from django.contrib.auth import get_user_model
        User = get_user_model()
        
        email = request.query_params.get('email', '').strip().lower()
        prn = request.query_params.get('prn', '').strip().upper()
        enrollment_number = request.query_params.get('enrollment_number', '').strip().upper()

        response_data = {
            'email_exists': False,
            'prn_exists': False,
            'enrollment_number_exists': False
        }

        if email and User.objects.filter(email=email).exists():
            response_data['email_exists'] = True

        if prn and StudentProfile.objects.filter(prn=prn).exists():
            response_data['prn_exists'] = True

        if enrollment_number and StudentProfile.objects.filter(enrollment_number=enrollment_number).exists():
            response_data['enrollment_number_exists'] = True

        return Response(response_data, status=status.HTTP_200_OK)
