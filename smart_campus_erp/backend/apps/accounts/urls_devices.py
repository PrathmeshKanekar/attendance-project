from django.urls import path
from .views import (
    DeviceRegisterView,
    DeviceVerifyView,
    DeviceRefreshView,
)

urlpatterns = [
    path('register/', DeviceRegisterView.as_view(), name='device-register'),
    path('me/',       DeviceVerifyView.as_view(),    name='device-me'),
    path('refresh/',  DeviceRefreshView.as_view(),   name='device-refresh'),
]
