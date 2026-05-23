import os
import base64
import uuid
from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.db import transaction
from django.conf import settings
from django.core.files.base import ContentFile
from .models import StudentProfile, StudentSubjectEnrollment
from apps.face_recognition.models import FaceRegistrationImage, FaceDescriptor
from apps.face_recognition.face_utils import generate_embedding
from apps.tenants.models import College
from apps.academic.models import Division

User = get_user_model()

class StudentProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = StudentProfile
        fields = '__all__'

class StudentSubjectEnrollmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = StudentSubjectEnrollment
        fields = '__all__'

class StudentRegistrationSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)
    first_name = serializers.CharField()
    last_name = serializers.CharField()
    college_id = serializers.UUIDField()
    division_id = serializers.UUIDField()
    prn = serializers.CharField()
    roll_number = serializers.CharField()
    year_of_study = serializers.IntegerField()
    face_image_b64 = serializers.CharField(required=True)

    def validate_email(self, value):
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("A user with this email already exists.")
        return value

    def validate_prn(self, value):
        if StudentProfile.objects.filter(prn=value).exists():
            raise serializers.ValidationError("This PRN is already registered.")
        return value

    @transaction.atomic
    def create(self, validated_data):
        face_image_b64 = validated_data.pop('face_image_b64')
        college_id = validated_data.pop('college_id')
        division_id = validated_data.pop('division_id')
        password = validated_data.pop('password')

        try:
            college = College.objects.get(id=college_id)
            division = Division.objects.get(id=division_id)
        except (College.DoesNotExist, Division.DoesNotExist):
            raise serializers.ValidationError("Invalid college or division ID.")

        # Create User (Not approved, but is_active=True so they can exist)
        user = User.objects.create_user(
            email=validated_data['email'],
            password=password,
            first_name=validated_data['first_name'],
            last_name=validated_data['last_name'],
            role='student',
            college=college,
            is_active=True,
            is_approved=False
        )

        # Create Student Profile
        profile = StudentProfile.objects.create(
            user=user,
            college=college,
            division=division,
            prn=validated_data['prn'],
            roll_number=validated_data['roll_number'],
            year_of_study=validated_data['year_of_study'],
            approval_status='PENDING_APPROVAL',
            is_active=False
        )

        # ── Process and Save Face Image ───────────────────
        try:
            # Handle potential header in base64 string
            img_b64 = face_image_b64
            if "base64," in img_b64:
                img_b64 = img_b64.split("base64,")[1]
            
            image_data = base64.b64decode(img_b64)
            filename = f"registration_{profile.id}_{uuid.uuid4().hex[:8]}.jpg"
            
            # Ensure the directory exists
            face_dir = os.path.join(settings.MEDIA_ROOT, 'faces')
            if not os.path.exists(face_dir):
                os.makedirs(face_dir, exist_ok=True)
            
            file_path = os.path.join(face_dir, filename)
            with open(file_path, 'wb') as f:
                f.write(image_data)
            
            FaceRegistrationImage.objects.create(
                student=profile,
                image_path=f"faces/{filename}",
                angle='front'
            )
        except Exception as e:
            raise serializers.ValidationError({"face_image_b64": f"Error saving face image: {str(e)}"})

        # ── Generate Embedding & Create FaceDescriptor ────
        try:
            embedding = generate_embedding(img_b64)
            
            FaceDescriptor.objects.create(
                student=profile,
                embedding=embedding,
                model_used='DeepFace-Facenet',
            )
            
            profile.face_registered = True
            profile.save(update_fields=['face_registered'])
            
            # Confirm face profile exists in database before registration success response
            if not FaceDescriptor.objects.filter(student=profile).exists():
                raise serializers.ValidationError({"face_image_b64": "Face profile was not saved to database."})
                
        except ValueError as exc:
            raise serializers.ValidationError({"face_image_b64": f"Biometric processing failed: {str(exc)}"})
        except Exception as exc:
            raise serializers.ValidationError({"face_image_b64": f"Failed to generate face biometric profile: {str(exc)}"})

        return profile


class LabAssistantPendingStudentSerializer(serializers.ModelSerializer):
    full_name = serializers.SerializerMethodField()
    email = serializers.EmailField(source='user.email')
    phone = serializers.CharField(source='user.phone', default='')
    college_code = serializers.CharField(source='college.code')
    course_name = serializers.CharField(source='course.name', default='')
    division_name = serializers.CharField(source='division.name', default='')
    face_enrollment_status = serializers.SerializerMethodField()
    device_status = serializers.SerializerMethodField()
    student_photo = serializers.SerializerMethodField()

    class Meta:
        model = StudentProfile
        fields = [
            'id', 'full_name', 'email', 'phone', 'college_code', 
            'course_name', 'division_name', 'prn', 'roll_number', 
            'year_of_study', 'created_at', 'face_enrollment_status', 
            'device_status', 'student_photo', 'approval_status', 
            'rejection_reason'
        ]

    def get_full_name(self, obj):
        return f"{obj.user.first_name} {obj.user.last_name}".strip()

    def get_face_enrollment_status(self, obj):
        from apps.face_recognition.models import FaceDescriptor
        return FaceDescriptor.objects.filter(student=obj).exists()

    def get_device_status(self, obj):
        from apps.accounts.models import DeviceRegistry
        return DeviceRegistry.objects.filter(user=obj.user, is_active=True).exists()

    def get_student_photo(self, obj):
        from apps.face_recognition.models import FaceRegistrationImage
        img = FaceRegistrationImage.objects.filter(student=obj, angle='front').first()
        if img and img.image_path:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(settings.MEDIA_URL + img.image_path)
            return settings.MEDIA_URL + img.image_path
        return None
