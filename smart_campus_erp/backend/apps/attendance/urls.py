from django.urls import path
from .views import (
    CreateSessionView,
    EndSessionView,
    ActiveSessionsView,
    CheckLocationView,
    MarkAttendanceView,
    ManualAttendanceView,
    SessionLogsView,
    MySessionsView,
    ValidateSessionView,
    SecurityAlertView,
)
from apps.virtual_rooms.views import TeacherSessionHeartbeatView

urlpatterns = [
    path('sessions/',                          CreateSessionView.as_view(),    name='session-create'),
    path('sessions/my/',                       MySessionsView.as_view(),       name='my-sessions'),
    path('sessions/active/',                   ActiveSessionsView.as_view(),   name='sessions-active'),
    path('sessions/<uuid:session_id>/end/',    EndSessionView.as_view(),       name='session-end'),
    path('sessions/<uuid:session_id>/logs/',   SessionLogsView.as_view(),      name='session-logs'),
    path('sessions/<uuid:session_id>/validate/', ValidateSessionView.as_view(), name='session-validate'),
    path('sessions/<uuid:session_id>/teacher-heartbeat/', TeacherSessionHeartbeatView.as_view(), name='teacher-session-heartbeat'),
    path('check-location/',                    CheckLocationView.as_view(),    name='check-location'),
    path('validate-geo/',                      CheckLocationView.as_view(),    name='validate-geo'),
    path('mark/',                              MarkAttendanceView.as_view(),   name='mark-attendance'),
    path('manual/',                            ManualAttendanceView.as_view(), name='manual-attendance'),
    path('security-alert/',                    SecurityAlertView.as_view(),    name='security-alert'),
]
