from django.contrib.auth import get_user_model
from django.utils import timezone
from django.db import models
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError

from apps.students.models import StudentProfile
from apps.approvals.models import ApprovalRequest
from apps.notifications.models import Notification
from apps.accounts.models import DeviceRegistry
from .serializers import (
    UserProfileSerializer,
    CreateUserSerializer,
    PendingUserSerializer,
)
from .permissions import (
    IsCollegeScopedStaff, IsSuperAdmin,
    IsPrincipal, IsCollegeAdmin, IsPrincipalOnly,
)

User = get_user_model()


def build_auth_response(user):
    """
    Build the standard auth response dict.
    Generates fresh JWT tokens for the given user.
    Returns dict with access, refresh, and full user payload.
    """
    refresh = RefreshToken.for_user(user)
    user_data = UserProfileSerializer(user).data
    return {
        'access': str(refresh.access_token),
        'refresh': str(refresh),
        'user': user_data,
    }


# ─────────────────────────────────────────────
# POST /api/auth/login/email/
# ─────────────────────────────────────────────
class EmailLoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        email    = request.data.get('email', '').strip().lower()
        password = request.data.get('password', '')

        if not email or not password:
            return Response(
                {'error': 'Email and password are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            user = User.objects.select_related('college', 'student_profile').get(email=email)
        except User.DoesNotExist:
            return Response(
                {'error': 'No account found with this email address.'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        if not user.check_password(password):
            return Response(
                {'error': 'Incorrect password.'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        if user.role == 'student':
            try:
                profile = user.student_profile
                if profile.approval_status == 'PENDING_APPROVAL':
                    return Response(
                        {'error': 'Your account is pending approval. Please contact your Lab Assistant.'},
                        status=status.HTTP_403_FORBIDDEN,
                    )
                elif profile.approval_status == 'REJECTED':
                    reason = profile.rejection_reason or 'No reason provided.'
                    return Response(
                        {'error': f'Your account has been rejected. Reason: {reason}'},
                        status=status.HTTP_403_FORBIDDEN,
                    )
            except AttributeError:
                pass
        elif not user.is_approved:
            return Response(
                {
                    'error': (
                        'Your account is pending approval. '
                        'Please contact your college Principal.'
                    )
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        if not user.is_active:
            return Response(
                {'error': 'Your account has been deactivated. Contact admin.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        if user.college is None and user.role != 'super_admin':
            return Response(
                {
                    'error': (
                        'Your account is not linked to any college. '
                        'Contact your administrator.'
                    )
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        # Update last login
        user.last_login_at = timezone.now()
        user.save(update_fields=['last_login_at'])

        return Response(build_auth_response(user), status=status.HTTP_200_OK)


# ─────────────────────────────────────────────
# POST /api/auth/login/prn/
# ─────────────────────────────────────────────
class PRNLoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        prn      = request.data.get('prn', '').strip().upper()
        password = request.data.get('password', '')

        if not prn or not password:
            return Response(
                {'error': 'PRN and password are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            profile = StudentProfile.objects.select_related(
                'user', 'user__college', 'division', 'course'
            ).get(prn=prn)
        except StudentProfile.DoesNotExist:
            return Response(
                {'error': 'No student found with this PRN number.'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        user = profile.user

        if not user.check_password(password):
            return Response(
                {'error': 'Incorrect password.'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        if profile.approval_status == 'PENDING_APPROVAL':
            return Response(
                {'error': 'Your account is pending approval. Please contact your Lab Assistant.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        elif profile.approval_status == 'REJECTED':
            reason = profile.rejection_reason or 'No reason provided.'
            return Response(
                {'error': f'Your account has been rejected. Reason: {reason}'},
                status=status.HTTP_403_FORBIDDEN,
            )

        if not user.is_active:
            return Response(
                {'error': 'Your account has been deactivated.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        user.last_login_at = timezone.now()
        user.save(update_fields=['last_login_at'])

        return Response(build_auth_response(user), status=status.HTTP_200_OK)


# ─────────────────────────────────────────────
# GET /api/auth/me/
# ─────────────────────────────────────────────
class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = User.objects.select_related('college').get(pk=request.user.pk)
        return Response(
            {'user': UserProfileSerializer(user).data},
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────
# POST /api/auth/logout/
# ─────────────────────────────────────────────
class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        refresh_token = request.data.get('refresh')
        if not refresh_token:
            return Response(
                {'error': 'Refresh token is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            token = RefreshToken(refresh_token)
            token.blacklist()
        except TokenError:
            pass
        return Response(
            {'success': True, 'message': 'Logged out successfully.'},
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────
# POST /api/auth/register-device/
# ─────────────────────────────────────────────
class RegisterDeviceView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        device_id   = request.data.get('device_id', '').strip()
        device_name = request.data.get('device_name', '').strip()
        platform    = request.data.get('platform', 'android').strip()

        if not device_id:
            return Response(
                {'error': 'device_id is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        DeviceRegistry.objects.update_or_create(
            user=request.user,
            device_id=device_id,
            defaults={
                'device_name': device_name,
                'platform': platform,
                'is_active': True,
            },
        )

        request.user.device_id = device_id
        request.user.save(update_fields=['device_id'])

        return Response(
            {'success': True, 'message': 'Device registered successfully.'},
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────
# POST /api/users/   — Create user
# ─────────────────────────────────────────────
class CreateUserView(APIView):
    permission_classes = [IsCollegeScopedStaff | IsCollegeAdmin | IsSuperAdmin]

    def post(self, request):
        serializer = CreateUserSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        data   = serializer.validated_data
        role   = data['role']
        college = (
            request.user.college
            if request.user.role != 'super_admin'
            else None
        )

        # Requirements: Principal, College Admin and Student become active immediately.
        # Others (teacher, staff, hod) stay pending and require Principal approval.
        is_active = False
        is_approved = False

        if role in ['principal', 'college_admin', 'super_admin', 'student']:
            is_active = True
            is_approved = True

        if college is None and role != 'super_admin':
            return Response(
                {'error': 'College is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user = User.objects.create_user(
            email      = data['email'],
            password   = data['password'],
            first_name = data['first_name'],
            last_name  = data['last_name'],
            phone      = data.get('phone', ''),
            role       = role,
            college    = college,
            is_active  = is_active,
            is_approved = is_approved,
        )

        if role == 'student':
            from apps.academic.models import Division, AcademicYear

            prn           = data.get('prn', '')
            roll_number   = data.get('roll_number', '')
            year_of_study = data.get('year_of_study', 1)
            division_id   = data.get('division_id')

            if not prn:
                user.delete()
                return Response(
                    {'error': 'PRN is required for student accounts.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            try:
                division = Division.objects.get(id=division_id, college=college)
            except Division.DoesNotExist:
                user.delete()
                return Response(
                    {'error': 'Invalid division ID.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            academic_year = AcademicYear.objects.filter(
                college=college, is_current=True
            ).first()

            StudentProfile.objects.create(
                user          = user,
                college       = college,
                division      = division,
                course        = division.course,
                academic_year = academic_year,
                prn           = prn.strip().upper(),
                roll_number   = roll_number,
                year_of_study = year_of_study,
            )

        # Create approval request only for roles that need it (Teacher and Staff)
        ROLES_NEEDING_APPROVAL = ['teacher', 'staff', 'hod', 'lab_assistant']
        if college and role in ROLES_NEEDING_APPROVAL:
            ApprovalRequest.objects.create(
                college        = college,
                user           = user,
                requested_role = role,
                status         = 'pending',
            )

            # Notifications for Principal
            principals_qs = User.objects.filter(
                college=college,
                role='principal',
                is_active=True,
                is_approved=True,
            )
            for principal in principals_qs:
                Notification.objects.create(
                    college    = college,
                    recipient  = principal,
                    sender     = request.user,
                    title      = 'New User Awaiting Approval',
                    message    = (
                        f'{user.first_name} {user.last_name} has registered '
                        f'as {role.replace("_", " ").title()} and needs your approval.'
                    ),
                    notif_type = 'approval',
                )

        msg = 'User created successfully.'
        if not is_approved:
            msg += ' Awaiting approval from college Principal.'
        else:
            msg += ' Account is active and ready to login.'

        return Response(
            {
                'success': True,
                'message': msg,
                'user_id': str(user.id),
            },
            status=status.HTTP_201_CREATED,
        )


# ─────────────────────────────────────────────
# GET /api/users/  — List users
# ─────────────────────────────────────────────
class ListUsersView(APIView):
    permission_classes = [IsCollegeScopedStaff | IsCollegeAdmin | IsSuperAdmin]

    def get(self, request):
        user = request.user

        if user.role == 'super_admin':
            qs = User.objects.select_related('college').all()
        else:
            qs = User.objects.select_related('college').filter(
                college=user.college
            )

        role       = request.query_params.get('role')
        is_approved = request.query_params.get('is_approved')
        is_active  = request.query_params.get('is_active')
        search     = request.query_params.get('search')

        if role:
            qs = qs.filter(role=role)
        if is_approved is not None and is_approved != '':
            qs = qs.filter(is_approved=is_approved.lower() == 'true')
        if is_active is not None and is_active != '':
            qs = qs.filter(is_active=is_active.lower() == 'true')
        if search:
            qs = qs.filter(
                models.Q(first_name__icontains=search)
                | models.Q(last_name__icontains=search)
                | models.Q(email__icontains=search)
            )

        qs = qs.order_by('-created_at')
        serializer = PendingUserSerializer(qs, many=True)
        return Response({'users': serializer.data, 'count': qs.count()})


# ─────────────────────────────────────────────
# POST /api/users/<id>/approve/
# ─────────────────────────────────────────────
class ApproveUserView(APIView):
    # ONLY Principal can approve
    permission_classes = [IsPrincipalOnly]

    def post(self, request, user_id):
        try:
            # Filter by college to ensure security
            target = User.objects.select_related('college').get(
                id      = user_id,
                college = request.user.college
            )
        except User.DoesNotExist:
            return Response(
                {'error': 'User not found in your college.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        target.is_approved = True
        target.is_active   = True
        target.approved_by = request.user
        target.approved_at = timezone.now()
        target.save(update_fields=[
            'is_approved', 'is_active', 'approved_by', 'approved_at'
        ])

        ApprovalRequest.objects.filter(
            user=target, status='pending'
        ).update(
            status      = 'approved',
            reviewed_by = request.user,
            reviewed_at = timezone.now(),
        )

        Notification.objects.create(
            college    = target.college,
            recipient  = target,
            sender     = request.user,
            title      = 'Account Approved',
            message    = (
                f'Your account as '
                f'{target.role.replace("_", " ").title()} '
                f'has been approved. You can now log in.'
            ),
            notif_type = 'approval',
        )

        return Response(
            {
                'success': True,
                'message': f'{target.get_full_name()} approved successfully.',
            },
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────
# POST /api/users/<id>/reject/
# ─────────────────────────────────────────────
class RejectUserView(APIView):
    # ONLY Principal can reject
    permission_classes = [IsPrincipalOnly]

    def post(self, request, user_id):
        reason = request.data.get('reason', '').strip()
        if not reason:
            return Response(
                {'error': 'A reason for rejection is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            # Filter by college to ensure security
            target = User.objects.get(
                id      = user_id,
                college = request.user.college
            )
        except User.DoesNotExist:
            return Response(
                {'error': 'User not found in your college.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        target.is_approved = False
        target.is_active   = False
        target.save(update_fields=['is_approved', 'is_active'])

        ApprovalRequest.objects.filter(
            user=target, status='pending'
        ).update(
            status           = 'rejected',
            reviewed_by      = request.user,
            reviewed_at      = timezone.now(),
            rejection_reason = reason,
        )

        Notification.objects.create(
            college    = target.college,
            recipient  = target,
            sender     = request.user,
            title      = 'Account Rejected',
            message    = (
                f'Your account registration was rejected. '
                f'Reason: {reason}'
            ),
            notif_type = 'approval',
        )

        return Response(
            {'success': True, 'message': 'User rejected.'},
            status=status.HTTP_200_OK,
        )


# ══════════════════════════════════════════════════════════
# GET/PUT /api/auth/users/{id}/   — User detail + update
# ══════════════════════════════════════════════════════════

class UserDetailView(APIView):
    permission_classes = [IsCollegeScopedStaff | IsCollegeAdmin | IsSuperAdmin]

    def _get_user(self, request, user_id):
        try:
            target = User.objects.select_related(
                'college', 'approved_by',
            ).get(id=user_id)
        except User.DoesNotExist:
            return None
        if (request.user.role != 'super_admin'
                and target.college != request.user.college):
            return None
        return target

    def get(self, request, user_id):
        target = self._get_user(request, user_id)
        if not target:
            return Response({'error': 'User not found.'}, status=404)

        # Gather student profile if applicable
        student_data = None
        try:
            profile = target.student_profile
            student_data = {
                'prn'           : profile.prn,
                'roll_number'   : profile.roll_number,
                'year_of_study' : profile.year_of_study,
                'division_name' : profile.division.name
                                  if profile.division else None,
                'course_name'   : profile.course.name
                                  if profile.course else None,
                'face_registered': profile.face_registered,
            }
        except Exception:
            pass

        return Response({
            'id'           : str(target.id),
            'email'        : target.email,
            'first_name'   : target.first_name,
            'last_name'    : target.last_name,
            'full_name'    : target.get_full_name(),
            'role'         : target.role,
            'phone'        : target.phone,
            'profile_photo': target.profile_photo,
            'college_id'   : str(target.college.id) if target.college else None,
            'college_name' : target.college.name    if target.college else None,
            'is_active'    : target.is_active,
            'is_approved'  : target.is_approved,
            'approved_by'  : target.approved_by.get_full_name()
                             if target.approved_by else None,
            'approved_at'  : target.approved_at.isoformat()
                             if target.approved_at else None,
            'last_login_at': target.last_login_at.isoformat()
                             if target.last_login_at else None,
            'created_at'   : target.created_at.isoformat(),
            'device_id'    : target.device_id,
            'student'      : student_data,
        })

    def put(self, request, user_id):
        target = self._get_user(request, user_id)
        if not target:
            return Response({'error': 'User not found.'}, status=404)

        # Protection for Super Admin account
        if target.email == 'superadmin@app.com':
            return Response(
                {'error': 'The permanent Super Admin account cannot be modified.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        allowed_fields = ['first_name', 'last_name', 'phone', 'profile_photo']
        for field in allowed_fields:
            if field in request.data:
                setattr(target, field, request.data[field])

        target.save(update_fields=allowed_fields)
        return Response({
            'success' : True,
            'message' : 'User updated successfully.',
            'full_name': target.get_full_name(),
        })


# ══════════════════════════════════════════════════════════
# POST /api/auth/users/{id}/deactivate/
# ══════════════════════════════════════════════════════════

class DeactivateUserView(APIView):
    permission_classes = [IsCollegeScopedStaff | IsCollegeAdmin | IsSuperAdmin]

    def post(self, request, user_id):
        try:
            target = User.objects.get(id=user_id)
        except User.DoesNotExist:
            return Response({'error': 'User not found.'}, status=404)

        if (request.user.role != 'super_admin'
                and target.college != request.user.college):
            return Response({'error': 'Forbidden.'}, status=403)

        # Protection for Super Admin account
        if target.email == 'superadmin@app.com':
            return Response(
                {'error': 'The permanent Super Admin account cannot be deactivated.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        if target == request.user:
            return Response(
                {'error': 'You cannot deactivate your own account.'},
                status=400,
            )

        target.is_active = False
        target.save(update_fields=['is_active'])

        Notification.objects.create(
            college    = target.college,
            recipient  = target,
            sender     = request.user,
            title      = 'Account Deactivated',
            message    = (
                'Your account has been deactivated by an administrator. '
                'Please contact your college admin for assistance.'
            ),
            notif_type = 'system',
        )

        return Response({
            'success': True,
            'message': f'{target.get_full_name()} deactivated.',
        })


# ══════════════════════════════════════════════════════════
# GET /api/approvals/pending/
# ══════════════════════════════════════════════════════════

class PendingApprovalsView(APIView):
    """
    Returns all pending users for the approver's college.
    ONLY Principal can access.
    """
    permission_classes = [IsPrincipalOnly]

    def get(self, request):
        # ONLY: teacher, lab assistant, hod should require approval.
        # Students are managed separately, Principal is auto-approved.
        ROLES_NEEDING_APPROVAL = ['teacher', 'lab_assistant', 'hod', 'staff', 'other_staff']
        
        qs = User.objects.select_related('college').filter(
            is_approved = False,
            role__in    = ROLES_NEEDING_APPROVAL
        )
        
        # Always filter by college since only college_admin can access
        qs = qs.filter(college=request.user.college)

        role = request.query_params.get('role')
        if role:
            qs = qs.filter(role=role)

        qs = qs.order_by('created_at')

        data = [
            {
                'id'         : str(u.id),
                'full_name'  : u.get_full_name(),
                'email'      : u.email,
                'role'       : u.role,
                'phone'      : u.phone,
                'college_name': u.college.name if u.college else None,
                'created_at' : u.created_at.isoformat(),
                'days_waiting': (
                    timezone.now() - u.created_at
                ).days,
            }
            for u in qs
        ]

        return Response({
            'pending_users': data,
            'count'        : len(data),
        })


# ══════════════════════════════════════════════════════════
# Device Verification & Registration Views
# ══════════════════════════════════════════════════════════

class DeviceRegisterView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        from .models import normalize_device_id
        device_id   = request.data.get('device_id', '').strip()
        device_name = request.data.get('device_name', '').strip()
        platform    = request.data.get('platform', 'android').strip()

        if not device_id:
            return Response(
                {'error': 'device_id is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        normalized = normalize_device_id(device_id)

        # Deactivate any previous devices for this user
        DeviceRegistry.objects.filter(user=request.user).update(is_active=False)

        DeviceRegistry.objects.update_or_create(
            user=request.user,
            device_id=normalized,
            defaults={
                'device_name': device_name,
                'platform': platform,
                'is_active': True,
                'is_verified': True,
            },
        )

        request.user.device_id = normalized
        request.user.save(update_fields=['device_id'])

        return Response({
            'success': True,
            'message': 'Device registered successfully.',
            'device_id': normalized,
        }, status=status.HTTP_200_OK)


class DeviceVerifyView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from .models import normalize_device_id
        device_id = request.query_params.get('device_id', '').strip()
        if not device_id:
            return Response(
                {'error': 'device_id query parameter is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        normalized = normalize_device_id(device_id)
        device = DeviceRegistry.objects.filter(
            user=request.user,
            device_id=normalized,
            is_active=True
        ).first()

        if device:
            device.last_used_at = timezone.now()
            device.save(update_fields=['last_used_at'])
            return Response({
                'is_registered': True,
                'is_verified': device.is_verified,
                'device_id': normalized,
            })
        else:
            return Response({
                'is_registered': False,
                'is_verified': False,
                'device_id': normalized,
            })


class DeviceRefreshView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        from .models import normalize_device_id
        device_id   = request.data.get('device_id', '').strip()
        device_name = request.data.get('device_name', '').strip()
        platform    = request.data.get('platform', 'android').strip()

        if not device_id:
            return Response(
                {'error': 'device_id is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        normalized = normalize_device_id(device_id)

        # Deactivate any previous devices for this user
        DeviceRegistry.objects.filter(user=request.user).update(is_active=False)

        device, created = DeviceRegistry.objects.update_or_create(
            user=request.user,
            device_id=normalized,
            defaults={
                'device_name': device_name,
                'platform': platform,
                'is_active': True,
                'is_verified': True,
                'last_used_at': timezone.now(),
            },
        )

        request.user.device_id = normalized
        request.user.save(update_fields=['device_id'])

        return Response({
            'success': True,
            'message': 'Device binding refreshed successfully.',
            'device_id': normalized,
        })


