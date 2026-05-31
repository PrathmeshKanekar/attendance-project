from rest_framework import serializers
from .models import StaffProfile

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

