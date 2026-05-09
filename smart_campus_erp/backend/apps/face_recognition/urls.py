from django.urls import path
from .views import (
    FaceRegisterView,
    FaceVerifyView,
    FaceStatusView,
    FaceDeleteView,
    FaceRegistrationListView,
)

urlpatterns = [
    path('register/',              FaceRegisterView.as_view(),         name='face-register'),
    path('verify/',                FaceVerifyView.as_view(),           name='face-verify'),
    path('list/',                  FaceRegistrationListView.as_view(), name='face-list'),
    path('status/<uuid:student_id>/', FaceStatusView.as_view(),        name='face-status'),
    path('<uuid:student_id>/',     FaceDeleteView.as_view(),           name='face-delete'),
]
