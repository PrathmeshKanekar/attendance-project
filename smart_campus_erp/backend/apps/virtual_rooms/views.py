from rest_framework import viewsets, permissions, status
from rest_framework.response import Response
from .models import VirtualRoom
from .serializers import VirtualRoomSerializer
from .permissions import IsLabAssistantOrReadOnly

class VirtualRoomViewSet(viewsets.ModelViewSet):
    """
    ViewSet for viewing, creating, updating and deleting VirtualRooms.
    Enforces that only Lab Assistants can create/update/delete.
    """
    queryset = VirtualRoom.objects.all().prefetch_related('corners')
    serializer_class = VirtualRoomSerializer
    permission_classes = [IsLabAssistantOrReadOnly]
    search_fields = ['name', 'building', 'department']
    ordering_fields = ['name', 'created_at', 'floor_number', 'capacity']
    filterset_fields = ['building', 'department', 'floor_number', 'is_active']

    def get_queryset(self):
        queryset = super().get_queryset()
        user = self.request.user
        # Filter by requesting user's college to enforce multi-tenant isolation
        if user and user.is_authenticated and hasattr(user, 'college') and user.college:
            queryset = queryset.filter(college=user.college)
            if user.role == 'lab_assistant':
                from apps.accounts.rbac import get_lab_assistant_departments
                depts = get_lab_assistant_departments(user)
                dept_names_and_codes = []
                for d in depts:
                    dept_names_and_codes.append(d.name)
                    dept_names_and_codes.append(d.code)
                queryset = queryset.filter(department__in=dept_names_and_codes)
        return queryset
