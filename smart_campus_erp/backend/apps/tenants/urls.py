from django.urls import path
from .views import (
    CollegeListCreateView,
    CollegeDetailView,
    CollegeActivateView,
)

urlpatterns = [
    path('colleges/',                          CollegeListCreateView.as_view(), name='college-list-create'),
    path('colleges/<uuid:college_id>/',        CollegeDetailView.as_view(),     name='college-detail'),
    path('colleges/<uuid:college_id>/activate/', CollegeActivateView.as_view(), name='college-activate'),
]
