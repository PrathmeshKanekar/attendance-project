from rest_framework.permissions import BasePermission
from rest_framework.exceptions import PermissionDenied
from django.db.models import Q

def get_lab_assistant_departments(user):
    """
    Returns a list of assigned departments for a lab assistant.
    For admin/principal/HOD roles, returns matching departments of their college/department.
    """
    if not user or not user.is_authenticated:
        return []
    
    if user.role in ['super_admin', 'college_admin', 'principal']:
        from apps.academic.models import Department
        return list(Department.objects.filter(college=user.college))
        
    if user.role == 'lab_assistant':
        return [assignment.department for assignment in user.lab_departments.filter(is_active=True)]
        
    if user.role == 'hod':
        profile = getattr(user, 'staff_profile', None)
        if profile and profile.department:
            return [profile.department]
            
    return []

def filter_by_assigned_department(user, queryset, department_field='department'):
    """
    Filters a queryset based on the user's assigned departments if they are a Lab Assistant.
    If the field is nested (e.g. division__course__department), support double underscore notation.
    """
    if not user or not user.is_authenticated:
        return queryset.none()
        
    if user.role in ['super_admin', 'college_admin', 'principal']:
        # Admins see everything in their college
        if hasattr(queryset.model, 'college'):
            return queryset.filter(college=user.college)
        return queryset
        
    if user.role == 'lab_assistant':
        depts = get_lab_assistant_departments(user)
        dept_ids = [d.id for d in depts]
        filter_kwargs = {f"{department_field}__in": dept_ids}
        return queryset.filter(**filter_kwargs)
        
    if user.role == 'hod':
        depts = get_lab_assistant_departments(user)
        if depts:
            dept_ids = [d.id for d in depts]
            filter_kwargs = {f"{department_field}__in": dept_ids}
            return queryset.filter(**filter_kwargs)
        return queryset.none()
        
    return queryset

class IsLabAssistantDepartmentScoped(BasePermission):
    """
    DRF permission class that ensures a Lab Assistant can only perform operations 
    on resources associated with their assigned departments.
    """
    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        # If user is not lab_assistant, let other permissions handle it
        if request.user.role != 'lab_assistant':
            return True
        # For lab assistants, they must have at least one active department assignment
        depts = get_lab_assistant_departments(request.user)
        return len(depts) > 0

    def has_object_permission(self, request, view, obj):
        user = request.user
        if not user or not user.is_authenticated:
            return False
        if user.role != 'lab_assistant':
            return True
            
        # Try to find a department relationship on the object
        dept = None
        if hasattr(obj, 'department'):
            dept = obj.department
        elif hasattr(obj, 'division') and obj.division and hasattr(obj.division, 'course'):
            dept = obj.division.course.department
        elif hasattr(obj, 'course') and obj.course:
            dept = obj.course.department
            
        if dept is None:
            # If no direct department relationship can be inspected, let it pass or verify college
            if hasattr(obj, 'college'):
                return obj.college == user.college
            return True
            
        assigned_depts = get_lab_assistant_departments(user)
        return dept in assigned_depts
