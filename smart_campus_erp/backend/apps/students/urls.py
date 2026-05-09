from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    StudentProfileViewSet, 
    StudentSubjectEnrollmentViewSet,
    StudentRegistrationView,
    StudentApprovalListView,
    StudentApprovalActionView
)

router = DefaultRouter()
router.register(r'profiles', StudentProfileViewSet)
router.register(r'enrollments', StudentSubjectEnrollmentViewSet)

urlpatterns = [
    path('', include(router.urls)),
    path('register/', StudentRegistrationView.as_view(), name='student-register'),
    path('approvals/', StudentApprovalListView.as_view(), name='student-approval-list'),
    path('approvals/<uuid:student_id>/', StudentApprovalActionView.as_view(), name='student-approval-action'),
]
