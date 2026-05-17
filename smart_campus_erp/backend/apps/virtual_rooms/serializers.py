"""
serializers.py — Virtual Room REST API Serializers
===================================================
"""
from __future__ import annotations
from rest_framework import serializers
from django.contrib.gis.geos import Point
from .models import VirtualRoom, RoomCorner
from .geo_utils import haversine_distance, calculate_spatial_vectors


# ─────────────────────────────────────────────────────────────────────────────
# Sub-serializers
# ─────────────────────────────────────────────────────────────────────────────

class RoomCornerSerializer(serializers.ModelSerializer):
    lat = serializers.FloatField(source="latitude")
    lng = serializers.FloatField(source="longitude")
    captured_at = serializers.DateTimeField(source="timestamp")
    accelerometer_data = serializers.JSONField(source="accelerometer", required=False, allow_null=True)
    gyroscope_data = serializers.JSONField(source="gyroscope", required=False, allow_null=True)
    magnetic_field_data = serializers.JSONField(source="magnetic_field", required=False, allow_null=True)

    class Meta:
        model  = RoomCorner
        fields = [
            "id", "corner_index",
            "lat", "lng", "altitude", "accuracy",
            "heading", "pitch", "roll", "yaw",
            "accelerometer_data", "gyroscope_data", "magnetic_field_data",
            "captured_at",
        ]


class SpatialVectorSerializer(serializers.Serializer):
    origin_point = serializers.JSONField()
    x_axis_vector = serializers.JSONField()
    y_axis_vector = serializers.JSONField()
    z_axis_vector = serializers.JSONField()
    x_extent = serializers.FloatField()
    y_extent = serializers.FloatField()
    calculated_at = serializers.DateTimeField(required=False)


# ─────────────────────────────────────────────────────────────────────────────
# Main room serializer
# ─────────────────────────────────────────────────────────────────────────────

