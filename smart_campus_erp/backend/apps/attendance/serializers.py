from rest_framework import serializers
from .models import AttendanceSession, AttendanceLog


class AttendanceSessionSerializer(serializers.ModelSerializer):
    subject_name   = serializers.CharField(
        source='subject_allocation.subject.name', read_only=True
    )
    subject_code   = serializers.CharField(
        source='subject_allocation.subject.code', read_only=True
    )
    teacher_name   = serializers.SerializerMethodField()
    division_name  = serializers.CharField(
        source='subject_allocation.division.name', read_only=True
    )
    division_year  = serializers.IntegerField(
        source='subject_allocation.division.year_of_study', read_only=True
    )
    room_name      = serializers.SerializerMethodField()

    class Meta:
        model  = AttendanceSession
        fields = [
            'id', 'session_code', 'status',
            'subject_name', 'subject_code',
            'teacher_name', 'division_name', 'division_year',
            'room_name',
            'scheduled_start', 'scheduled_end',
            'actual_start', 'actual_end',
            'total_students', 'present_count',
            'teacher_lat', 'teacher_lng', 'teacher_altitude', 'teacher_accuracy',
            'radius_meters', 'created_at',
        ]
        read_only_fields = [
            'id', 'session_code', 'present_count',
            'actual_start', 'actual_end', 'created_at',
        ]

    def get_teacher_name(self, obj):
        if not obj.teacher:
            return None
        return obj.teacher.get_full_name()

    def get_room_name(self, obj):
        return obj.virtual_room.name if obj.virtual_room else None


class AttendanceLogSerializer(serializers.ModelSerializer):
    student_name = serializers.SerializerMethodField()
    student_prn  = serializers.SerializerMethodField()
    teacher_name = serializers.CharField(source='session.teacher.get_full_name', read_only=True)
    subject_name = serializers.CharField(source='session.subject_allocation.subject.name', read_only=True)
    division_name = serializers.CharField(source='session.subject_allocation.division.name', read_only=True)
    year_of_study = serializers.IntegerField(source='session.subject_allocation.division.year_of_study', read_only=True)

    class Meta:
        model  = AttendanceLog
        fields = [
            'id', 'student', 'student_name', 'student_prn',
            'teacher_name', 'subject_name', 'division_name', 'year_of_study',
            'status', 'marked_at',
            'is_verified_gps', 'is_verified_face',
            'face_confidence', 'blink_count',
            'manual_reason', 'marked_by',
        ]

    def get_student_name(self, obj):
        if not obj.student:
            return None
        return obj.student.get_full_name()

    def get_student_prn(self, obj):
        try:
            return obj.student.student_profile.prn
        except Exception:
            return None


class CreateSessionSerializer(serializers.Serializer):
    subject_allocation_id = serializers.UUIDField()
    virtual_room_id       = serializers.UUIDField()
    scheduled_start       = serializers.DateTimeField()
    scheduled_end         = serializers.DateTimeField()
    teacher_lat           = serializers.DecimalField(
        max_digits=10, decimal_places=7, min_value=-90, max_value=90
    )
    teacher_lng           = serializers.DecimalField(
        max_digits=10, decimal_places=7, min_value=-180, max_value=180
    )
    teacher_altitude      = serializers.FloatField(default=0.0, min_value=-100, max_value=9000)
    teacher_accuracy      = serializers.FloatField(default=10.0, min_value=0, max_value=1000)
    radius_meters         = serializers.FloatField(default=30.0, min_value=5, max_value=150)

    def validate(self, data):
        if data['scheduled_end'] <= data['scheduled_start']:
            raise serializers.ValidationError({
                'scheduled_end': 'Session end must be after start.'
            })
        
        import re
        # Check for duration (min 15 mins, max 6 hours)
        delta = data['scheduled_end'] - data['scheduled_start']
        if delta.total_seconds() < 900:
            raise serializers.ValidationError('Session must be at least 15 minutes.')
        if delta.total_seconds() > 21600:
            raise serializers.ValidationError('Session cannot exceed 6 hours.')
            
        return data


class MarkAttendanceSerializer(serializers.Serializer):
    session_id     = serializers.UUIDField()
    lat            = serializers.FloatField(min_value=-90, max_value=90)
    lng            = serializers.FloatField(min_value=-180, max_value=180)
    altitude       = serializers.FloatField(default=0.0, min_value=-100, max_value=9000)
    accuracy       = serializers.FloatField(default=10.0, min_value=0, max_value=500)
    device_id      = serializers.CharField(max_length=255)
    face_image_b64    = serializers.CharField()
    blink_count       = serializers.IntegerField(min_value=3)
    is_mocked         = serializers.BooleanField(required=False, default=False)
    compass_direction = serializers.FloatField(required=False, default=0.0, min_value=0, max_value=360)
    device_movement   = serializers.CharField(required=False, allow_blank=True, default='', max_length=1000)

    def validate_face_image_b64(self, value):
        if not value or len(value) < 1000: # Base64 for a real image is usually large
            raise serializers.ValidationError(
                'Invalid face image. Please retake the photo.'
            )
        # Check for base64 prefix if present
        if ',' in value:
            val = value.split(',')[1]
        else:
            val = value
            
        import base64
        try:
            base64.b64decode(val[:100], validate=True)
        except Exception:
            raise serializers.ValidationError('Invalid base64 encoding.')
            
        return value

    def validate_device_id(self, value):
        if not value:
            raise serializers.ValidationError('Device ID cannot be empty.')
        
        # Trim leading and trailing whitespace
        val = value.strip()
        
        import re
        # Allow alphanumeric, hyphen, underscore, colon, slash, dot, equals, spaces, and braces
        # Format: e.g. UUIDs, Android Build IDs, iOS IDFVs, Web hash/string
        if not re.match(r'^[a-zA-Z0-9\-\:_/\.={}\[\] ]{5,255}$', val):
            raise serializers.ValidationError('Invalid device identifier format.')
        
        from apps.accounts.models import normalize_device_id
        return normalize_device_id(val)


class CheckLocationSerializer(serializers.Serializer):
    session_id = serializers.UUIDField()
    lat        = serializers.FloatField(min_value=-90, max_value=90)
    lng        = serializers.FloatField(min_value=-180, max_value=180)
    altitude   = serializers.FloatField(default=0.0, min_value=-100, max_value=9000)
    accuracy   = serializers.FloatField(default=10.0, min_value=0, max_value=500)
    is_mocked  = serializers.BooleanField(required=False, default=False)
    sensors    = serializers.JSONField(required=False, default=dict)


class ManualAttendanceSerializer(serializers.Serializer):
    session_id = serializers.UUIDField()
    student_id = serializers.UUIDField()
    reason     = serializers.CharField(min_length=5, max_length=500)

    def validate_reason(self, value):
        import re
        # Prevent SQL injection symbols and excessive spaces
        val = re.sub(r'\s+', ' ', value).strip()
        forbidden = [';', '--', '/*', '*/', '<', '>', 'xp_']
        for char in forbidden:
            if char in val:
                raise serializers.ValidationError(f'Character "{char}" not allowed.')
        return val
