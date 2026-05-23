from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import StaffProfileViewSet

router = DefaultRouter()
router.register(r'profiles', StaffProfileViewSet)

urlpatterns = [
    path('', include(router.urls)),
]

