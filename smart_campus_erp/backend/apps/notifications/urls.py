from django.urls import path
from .views import (
    NotificationListView,
    MarkNotificationReadView,
    MarkAllReadView,
    UnreadCountView,
)

urlpatterns = [
    path('',                              NotificationListView.as_view(),     name='notif-list'),
    path('read-all/',                     MarkAllReadView.as_view(),          name='notif-read-all'),
    path('unread-count/',                 UnreadCountView.as_view(),          name='notif-unread-count'),
    path('<uuid:notif_id>/read/',         MarkNotificationReadView.as_view(), name='notif-read'),
]
