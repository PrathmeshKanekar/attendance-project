from rest_framework import serializers
from .models import VirtualRoom
from .geo_utils import calculate_room_dimensions


class VirtualRoomSerializer(serializers.ModelSerializer):
    created_by_name = serializers.SerializerMethodField()
    college_name = serializers.CharField(
        source='college.name', read_only=True
    )
    session_count = serializers.SerializerMethodField()
    validation_mode = serializers.SerializerMethodField()

    class Meta:
        model = VirtualRoom
        fields = [
            'id', 'name', 'building', 'floor_number',
            'department', 'capacity',
            'center_lat', 'center_lng',
            'radius_meters', 'min_altitude', 'max_altitude',
            'corner_coordinates', 'use_polygon',
            'estimated_length', 'estimated_width', 'estimated_area',
            'room_orientation',
            'is_active', 'college', 'college_name',
            'created_by', 'created_by_name',
            'session_count', 'validation_mode',
            'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'college', 'created_by',
            'estimated_length', 'estimated_width', 'estimated_area',
            'created_at', 'updated_at',
        ]

    def get_created_by_name(self, obj):
        if obj.created_by:
            return obj.created_by.get_full_name()
        return None

    def get_session_count(self, obj):
        return obj.attendance_sessions.count()

    def get_validation_mode(self, obj):
        return 'polygon' if obj.has_polygon else 'radius'

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

    def validate_corner_coordinates(self, value):
        """Validate corner coordinate format and count."""
        if value is None:
            return value

        if not isinstance(value, list):
            raise serializers.ValidationError(
                'corner_coordinates must be a JSON array.'
            )
        if len(value) < 3:
            raise serializers.ValidationError(
                'At least 3 corner coordinates are required.'
            )
        if len(value) > 6:
            raise serializers.ValidationError(
                'Maximum 6 corner coordinates allowed.'
            )

        for i, corner in enumerate(value):
            if not isinstance(corner, dict):
                raise serializers.ValidationError(
                    f'Corner {i+1} must be a JSON object.'
                )
            if 'lat' not in corner or 'lng' not in corner:
                raise serializers.ValidationError(
                    f'Corner {i+1} must have lat and lng fields.'
                )
            lat = float(corner['lat'])
            lng = float(corner['lng'])
            if not (-90 <= lat <= 90):
                raise serializers.ValidationError(
                    f'Corner {i+1} latitude is invalid.'
                )
            if not (-180 <= lng <= 180):
                raise serializers.ValidationError(
                    f'Corner {i+1} longitude is invalid.'
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

    def create(self, validated_data):
        """Auto-calculate dimensions and center when corners are provided."""
        corners = validated_data.get('corner_coordinates')
        if corners and len(corners) >= 3:
            dims = calculate_room_dimensions(corners)
            validated_data['estimated_length'] = dims['estimated_length']
            validated_data['estimated_width'] = dims['estimated_width']
            validated_data['estimated_area'] = dims['estimated_area']

            # Auto-set center to polygon centroid if not explicitly provided
            if not validated_data.get('center_lat') or not validated_data.get('center_lng'):
                validated_data['center_lat'] = dims['center_lat']
                validated_data['center_lng'] = dims['center_lng']

            # Auto-calculate altitude range from corners
            alts = [float(c.get('alt', 0)) for c in corners if c.get('alt') is not None]
            if alts:
                validated_data['min_altitude'] = min(alts) - 5.0
                validated_data['max_altitude'] = max(alts) + 5.0

            validated_data['use_polygon'] = True

        return super().create(validated_data)

    def update(self, instance, validated_data):
        """Re-calculate dimensions when corners are updated."""
        corners = validated_data.get('corner_coordinates')
        if corners and len(corners) >= 3:
            dims = calculate_room_dimensions(corners)
            validated_data['estimated_length'] = dims['estimated_length']
            validated_data['estimated_width'] = dims['estimated_width']
            validated_data['estimated_area'] = dims['estimated_area']

            # Update center to polygon centroid
            validated_data['center_lat'] = dims['center_lat']
            validated_data['center_lng'] = dims['center_lng']

            # Update altitude range
            alts = [float(c.get('alt', 0)) for c in corners if c.get('alt') is not None]
            if alts:
                validated_data['min_altitude'] = min(alts) - 5.0
                validated_data['max_altitude'] = max(alts) + 5.0

            validated_data['use_polygon'] = True

        return super().update(instance, validated_data)


class CheckLocationInputSerializer(serializers.Serializer):
    lat = serializers.FloatField()
    lng = serializers.FloatField()
    altitude = serializers.FloatField(default=0.0)

    def validate_lat(self, value):
        if not (-90 <= value <= 90):
            raise serializers.ValidationError('Invalid latitude.')
        return value

    def validate_lng(self, value):
        if not (-180 <= value <= 180):
            raise serializers.ValidationError('Invalid longitude.')
        return value
