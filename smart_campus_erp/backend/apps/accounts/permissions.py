from rest_framework.permissions import BasePermission


class IsSuperAdmin(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'super_admin'
        )


class IsCollegeAdmin(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'college_admin'
        )


class IsPrincipal(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'principal'
        )


class IsHOD(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'hod'
        )


class IsTeacher(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'teacher'
        )


class IsStudent(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'student'
        )


class IsLabAssistant(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'lab_assistant'
        )


class IsCollegeScopedStaff(BasePermission):
    """
    Allows: college_admin, principal, hod, lab_assistant.
    All scoped to their own college.
    """
    ALLOWED_ROLES = [
        'college_admin', 'principal', 'hod', 'lab_assistant',
    ]

    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role in self.ALLOWED_ROLES
        )


class IsTeacherOrAbove(BasePermission):
    """Teacher, HOD, Principal, CollegeAdmin, SuperAdmin."""
    ALLOWED_ROLES = [
        'teacher', 'hod', 'principal',
        'college_admin', 'super_admin', 'lab_assistant',
    ]

    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role in self.ALLOWED_ROLES
        )


class IsCollegeScopedAdmin(BasePermission):
    ALLOWED_ROLES = [
        'college_admin', 'principal', 'hod', 'lab_assistant',
    ]

    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role in self.ALLOWED_ROLES
        )


class CollegeScopedMixin:
    """
    Add to any APIView / ViewSet.
    Automatically filters queryset to request.user.college.
    Super Admin sees everything.
    """
    def get_college_queryset(self, qs):
        user = self.request.user
        if user.role == 'super_admin':
            return qs
        if hasattr(qs.model, 'college_id'):
            return qs.filter(college=user.college)
        return qs
