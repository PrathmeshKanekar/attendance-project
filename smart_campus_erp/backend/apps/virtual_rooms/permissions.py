from rest_framework import permissions

class IsLabAssistantOrReadOnly(permissions.BasePermission):
    """
    Custom permission to only allow Lab Assistants to create, update, or delete virtual rooms.
    All other authenticated users can read virtual rooms.
    """
    def has_permission(self, request, view):
        # Must be authenticated
        if not request.user or not request.user.is_authenticated:
            return False

        # Read permissions are allowed to any authenticated user (e.g. for listing/viewing)
        if request.method in permissions.SAFE_METHODS:
            return True

        # Write permissions (POST, PUT, PATCH, DELETE) are ONLY allowed to lab_assistant
        return getattr(request.user, 'role', '') == 'lab_assistant'
