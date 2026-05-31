from django.contrib import admin
from .models import VirtualRoom, RoomCorner

@admin.register(VirtualRoom)
class VirtualRoomAdmin(admin.ModelAdmin):
    list_display = ('name', 'building', 'floor_number', 'college', 'has_polygon', 'is_active')
    list_filter = ('college', 'building', 'is_active')
    search_fields = ('name', 'building', 'department')
    readonly_fields = ('created_at',)

@admin.register(RoomCorner)
class RoomCornerAdmin(admin.ModelAdmin):
    list_display = ('room', 'corner_index', 'latitude', 'longitude', 'altitude', 'accuracy')
    list_filter = ('room',)
