from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import StaffProfileViewSet, LabAssistantAssignmentView

router = DefaultRouter()
router.register(r'profiles', StaffProfileViewSet)

urlpatterns = [
    path('lab-assistants/', LabAssistantAssignmentView.as_view(), name='lab-assistant-assignment'),
    path('', include(router.urls)),
]

