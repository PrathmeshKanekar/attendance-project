from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    StudentProfileViewSet, 
    StudentSubjectEnrollmentViewSet,
    StudentRegistrationView,
)

router = DefaultRouter()
router.register(r'profiles', StudentProfileViewSet)
router.register(r'enrollments', StudentSubjectEnrollmentViewSet)

urlpatterns = [
    path('', include(router.urls)),
    path('register/', StudentRegistrationView.as_view(), name='student-register'),
]