class VirtualRoomSerializer(serializers.ModelSerializer):
    corners         = RoomCornerSerializer(many=True, read_only=True)
    college_name    = serializers.CharField(source="college.name", read_only=True)
    college         = serializers.PrimaryKeyRelatedField(read_only=True)
    spatial_vectors = serializers.SerializerMethodField()
    corner_count    = serializers.IntegerField(read_only=True)
    has_polygon     = serializers.BooleanField(read_only=True)
    created_by_name = serializers.SerializerMethodField()

    def get_spatial_vectors(self, obj) -> dict | None:
        if obj.x_axis_vector:
            corners = obj.corners.all().order_by("corner_index")
            origin = {}
            if corners.exists():
                c1 = corners[0]
                origin = {"lat": c1.lat, "lng": c1.lng, "alt": c1.altitude}
            return {
                "origin_point": origin,
                "x_axis_vector": obj.x_axis_vector,
                "y_axis_vector": obj.y_axis_vector,
                "z_axis_vector": obj.z_axis_vector,
                "x_extent": obj.length or 0.0,
                "y_extent": obj.width or 0.0,
            }
        return None

    # User response compatibility overrides
    floor           = serializers.IntegerField(source="floor_number", read_only=True)
    polygon         = serializers.SerializerMethodField()

    # Write-only: bulk corner payload at room creation
    corner_coordinates = serializers.ListField(
        child=serializers.DictField(),
        required=False,
        write_only=True,
        help_text='[{"lat":…,"lng":…,"alt":…,"accuracy":…,"heading":…,"pitch":…,"roll":…,"yaw":…}, …]',
    )

    class Meta:
        model  = VirtualRoom
        fields = [
            # Identity
            "id", "college", "college_name", "name", "building",
            "floor_number", "floor", "department", "capacity",
            # Spatial
            "center_lat", "center_lng", "radius_meters",
            "min_altitude", "max_altitude", "altitude_tolerance",
            "length", "width", "area",
            "use_polygon", "has_polygon", "corner_count",
            "polygon",
            # Spatial Metadata
            "normalized_coordinates", "orientation_matrix", "room_dimensions",
            # Relations
            "corners", "spatial_vectors",
            # Meta
            "is_active", "created_at", "updated_at",
            "created_by_name",
            # Write-only
            "corner_coordinates",
        ]
        read_only_fields = [
            "length", "width", "area",
            "min_altitude", "max_altitude",
            "use_polygon",
            "center_lat", "center_lng",
            "normalized_coordinates", "orientation_matrix", "room_dimensions",
        ]

    def get_created_by_name(self, obj):
        if obj.created_by:
            return f"{obj.created_by.first_name} {obj.created_by.last_name}".strip() or str(obj.created_by)
        return None

    def get_polygon(self, obj):
        corners = obj.corners.all().order_by("corner_index")
        if corners.exists():
            return [{"lat": c.lat, "lng": c.lng} for c in corners]
        if obj.boundary_polygon:
            try:
                geom = obj.boundary_polygon
                if isinstance(geom, str):
                    from django.contrib.gis.geos import GEOSGeometry
                    geom = GEOSGeometry(geom)
                return [{"lat": coord[1], "lng": coord[0]} for coord in geom.coords[0]]
            except Exception:
                pass
        return []

    def validate_corner_coordinates(self, value: list) -> list:
        if not value:
            return value
        if len(value) != 4:
            raise serializers.ValidationError("Exactly 4 corner coordinates are required.")

        class MockCorner:
            def __init__(self, lat, lng, altitude):
                self.lat = lat
                self.lng = lng
                self.altitude = altitude

        mock_corners = [
            MockCorner(
                float(c.get("lat", 0.0)),
                float(c.get("lng", 0.0)),
                float(c.get("alt", 0.0)),
            )
            for c in value
        ]

        # 1. GPS Accuracy Validation (accuracy <= 80 meters required)
        for i, c in enumerate(value):
            acc = float(c.get("accuracy", 10.0))
            if acc > 80.0:
                raise serializers.ValidationError(
                    f"Corner {i+1} has poor GPS accuracy ({acc:.1f}m). Accuracy must be 80 meters or better."
                )

        # 2. Check uniqueness and minimum distance (1.5 meters)
        for i in range(len(value)):
            for j in range(i + 1, len(value)):
                d = haversine_distance(
                    mock_corners[i].lat, mock_corners[i].lng,
                    mock_corners[j].lat, mock_corners[j].lng,
                )
                if d < 1.5:
                    raise serializers.ValidationError(
                        f"Distance between Corner {i+1} and Corner {j+1} is only {d:.2f}m. "
                        "All corners must be at least 1.5 meters apart to avoid duplicate inputs."
                    )

        # 3. Check for self-intersecting polygon edges
        from .geo_utils import check_polygon_self_intersection, polygon_area_m2
        if check_polygon_self_intersection(mock_corners):
            raise serializers.ValidationError("Impossible geometry: The captured boundary polygon is self-intersecting.")

        # 4. Check for room dimensions (too small or too vast)
        c1, c2, c3, c4 = mock_corners[0], mock_corners[1], mock_corners[2], mock_corners[3]
        length = haversine_distance(c1.lat, c1.lng, c2.lat, c2.lng)
        width = haversine_distance(c1.lat, c1.lng, c4.lat, c4.lng)

        if length < 1.0 or width < 1.0:
            raise serializers.ValidationError(
                f"Impossible geometry: Room dimensions are too narrow (Length: {length:.1f}m, Width: {width:.1f}m). "
                "Minimum room dimension is 1.0 meter."
            )
        if length > 200.0 or width > 200.0:
            raise serializers.ValidationError(
                f"Impossible geometry: Room dimensions are too vast (Length: {length:.1f}m, Width: {width:.1f}m). "
                "Maximum room dimension is 200.0 meters."
            )

        # 5. Check calculated area
        area = polygon_area_m2(mock_corners)
        if area < 2.0:
            raise serializers.ValidationError(
                f"Impossible geometry: Room area ({area:.1f} m²) is too small. "
                "Minimum required area is 2.0 square meters."
            )
        if area > 10000.0:
            raise serializers.ValidationError(
                f"Impossible geometry: Room area ({area:.1f} m²) is too large. "
                "Maximum allowed area is 10,000.0 square meters."
            )

        return value

    def create(self, validated_data: dict) -> VirtualRoom:
        validated_data.pop("magnetic_heading", None)
        corner_data: list | None = validated_data.pop("corner_coordinates", None)
        room = VirtualRoom.objects.create(**validated_data)

        if corner_data:
            self._create_corners(room, corner_data)
            calculate_spatial_vectors(room)

        return room

    def update(self, instance: VirtualRoom, validated_data: dict) -> VirtualRoom:
        validated_data.pop("magnetic_heading", None)
        corner_data: list | None = validated_data.pop("corner_coordinates", None)
        instance = super().update(instance, validated_data)

        if corner_data:
            # Delete old corners and recreate
            instance.corners.all().delete()
            self._create_corners(instance, corner_data)
            calculate_spatial_vectors(instance)

        return instance

    @staticmethod
    def _create_corners(room: VirtualRoom, corner_data: list) -> None:
        for index, c in enumerate(corner_data, start=1):
            def safe_float(val, default=0.0) -> float:
                try:
                    if val is None:
                        return default
                    return float(val)
                except (ValueError, TypeError):
                    return default

            RoomCorner.objects.create(
                room=room,
                corner_index=index,
                latitude=safe_float(c.get("lat")),
                longitude=safe_float(c.get("lng")),
                altitude=safe_float(c.get("alt") or c.get("altitude")),
                accuracy=safe_float(c.get("accuracy"), 10.0),
                heading=safe_float(c.get("heading") or c.get("magnetic_heading")),
                pitch=safe_float(c.get("pitch")),
                roll=safe_float(c.get("roll")),
                yaw=safe_float(c.get("yaw")),
                accelerometer=c.get("accelerometer"),
                gyroscope=c.get("gyroscope"),
                magnetic_field=c.get("magnetic_field") or c.get("magnetic_field_data"),
            )


