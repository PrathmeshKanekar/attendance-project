from rest_framework import permissions

class IsCollegeAdminOrStaff(permissions.BasePermission):
    """
    Role Restriction:
    - ONLY users with role: lab_assistant can create, edit, or delete virtual rooms.
    - Teachers, Principals, College Admins, Students MUST NOT create or modify virtual rooms.
    - Safe methods (GET, HEAD, OPTIONS) are available to authorized academic roles.
    """
    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
            
        role = getattr(request.user, 'role', '')
        
        # Read requests are allowed for all academic staff/students to marked attendance correctly
        if request.method in permissions.SAFE_METHODS:
            return role in {'lab_assistant', 'super_admin', 'college_admin', 'teacher', 'principal', 'hod', 'student'}
            
        # Write operations are strictly restricted to lab_assistant only
        return role == 'lab_assistant'
