from django.urls import path
from .views import (
    VirtualRoomListCreateView,
    VirtualRoomDetailView,
    CheckLocationView,
    RoomStatsView,
)

urlpatterns = [
    path('',
         VirtualRoomListCreateView.as_view(), name='room-list-create'),
    path('<uuid:room_id>/',
         VirtualRoomDetailView.as_view(),     name='room-detail'),
    path('<uuid:room_id>/check-location/',
         CheckLocationView.as_view(),          name='room-check-location'),
    path('<uuid:room_id>/stats/',
         RoomStatsView.as_view(),              name='room-stats'),
]
