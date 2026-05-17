from rest_framework import permissions


class IsCollegeAdminOrStaff(permissions.BasePermission):
    """
    Allow access to:
    - super_admin (all rooms)
    - college_admin (own college rooms)
    - lab_assistant (own college rooms — can create/capture)
    - teacher (read-only for own college)
    - principal (read-only for own college)
    - hod (read-only for own college)

    Write operations restricted to: super_admin, college_admin, lab_assistant
    """
    WRITE_ROLES = {'super_admin', 'college_admin', 'lab_assistant'}
    READ_ROLES = {'super_admin', 'college_admin', 'lab_assistant', 'teacher', 'principal', 'hod', 'staff'}

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False

        role = getattr(request.user, 'role', '')

        if request.method in permissions.SAFE_METHODS:
            return role in self.READ_ROLES
        return role in self.WRITE_ROLES
