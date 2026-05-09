from rest_framework import serializers
from .models import FaceDescriptor

class FaceDescriptorSerializer(serializers.ModelSerializer):
    student_name  = serializers.SerializerMethodField()
    student_prn   = serializers.SerializerMethodField()
    registered_by_name = serializers.SerializerMethodField()

    class Meta:
        model  = FaceDescriptor
        fields = [
            'id', 'student', 'student_name', 'student_prn',
            'model_used', 'registered_by', 'registered_by_name',
            'registered_at', 'updated_at',
        ]
        read_only_fields = ['id', 'registered_at', 'updated_at']

    def get_student_name(self, obj):
        return obj.student.user.get_full_name()

    def get_student_prn(self, obj):
        return obj.student.prn

    def get_registered_by_name(self, obj):
        if obj.registered_by:
            return obj.registered_by.get_full_name()
        return None


class FaceRegisterInputSerializer(serializers.Serializer):
    student_id    = serializers.UUIDField()
    face_image_b64 = serializers.CharField()

    def validate_face_image_b64(self, value):
        if not value or len(value) < 100:
            raise serializers.ValidationError(
                'face_image_b64 is too short. Provide a valid base64 image.'
            )
        return value


class FaceVerifyInputSerializer(serializers.Serializer):
    student_id    = serializers.UUIDField(required=False)
    face_image_b64 = serializers.CharField()
