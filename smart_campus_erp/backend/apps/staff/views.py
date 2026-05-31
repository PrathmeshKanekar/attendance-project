from rest_framework import viewsets, status, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from django.utils import timezone
from apps.core.mixins import CollegeScopedMixin
from apps.accounts.permissions import IsCollegeAdmin, IsPrincipal
from .models import StaffProfile
from .serializers import StaffProfileSerializer

class StaffProfileViewSet(CollegeScopedMixin, viewsets.ModelViewSet):
    queryset = StaffProfile.objects.all()
    serializer_class = StaffProfileSerializer
    filterset_fields = ['department', 'is_active']
    search_fields = ['employee_id', 'user__first_name', 'user__last_name', 'user__email']


from django.contrib.auth import get_user_model
from rest_framework.views import APIView
from apps.accounts.permissions import IsCollegeAdmin, IsPrincipal
from .models import LabAssistantDepartment
from apps.academic.models import Department

User = get_user_model()

class LabAssistantAssignmentView(APIView):
    permission_classes = [permissions.IsAuthenticated, IsCollegeAdmin | IsPrincipal]

    def get(self, request):
        college = request.user.college
        # Get all users with role 'lab_assistant' in same college
        assistants = User.objects.filter(role='lab_assistant', college=college)
        data = []
        for assistant in assistants:
            # Get assigned departments
            assigned = LabAssistantDepartment.objects.filter(user=assistant, is_active=True).select_related('department')
            data.append({
                'id': str(assistant.id),
                'email': assistant.email,
                'full_name': assistant.get_full_name(),
                'assigned_departments': [
                    {
                        'id': str(a.department.id),
                        'name': a.department.name,
                        'code': a.department.code
                    } for a in assigned
                ]
            })
        return Response(data, status=status.HTTP_200_OK)

    def post(self, request):
        assistant_id = request.data.get('assistant_id')
        department_ids = request.data.get('department_ids', []) # List of UUIDs

        college = request.user.college
        try:
            assistant = User.objects.get(id=assistant_id, role='lab_assistant', college=college)
        except User.DoesNotExist:
            return Response({"error": "Lab Assistant not found or not in your college."}, status=status.HTTP_404_NOT_FOUND)

        # Remove existing active assignments
        LabAssistantDepartment.objects.filter(user=assistant).delete()

        # Add new assignments
        new_assignments = []
        for dept_id in department_ids:
            try:
                dept = Department.objects.get(id=dept_id, college=college)
                new_assignments.append(
                    LabAssistantDepartment(user=assistant, department=dept, is_active=True)
                )
            except Department.DoesNotExist:
                continue

        if new_assignments:
            LabAssistantDepartment.objects.bulk_create(new_assignments)

        return Response({
            "success": True,
            "message": f"Successfully updated department assignments for {assistant.get_full_name()}."
        }, status=status.HTTP_200_OK)


