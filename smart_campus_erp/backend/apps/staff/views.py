from rest_framework import viewsets, status, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from django.utils import timezone
from apps.core.mixins import CollegeScopedMixin
from apps.core.permissions import IsCollegeAdmin, IsPrincipal
from .models import StaffProfile, ApprovalRequest
from .serializers import StaffProfileSerializer, ApprovalRequestSerializer

class StaffProfileViewSet(CollegeScopedMixin, viewsets.ModelViewSet):
    queryset = StaffProfile.objects.all()
    serializer_class = StaffProfileSerializer
    filterset_fields = ['department', 'is_active']
    search_fields = ['employee_id', 'user__first_name', 'user__last_name', 'user__email']

class ApprovalRequestViewSet(CollegeScopedMixin, viewsets.ModelViewSet):
    queryset = ApprovalRequest.objects.all()
    serializer_class = ApprovalRequestSerializer
    filterset_fields = ['status', 'requested_user__role']

    def get_permissions(self):
        return [permissions.IsAuthenticated(), (IsCollegeAdmin | IsPrincipal)()]

    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        approval = self.get_object()
        if approval.status != ApprovalRequest.ApprovalStatus.PENDING:
            return Response({'error': 'Request already processed'}, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            approval.status = ApprovalRequest.ApprovalStatus.APPROVED
            approval.reviewed_by = request.user
            approval.save() # Triggers save() logic for activation
            return Response({'status': 'approved and user activated'})
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        approval = self.get_object()
        if approval.status != ApprovalRequest.ApprovalStatus.PENDING:
            return Response({'error': 'Request already processed'}, status=status.HTTP_400_BAD_REQUEST)
        
        reason = request.data.get('rejection_reason', 'No reason provided')
        approval.status = ApprovalRequest.ApprovalStatus.REJECTED
        approval.reviewed_by = request.user
        approval.rejection_reason = reason
        approval.save()
        return Response({'status': 'rejected'})
