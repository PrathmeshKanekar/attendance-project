from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    StudentProfileViewSet, 
    StudentSubjectEnrollmentViewSet,
    StudentRegistrationView,
    StudentDuplicateCheckView,
)

router = DefaultRouter()
router.register(r'profiles', StudentProfileViewSet, basename='student-profile')
router.register(r'enrollments', StudentSubjectEnrollmentViewSet, basename='student-enrollment')

urlpatterns = [
    path('', include(router.urls)),
    path('register/', StudentRegistrationView.as_view(), name='student-register'),
    path('check-duplicate/', StudentDuplicateCheckView.as_view(), name='student-check-duplicate'),
]
