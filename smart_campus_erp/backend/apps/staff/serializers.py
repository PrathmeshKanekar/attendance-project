from rest_framework import serializers
from .models import StaffProfile, ApprovalRequest

class StaffProfileSerializer(serializers.ModelSerializer):
    full_name = serializers.ReadOnlyField(source='user.get_full_name')
    email = serializers.ReadOnlyField(source='user.email')
    
    class Meta:
        model = StaffProfile
        fields = '__all__'

class UserSummarySerializer(serializers.Serializer):
    id = serializers.UUIDField()
    full_name = serializers.ReadOnlyField(source='get_full_name')
    email = serializers.EmailField()
    mobile = serializers.CharField()
    role = serializers.CharField()
    profile_photo_url = serializers.ImageField(source='profile_photo', read_only=True)
    department_name = serializers.SerializerMethodField()

    def get_department_name(self, obj):
        # Check if staff or student profile exists
        if hasattr(obj, 'staff_profile'):
            return obj.staff_profile.department.name if obj.staff_profile.department else "General"
        if hasattr(obj, 'student_profile'):
            return obj.student_profile.department.name if obj.student_profile.department else "General"
        return "N/A"

class ApprovalRequestSerializer(serializers.ModelSerializer):
    requested_user_details = UserSummarySerializer(source='requested_user', read_only=True)
    requested_by_name = serializers.ReadOnlyField(source='requested_by.get_full_name')
    reviewed_by_name = serializers.ReadOnlyField(source='reviewed_by.get_full_name')

    class Meta:
        model = ApprovalRequest
        fields = [
            'id', 'college', 'requested_user', 'requested_user_details', 
            'requested_by', 'requested_by_name', 'reviewed_by', 
            'reviewed_by_name', 'status', 'rejection_reason', 
            'created_at', 'reviewed_at'
        ]
        read_only_fields = ['status', 'reviewed_at', 'reviewed_by']
