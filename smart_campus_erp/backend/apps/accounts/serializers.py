from rest_framework import serializers
from django.contrib.auth import get_user_model
from apps.students.models import StudentProfile
from apps.approvals.models import ApprovalRequest

User = get_user_model()


class UserProfileSerializer(serializers.ModelSerializer):
    college_id   = serializers.SerializerMethodField()
    college_name = serializers.SerializerMethodField()
    college_code = serializers.SerializerMethodField()
    prn          = serializers.SerializerMethodField()
    full_name    = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'email', 'first_name', 'last_name', 'full_name',
            'role', 'phone', 'profile_photo',
            'college_id', 'college_name', 'college_code',
            'prn', 'device_id', 'is_approved', 'is_active',
        ]

    def get_college_id(self, obj):
        return str(obj.college.id) if obj.college else None

    def get_college_name(self, obj):
        return obj.college.name if obj.college else None

    def get_college_code(self, obj):
        return obj.college.code if obj.college else None

    def get_prn(self, obj):
        try:
            return obj.student_profile.prn
        except StudentProfile.DoesNotExist:
            return None

    def get_full_name(self, obj):
        return f'{obj.first_name} {obj.last_name}'


class CreateUserSerializer(serializers.ModelSerializer):
    password  = serializers.CharField(write_only=True, min_length=6)
    prn       = serializers.CharField(required=False, allow_blank=True)
    roll_number = serializers.CharField(required=False, allow_blank=True)
    year_of_study = serializers.IntegerField(required=False)
    division_id = serializers.UUIDField(required=False)

    class Meta:
        model = User
        fields = [
            'email', 'password', 'first_name', 'last_name',
            'phone', 'role',
            'prn', 'roll_number', 'year_of_study', 'division_id',
        ]

    def validate_role(self, value):
        allowed = [
            'college_admin', 'principal', 'hod',
            'teacher', 'student', 'lab_assistant',
        ]
        if value not in allowed:
            raise serializers.ValidationError(
                f'Role must be one of: {", ".join(allowed)}'
            )
        return value


class ApprovalRequestSerializer(serializers.ModelSerializer):
    user_name  = serializers.CharField(source='user.get_full_name', read_only=True)
    user_email = serializers.CharField(source='user.email', read_only=True)

    class Meta:
        model = ApprovalRequest
        fields = [
            'id', 'user', 'user_name', 'user_email',
            'requested_role', 'status', 'rejection_reason',
            'reviewed_by', 'reviewed_at', 'created_at',
        ]
        read_only_fields = [
            'id', 'status', 'reviewed_by', 'reviewed_at', 'created_at',
        ]


class PendingUserSerializer(serializers.ModelSerializer):
    college_name = serializers.CharField(source='college.name', read_only=True)
    full_name    = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'email', 'full_name', 'role', 'phone',
            'college_name', 'is_approved', 'is_active', 'created_at',
        ]

    def get_full_name(self, obj):
        return f'{obj.first_name} {obj.last_name}'
