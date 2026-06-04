from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import VirtualRoomViewSet, RoomPresenceHeartbeatView

router = DefaultRouter()
router.register(r'', VirtualRoomViewSet, basename='virtualroom')

urlpatterns = [
    # Presence heartbeat: POST /api/virtual-rooms/{room_id}/presence/heartbeat/
    path(
        '<uuid:room_id>/presence/heartbeat/',
        RoomPresenceHeartbeatView.as_view(),
        name='room-presence-heartbeat',
    ),
    path('', include(router.urls)),
]
