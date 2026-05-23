from django.contrib import admin
from .models import AttendanceSession, AttendanceLog, ManualAttendanceRequest

@admin.register(AttendanceLog)
class AttendanceLogAdmin(admin.ModelAdmin):
    list_display = ('student', 'session', 'status', 'marked_at', 'device_id', 'is_mocked_gps', 'is_verified_gps', 'is_verified_face')
    list_filter = ('status', 'is_mocked_gps', 'is_verified_gps', 'is_verified_face', 'college')
    search_fields = ('student__email', 'session__session_code', 'device_id')
    readonly_fields = ('device_id', 'gps_accuracy', 'is_mocked_gps', 'security_flags', 'marked_lat', 'marked_lng', 'marked_altitude', 'face_confidence', 'blink_count')

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_superuser:
            return qs
        # Filter by college admin scope
        if hasattr(request.user, 'college') and request.user.college:
            return qs.filter(college=request.user.college)
        return qs

    def save_model(self, request, obj, form, change):
        if not change and not obj.college and hasattr(request.user, 'college'):
            obj.college = request.user.college
        super().save_model(request, obj, form, change)


@admin.register(AttendanceSession)
class AttendanceSessionAdmin(admin.ModelAdmin):
    list_display = ('session_code', 'subject_allocation', 'teacher', 'status', 'scheduled_start', 'scheduled_end')
    list_filter = ('status', 'college')
    search_fields = ('session_code', 'teacher__email')

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_superuser:
            return qs
        if hasattr(request.user, 'college') and request.user.college:
            return qs.filter(college=request.user.college)
        return qs
