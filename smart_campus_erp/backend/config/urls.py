from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from drf_spectacular.views import SpectacularAPIView, SpectacularRedocView, SpectacularSwaggerView

urlpatterns = [
    path('admin/', admin.site.urls),
    
    # Explicit routes requested by user
    path('api/auth/', include('apps.accounts.urls')),
    path('api/tenants/', include('apps.tenants.urls')),
    path('api/academic/', include('apps.academic.urls')),
    path('api/students/', include('apps.students.urls')),
    path('api/', include('apps.tenants.urls')),
    path('api/', include('apps.academic.urls')),
    path('api/', include('apps.students.urls')),
    path('api/', include('apps.attendance.urls')),
    path('api/attendance/', include('apps.attendance.urls')),
    path('api/face/', include('apps.face_recognition.urls')),
    path('api/virtual-rooms/', include('apps.virtual_rooms.urls')),
    path('api/reports/', include('apps.reports.urls')),
    path('api/notifications/', include('apps.notifications.urls')),
    path('api/approvals/', include('apps.approvals.urls')),
    
    # API v1
    path('api/', include('apps.accounts.urls')),
    path('api/v1/', include('apps.accounts.urls')),
    path('api/v1/tenants/', include('apps.tenants.urls')),
    path('api/v1/students/', include('apps.students.urls')),
    path('api/v1/staff/', include('apps.staff.urls')),
    path('api/v1/academic/', include('apps.academic.urls')),
    path('api/v1/attendance/', include('apps.attendance.urls')),
    path('api/v1/approvals/', include('apps.staff.urls')), # Shared with staff
    path('api/v1/notifications/', include('apps.notifications.urls')),
    path('api/v1/reports/', include('apps.reports.urls')),
    path('api/v1/face/', include('apps.face_recognition.urls')),

    
    # Documentation
    path('api/docs/schema/', SpectacularAPIView.as_view(), name='schema'),
    path('api/docs/swagger/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
    path('api/docs/redoc/', SpectacularRedocView.as_view(url_name='schema'), name='redoc'),
]

# Conditional Virtual Rooms
if 'apps.virtual_rooms' in settings.INSTALLED_APPS:
    urlpatterns += [path('api/v1/rooms/', include('apps.virtual_rooms.urls'))]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
    
    if 'debug_toolbar' in settings.INSTALLED_APPS:
        import debug_toolbar
        urlpatterns += [path('__debug__/', include(debug_toolbar.urls))]
