from rest_framework import serializers
from .models        import VirtualRoom


class VirtualRoomSerializer(serializers.ModelSerializer):
    created_by_name  = serializers.SerializerMethodField()
    college_name     = serializers.CharField(
        source='college.name', read_only=True
    )
    session_count    = serializers.SerializerMethodField()

    class Meta:
        model  = VirtualRoom
        fields = [
            'id', 'name', 'building', 'floor_number',
            'center_lat', 'center_lng',
            'radius_meters', 'min_altitude', 'max_altitude',
            'is_active', 'college', 'college_name',
            'created_by', 'created_by_name',
            'session_count',
            'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'college', 'created_by',
            'created_at', 'updated_at',
        ]

    def get_created_by_name(self, obj):
        if obj.created_by:
            return obj.created_by.get_full_name()
        return None

    def get_session_count(self, obj):
        return obj.attendance_sessions.count()

    def validate_radius_meters(self, value):
        if value < 5:
            raise serializers.ValidationError(
                'Radius must be at least 5 meters.'
            )
        if value > 500:
            raise serializers.ValidationError(
                'Radius cannot exceed 500 meters.'
            )
        return value

    def validate_center_lat(self, value):
        lat = float(value)
        if not (-90 <= lat <= 90):
            raise serializers.ValidationError(
                'Latitude must be between -90 and 90.'
            )
        return value

    def validate_center_lng(self, value):
        lng = float(value)
        if not (-180 <= lng <= 180):
            raise serializers.ValidationError(
                'Longitude must be between -180 and 180.'
            )
        return value

    def validate(self, data):
        min_alt = data.get('min_altitude', 0.0)
        max_alt = data.get('max_altitude', 50.0)
        if min_alt >= max_alt:
            raise serializers.ValidationError(
                'max_altitude must be greater than min_altitude.'
            )
        return data


class CheckLocationInputSerializer(serializers.Serializer):
    lat      = serializers.FloatField()
    lng      = serializers.FloatField()
    altitude = serializers.FloatField(default=0.0)

    def validate_lat(self, value):
        if not (-90 <= value <= 90):
            raise serializers.ValidationError('Invalid latitude.')
        return value

    def validate_lng(self, value):
        if not (-180 <= value <= 180):
            raise serializers.ValidationError('Invalid longitude.')
        return value
