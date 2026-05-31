from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import VirtualRoomViewSet

router = DefaultRouter()
router.register(r'', VirtualRoomViewSet, basename='virtualroom')

urlpatterns = [
    path('', include(router.urls)),
]
