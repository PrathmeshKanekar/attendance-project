from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView
from .views import (
    EmailLoginView,
    PRNLoginView,
    MeView,
    LogoutView,
    RegisterDeviceView,
    CreateUserView,
    ListUsersView,
    ApproveUserView,
    RejectUserView,
    UserDetailView,
    DeactivateUserView,
    PendingApprovalsView,
)

urlpatterns = [
    # Auth
    path('login/email/',      EmailLoginView.as_view(),    name='login-email'),
    path('login/prn/',        PRNLoginView.as_view(),       name='login-prn'),
    path('me/',               MeView.as_view(),             name='me'),
    path('logout/',           LogoutView.as_view(),         name='logout'),
    path('refresh/',          TokenRefreshView.as_view(),   name='token-refresh'),
    path('register-device/',  RegisterDeviceView.as_view(), name='register-device'),

    # User management
    path('users/',                      ListUsersView.as_view(),  name='users-list'),
    path('users/create/',               CreateUserView.as_view(), name='users-create'),
    path('users/<uuid:user_id>/approve/', ApproveUserView.as_view(), name='user-approve'),
    path('users/<uuid:user_id>/reject/',  RejectUserView.as_view(),  name='user-reject'),
    path('users/<uuid:user_id>/',            UserDetailView.as_view(),    name='user-detail'),
    path('users/<uuid:user_id>/deactivate/', DeactivateUserView.as_view(),name='user-deactivate'),
    path('users/pending/',                   PendingApprovalsView.as_view(),name='users-pending'),
]

