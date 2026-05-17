from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

urlpatterns = [
    path('admin/', admin.site.urls),
    
    # ── API ROUTES (Legacy & Mobile Compatibility) ──────────────────
    path('api/auth/', include('apps.accounts.urls')),
    path('api/tenants/', include('apps.tenants.urls')),
    path('api/academic/', include('apps.academic.urls')),
    path('api/', include('apps.academic.urls')),
    path('api/students/', include('apps.students.urls')),
    path('api/attendance/', include('apps.attendance.urls')),
    path('api/face/', include('apps.face_recognition.urls')),
    path('api/virtual-rooms/', include('apps.virtual_rooms.urls')),
    path('api/reports/', include('apps.reports.urls')),
    path('api/notifications/', include('apps.notifications.urls')),
    path('api/approvals/', include('apps.approvals.urls')),
    
    # ── API V1 (Future Proofing) ──────────────────────────────────
    path('api/v1/accounts/', include('apps.accounts.urls')),
    path('api/v1/tenants/', include('apps.tenants.urls')),
    path('api/v1/academic/', include('apps.academic.urls')),
    path('api/v1/students/', include('apps.students.urls')),
    path('api/v1/attendance/', include('apps.attendance.urls')),
    path('api/v1/virtual-rooms/', include('apps.virtual_rooms.urls')),
    path('api/v1/reports/', include('apps.reports.urls')),
    path('api/v1/approvals/', include('apps.approvals.urls')),
    
    # ── DOCUMENTATION ──────────────────────────────────────────────
    path('api/docs/schema/', SpectacularAPIView.as_view(), name='schema'),
    path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),

] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

if settings.DEBUG and "debug_toolbar" in settings.INSTALLED_APPS:
    try:
        import debug_toolbar
        urlpatterns = [
            path('__debug__/', include(debug_toolbar.urls)),
        ] + urlpatterns
    except ImportError:
        pass

