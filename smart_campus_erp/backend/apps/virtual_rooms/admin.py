from django.contrib import admin
from django.contrib.gis import admin as gis_admin
from .models import VirtualRoom, RoomCorner, SpatialMetadata, AttendanceLocationLog

@admin.register(VirtualRoom)
class VirtualRoomAdmin(gis_admin.GISModelAdmin):
    list_display = ('room_name', 'building', 'floor', 'college', 'has_polygon', 'is_active')
    list_filter = ('college', 'building', 'is_active')
    search_fields = ('room_name', 'building', 'department')
    readonly_fields = ('length', 'width', 'area', 'min_altitude', 'max_altitude')

@admin.register(RoomCorner)
class RoomCornerAdmin(admin.ModelAdmin):
    list_display = ('room', 'corner_index', 'altitude', 'accuracy')
    list_filter = ('room',)

@admin.register(SpatialMetadata)
class SpatialMetadataAdmin(admin.ModelAdmin):
    list_display = ('room', 'last_updated')

@admin.register(AttendanceLocationLog)
class AttendanceLocationLogAdmin(admin.ModelAdmin):
    list_display = ('user', 'room', 'is_valid', 'validation_mode', 'confidence', 'checked_at')
    list_filter = ('is_valid', 'validation_mode', 'room')
    search_fields = ('user__email', 'user__first_name')
    readonly_fields = ('checked_at',)