# ─────────────────────────────────────────────────────────────────────────────
# Corner capture (incremental — one at a time from device)
# ─────────────────────────────────────────────────────────────────────────────

class RoomCaptureSerializer(serializers.Serializer):
    room_id      = serializers.UUIDField()
    corner_index = serializers.IntegerField(min_value=1, max_value=4)
    lat          = serializers.FloatField(min_value=-90,  max_value=90)
    lng          = serializers.FloatField(min_value=-180, max_value=180)
    altitude     = serializers.FloatField()
    accuracy     = serializers.FloatField(min_value=0)
    heading      = serializers.FloatField()
    pitch        = serializers.FloatField(default=0.0)
    roll         = serializers.FloatField(default=0.0)
    yaw          = serializers.FloatField(default=0.0)
    accelerometer     = serializers.JSONField(required=False, allow_null=True)
    gyroscope         = serializers.JSONField(required=False, allow_null=True)
    magnetic_field    = serializers.JSONField(required=False, allow_null=True)

    def validate(self, data):
        room_id = data.get("room_id")
        corner_index = data.get("corner_index")
        lat = data.get("lat")
        lng = data.get("lng")
        accuracy = data.get("accuracy", 10.0)

        try:
            room = VirtualRoom.objects.get(id=room_id)
        except VirtualRoom.DoesNotExist:
            raise serializers.ValidationError({"room_id": "Room does not exist."})

        # 1. GPS Accuracy Validation (accuracy <= 80 meters required)
        if accuracy > 80.0:
            raise serializers.ValidationError({"accuracy": "Waiting for accurate GPS signal…"})

        # 2. Check existing corners of the room (excluding this corner_index if we are overwriting it)
        existing_corners = room.corners.exclude(corner_index=corner_index)
        for ec in existing_corners:
            # Rounded check: round to 6 decimal places (~11 cm resolution)
            if round(ec.lat, 6) == round(lat, 6) and round(ec.lng, 6) == round(lng, 6):
                raise serializers.ValidationError({"corner_coordinates": "Move to a different physical corner before capturing."})

            # Distance check using haversine_distance
            d = haversine_distance(lat, lng, ec.lat, ec.lng)
            if d < 1.5:
                raise serializers.ValidationError({"corner_coordinates": "Move to a different physical corner before capturing."})

        return data

    def create(self, validated_data: dict) -> RoomCorner:
        room   = VirtualRoom.objects.get(id=validated_data["room_id"])
        corner, _ = RoomCorner.objects.update_or_create(
            room=room,
            corner_index=validated_data["corner_index"],
            defaults={
                "latitude":         validated_data["lat"],
                "longitude":        validated_data["lng"],
                "altitude":         validated_data["altitude"],
                "accuracy":         validated_data["accuracy"],
                "heading":          validated_data["heading"],
                "pitch":            validated_data.get("pitch", 0.0),
                "roll":             validated_data.get("roll",  0.0),
                "yaw":              validated_data.get("yaw",   0.0),
                "accelerometer":    validated_data.get("accelerometer"),
                "gyroscope":        validated_data.get("gyroscope"),
                "magnetic_field":   validated_data.get("magnetic_field"),
            },
        )
        # Auto-compute spatial vectors once all 4 corners are captured
        if room.corners.count() == 4:
            try:
                calculate_spatial_vectors(room)
            except Exception as exc:
                import logging
                logging.getLogger(__name__).error(
                    "calculate_spatial_vectors failed for room %s: %s", room.id, exc
                )
        return corner


# ─────────────────────────────────────────────────────────────────────────────
# Check-location request
# ─────────────────────────────────────────────────────────────────────────────

class CheckLocationSerializer(serializers.Serializer):
    lat          = serializers.FloatField(min_value=-90,  max_value=90)
    lng          = serializers.FloatField(min_value=-180, max_value=180)
    altitude     = serializers.FloatField()
    gps_accuracy = serializers.FloatField(default=10.0, min_value=0)
    sensors      = serializers.JSONField(required=False, allow_null=True)