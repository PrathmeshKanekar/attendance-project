import math
from rest_framework import serializers
from .models import VirtualRoom, RoomCorner, VirtualRoomAuditLog, VirtualRoomSecurityLog
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
            'corners', 'corner_coordinates', 'has_polygon',
            # New creation workflow fields
            'room_number', 'description', 'location_method',
            'gps_accuracy', 'gps_health_score', 'status',
            'boundary_geojson', 'width_meters', 'length_meters',
            'is_deleted', 'updated_at',
        ]
        read_only_fields = [
            'id', 'college', 'created_by', 'created_at',
            'area_sq_meters', 'perimeter_meters', 'orientation_degrees',
            'reconstruction_quality', 'spatial_metadata',
            'updated_at',
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
            raise serializers.ValidationError("Exactly 4 corners must be provided to define a closed spatial room.")
            
        pts = []
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
            
            pts.append((flat, flng))

        # ─── A. Self-Intersection Check ───────────────────────────────────────
        p1, p2, p3, p4 = pts[0], pts[1], pts[2], pts[3]
        
        def ccw(A, B, C):
            # Returns True if points A, B, C are in counter-clockwise order
            return (C[1] - A[1]) * (B[0] - A[0]) > (B[1] - A[1]) * (C[0] - A[0])
            
        def intersect(A, B, C, D):
            # Returns True if line segment AB and CD intersect
            return ccw(A, C, D) != ccw(B, C, D) and ccw(A, B, C) != ccw(A, B, D)

        # Non-adjacent edges of a 4-corner polygon:
        # Edge 1 (p1-p2) & Edge 3 (p3-p4)
        # Edge 2 (p2-p3) & Edge 4 (p4-p1)
        if intersect(p1, p2, p3, p4) or intersect(p2, p3, p4, p1):
            raise serializers.ValidationError(
                "Self-intersecting/twisted polygon detected! "
                "You must capture the corners continuously in a clockwise or "
                "counter-clockwise circle around the room boundary."
            )

        # ─── B. Realistic Room Area Verification ────────────────────────────────
        cx = sum(p[0] for p in pts) / 4.0
        cy = sum(p[1] for p in pts) / 4.0
        lat_rad = math.radians(cx)
        
        meters_per_degree_lat = 110574.0
        meters_per_degree_lng = 111320.0 * math.cos(lat_rad)
        
        local_pts = []
        for p in pts:
            x = (p[1] - cy) * meters_per_degree_lng
            y = (p[0] - cx) * meters_per_degree_lat
            local_pts.append((x, y))
            
        shoelace_sum = 0.0
        for i in range(4):
            next_idx = (i + 1) % 4
            shoelace_sum += (local_pts[i][0] * local_pts[next_idx][1]) - (local_pts[next_idx][0] * local_pts[i][1])
        area = abs(shoelace_sum) / 2.0
        
        if area < 3.0:
            raise serializers.ValidationError(
                f"Calculated room area is too small ({area:.1f} m²). Minimum is 3.0 m²."
            )
        if area > 1200.0:
            raise serializers.ValidationError(
                f"Calculated room area is unrealistically large ({area:.1f} m²). "
                "Maximum geofenced indoor room size is 1200.0 m²."
            )
            
        return value

    def create(self, validated_data):
        corner_data = validated_data.pop('corner_coordinates', None)
        request = self.context.get('request')
        if request and request.user and request.user.is_authenticated:
            validated_data['created_by'] = request.user
            if 'college' not in validated_data and hasattr(request.user, 'college'):
                validated_data['college'] = request.user.college

        # Auto-set status to 'created' when all required data is present
        if corner_data and len(corner_data) == 4:
            validated_data.setdefault('status', 'created')
        else:
            validated_data.setdefault('status', 'draft')

        room = VirtualRoom.objects.create(**validated_data)
        
        if corner_data:
            self._save_corners(room, corner_data)

        # Write audit log
        if request and request.user and request.user.is_authenticated:
            VirtualRoomAuditLog.objects.create(
                room=room,
                event_type='created',
                actor=request.user,
                actor_role=getattr(request.user, 'role', ''),
                event_data={
                    'room_name': room.name,
                    'room_number': room.room_number,
                    'building_name': room.building,
                    'department': room.department,
                    'floor': str(room.floor_number),
                    'capacity': room.capacity,
                    'center_latitude': room.center_lat,
                    'center_longitude': room.center_lng,
                    'location_method': room.location_method,
                    'gps_accuracy': room.gps_accuracy,
                    'gps_health_score': room.gps_health_score,
                    'area_sqm': room.area_sq_meters,
                    'width_meters': room.width_meters,
                    'length_meters': room.length_meters,
                    'status': room.status,
                    'boundary_geojson': room.boundary_geojson,
                },
                device_info=request.data.get('device_info', {}),
                gps_snapshot=request.data.get('gps_snapshot', {}),
            )
            
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
        geojson_coords = []
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
            geojson_coords.append([lng, lat])
            
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
            'width_meters': room.width_meters,
            'length_meters': room.length_meters,
            'rotation_degrees': spatial['orientation'],
            'confidence_score': spatial['quality'],
            'local_cartesian_offsets': spatial['local_points'],
            'engine_version': 'GeoSpatialFusion-v2.0',
            'slam_compatible': True,
            'unity_anchor_ready': True,
        }

        # 3. Generate boundary GeoJSON (closed polygon)
        if geojson_coords:
            geojson_coords.append(geojson_coords[0])  # Close the ring
            room.boundary_geojson = {
                'type': 'Polygon',
                'coordinates': [geojson_coords],
            }
        
        room.save(update_fields=[
            'center_lat', 'center_lng', 'area_sq_meters',
            'perimeter_meters', 'orientation_degrees',
            'reconstruction_quality', 'spatial_metadata',
            'boundary_geojson',
            'width_meters',
            'length_meters',
        ])

from .models import RoomPresence, RoomEntryLog

class RoomPresenceSerializer(serializers.ModelSerializer):
    user_name = serializers.SerializerMethodField()
    user_role = serializers.SerializerMethodField()

    class Meta:
        model = RoomPresence
        fields = [
            'id', 'user', 'user_name', 'user_role',
            'last_lat', 'last_lng', 'last_accuracy',
            'entered_at', 'exit_time', 'last_heartbeat',
            'is_inside', 'device_id',
        ]
        read_only_fields = fields

    def get_user_name(self, obj):
        return f"{obj.user.first_name} {obj.user.last_name}".strip()

    def get_user_role(self, obj):
        return obj.user.role


# ─── Duplicate Check Serializer ──────────────────────────────────────────────

class DuplicateCheckSerializer(serializers.Serializer):
    """Input serializer for the duplicate-check endpoint."""
    department = serializers.CharField(required=True)
    building = serializers.CharField(required=True)
    floor = serializers.CharField(required=True)
    room_number = serializers.CharField(required=False, default='')
    room_name = serializers.CharField(required=False, default='')
    center_lat = serializers.FloatField(required=False, default=None)
    center_lng = serializers.FloatField(required=False, default=None)