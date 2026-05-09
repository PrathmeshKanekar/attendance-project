from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import StaffProfileViewSet, ApprovalRequestViewSet

router = DefaultRouter()
router.register(r'profiles', StaffProfileViewSet)
router.register(r'approvals', ApprovalRequestViewSet)

urlpatterns = [
    path('', include(router.urls)),
]
