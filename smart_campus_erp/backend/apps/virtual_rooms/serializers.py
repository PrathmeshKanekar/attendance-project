from rest_framework import serializers
from .models import VirtualRoom, RoomCorner
from .geo_utils import calculate_room_center, reconstruct_room_spatial_data

class RoomCornerSerializer(serializers.ModelSerializer):
    class Meta:
        model = RoomCorner
        fields = [
            'id', 'corner_index', 'latitude', 'longitude',
            'altitude', 'heading', 'accuracy', 'sensor_telemetry'
        ]

class VirtualRoomSerializer(serializers.ModelSerializer):
    corners = RoomCornerSerializer(many=True, read_only=True)
    created_by_name = serializers.SerializerMethodField(read_only=True)
    has_polygon = serializers.BooleanField(read_only=True)
    
    # Bulk write-only corner coordinates to support single-request creation/updates
    corner_coordinates = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        allow_empty=True
    )

    class Meta:
        model = VirtualRoom
        fields = [
            'id', 'college', 'name', 'building', 'department',
            'floor_number', 'capacity', 'center_lat', 'center_lng',
            'area_sq_meters', 'perimeter_meters', 'orientation_degrees',
            'reconstruction_quality', 'spatial_metadata',
            'created_by', 'created_by_name', 'created_at', 'is_active',
            'corners', 'corner_coordinates', 'has_polygon'
        ]
        read_only_fields = [
            'id', 'college', 'created_by', 'created_at',
            'area_sq_meters', 'perimeter_meters', 'orientation_degrees',
            'reconstruction_quality', 'spatial_metadata'
        ]

    def get_created_by_name(self, obj):
        if obj.created_by:
            return f"{obj.created_by.first_name} {obj.created_by.last_name}".strip() or obj.created_by.username
        return "Unknown"

    def validate(self, attrs):
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            if 'college' not in attrs and hasattr(request.user, 'college'):
                attrs['college'] = request.user.college
        return attrs

    def validate_corner_coordinates(self, value):
        if not value:
            return value
            
        if len(value) != 4:
            raise serializers.ValidationError("Exactly 4 corners must be provided.")
            
        for idx, corner in enumerate(value):
            lat = corner.get('lat') or corner.get('latitude')
            lng = corner.get('lng') or corner.get('longitude')
            
            if lat is None or lng is None:
                raise serializers.ValidationError(f"Corner {idx + 1} must have lat/latitude and lng/longitude fields.")
                
            try:
                flat = float(lat)
                flng = float(lng)
            except (ValueError, TypeError):
                raise serializers.ValidationError(f"Corner {idx + 1} coordinates must be valid numbers.")
                
            if not (-90.0 <= flat <= 90.0):
                raise serializers.ValidationError(f"Corner {idx + 1} latitude must be between -90 and 90.")
                
            if not (-180.0 <= flng <= 180.0):
                raise serializers.ValidationError(f"Corner {idx + 1} longitude must be between -180 and 180.")
            
        return value

    def create(self, validated_data):
        corner_data = validated_data.pop('corner_coordinates', None)
        request = self.context.get('request')
        if request and request.user and request.user.is_authenticated:
            validated_data['created_by'] = request.user
            if 'college' not in validated_data and hasattr(request.user, 'college'):
                validated_data['college'] = request.user.college

        room = VirtualRoom.objects.create(**validated_data)
        
        if corner_data:
            self._save_corners(room, corner_data)
            
        return room

    def update(self, instance, validated_data):
        corner_data = validated_data.pop('corner_coordinates', None)
        instance = super().update(instance, validated_data)
        
        if corner_data is not None:
            instance.corners.all().delete()
            if corner_data:
                self._save_corners(instance, corner_data)
                
        return instance

    def _save_corners(self, room, corner_data):
        corners_list = []
        for idx, c in enumerate(corner_data, start=1):
            lat = float(c.get('lat') or c.get('latitude') or 0.0)
            lng = float(c.get('lng') or c.get('longitude') or 0.0)
            alt = float(c.get('alt') or c.get('altitude') or 0.0)
            heading = float(c.get('heading') or 0.0)
            accuracy = float(c.get('accuracy') or c.get('accuracy_meters') or 0.0)
            
            # Extract optional raw IMU sensor values
            sensor_dict = {
                'gyro_x': float(c.get('gyroX') or c.get('gyro_x') or 0.0),
                'gyro_y': float(c.get('gyroY') or c.get('gyro_y') or 0.0),
                'gyro_z': float(c.get('gyroZ') or c.get('gyro_z') or 0.0),
                'accel_x': float(c.get('accelX') or c.get('accel_x') or 0.0),
                'accel_y': float(c.get('accelY') or c.get('accel_y') or 0.0),
                'accel_z': float(c.get('accelZ') or c.get('accel_z') or 0.0),
                'direction_label': str(c.get('directionLabel') or c.get('direction_label') or 'N'),
            }
            
            corner = RoomCorner.objects.create(
                room=room,
                corner_index=idx,
                latitude=lat,
                longitude=lng,
                altitude=alt,
                heading=heading,
                accuracy=accuracy,
                sensor_telemetry=sensor_dict
            )
            corners_list.append(corner)
            
        # 1. Geographic centroid calculation
        center = calculate_room_center(corners_list)
        room.center_lat = center['lat']
        room.center_lng = center['lng']
        
        # 2. Advanced Spatial Reconstruction (Area, Perimeter, Yaw, Quality Score)
        spatial = reconstruct_room_spatial_data(corners_list)
        room.area_sq_meters = spatial['area']
        room.perimeter_meters = spatial['perimeter']
        room.orientation_degrees = spatial['orientation']
        room.reconstruction_quality = spatial['quality']
        room.spatial_metadata = {
            'local_cartesian_offsets': spatial['local_points'],
            'engine_version': 'GeoSpatialFusion-v2.0',
            'slam_compatible': True,
            'unity_anchor_ready': True,
        }
        
        room.save(update_fields=[
            'center_lat', 'center_lng', 'area_sq_meters',
            'perimeter_meters', 'orientation_degrees',
            'reconstruction_quality', 'spatial_metadata'
        ])