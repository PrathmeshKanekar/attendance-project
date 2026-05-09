from django.urls import path
from .views      import PendingApprovalListView

urlpatterns = [
    path('pending/', PendingApprovalListView.as_view(), name='approvals-pending'),
]
