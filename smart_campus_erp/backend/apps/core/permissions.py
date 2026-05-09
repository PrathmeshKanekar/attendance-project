from rest_framework import permissions

class IsSuperAdmin(permissions.BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == 'super_admin'

class IsSameCollege(permissions.BasePermission):
    def has_object_permission(self, request, view, obj):
        if not request.user.is_authenticated:
            return False
        if request.user.role == 'super_admin':
            return True
        # Assuming obj has a college field or IS a college
        obj_college = obj if hasattr(obj, 'timezone') else getattr(obj, 'college', None)
        return obj_college == request.user.college

class IsCollegeAdmin(permissions.BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == 'college_admin'
    
    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)

class IsPrincipal(permissions.BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == 'principal'
    
    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)

class IsHOD(permissions.BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == 'hod'
    
    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)

class IsTeacher(permissions.BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == 'teacher'
    
    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)

class IsStudent(permissions.BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.role == 'student'
    
    def has_object_permission(self, request, view, obj):
        return IsSameCollege().has_object_permission(request, view, obj)

class IsCollegeActiveAndSubscribed(permissions.BasePermission):
    def has_permission(self, request, view):
        if not request.user.is_authenticated or not request.user.college:
            return False
        college = request.user.college
        return college.is_active and not college.is_suspended
