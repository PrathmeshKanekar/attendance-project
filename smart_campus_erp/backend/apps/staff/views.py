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

