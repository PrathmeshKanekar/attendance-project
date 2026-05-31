from rest_framework.permissions import BasePermission


class IsSuperAdmin(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'super_admin'
        )

    def has_object_permission(self, request, view, obj):
        return True


class IsCollegeAdmin(BasePermission):
    """
    College Admin can handle ONLY: new users add, academic year master, departments, courses.
    They should NOT access: approvals, attendance, virtual rooms, etc.
    """
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'college_admin'
        )

    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)


class IsPrincipalOnly(BasePermission):
    """ONLY Principal can approve teachers, lab assistants, HODs, other staff."""
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'principal'
        )


class IsLabAssistantOnly(BasePermission):
    """ONLY Lab Assistant can manage virtual rooms (create, edit, delete)."""
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'lab_assistant'
        )


class IsSameCollege(BasePermission):
    def has_object_permission(self, request, view, obj):
        if not request.user.is_authenticated:
            return False
        if request.user.role == 'super_admin':
            return True
        # Assuming obj has a college field or IS a college
        obj_college = obj if hasattr(obj, 'timezone') else getattr(obj, 'college', None)
        return obj_college == request.user.college


class IsCollegeActiveAndSubscribed(BasePermission):
    def has_permission(self, request, view):
        if not request.user.is_authenticated or not request.user.college:
            return False
        college = request.user.college
        return college.is_active and not college.is_suspended


class IsPrincipal(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'principal'
        )

    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)


class IsHOD(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'hod'
        )

    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)


class IsTeacher(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'teacher'
        )

    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)


class IsStudent(BasePermission):
    def has_permission(self, request, view):
        if not request.user.is_authenticated or request.user.role != 'student':
            return False
        try:
            return request.user.student_profile.approval_status == 'APPROVED'
        except AttributeError:
            return False

    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)


class IsLabAssistant(BasePermission):
    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role == 'lab_assistant'
        )

    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)


class IsCollegeScopedStaff(BasePermission):
    """
    Allows: principal, hod, lab_assistant, teacher.
    College Admin is excluded as they only handle Departments/Courses now.
    """
    ALLOWED_ROLES = [
        'principal', 'hod', 'lab_assistant', 'teacher'
    ]

    def has_permission(self, request, view):
        return (
            request.user.is_authenticated
            and request.user.role in self.ALLOWED_ROLES
        )

    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)


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
