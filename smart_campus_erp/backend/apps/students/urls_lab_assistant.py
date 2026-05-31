from django.urls import path
from .views import (
    LabAssistantPendingStudentsView,
    LabAssistantApproveStudentView,
    LabAssistantRejectStudentView,
    LabAssistantBlockStudentView,
)

urlpatterns = [
    path('pending-students/', LabAssistantPendingStudentsView.as_view(), name='lab-assistant-pending-students'),
    path('students/<uuid:student_id>/approve/', LabAssistantApproveStudentView.as_view(), name='lab-assistant-approve-student'),
    path('students/<uuid:student_id>/reject/', LabAssistantRejectStudentView.as_view(), name='lab-assistant-reject-student'),
    path('students/<uuid:student_id>/block/', LabAssistantBlockStudentView.as_view(), name='lab-assistant-block-student'),
]
