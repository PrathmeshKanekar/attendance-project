from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.db import transaction
from .models import StudentProfile, StudentSubjectEnrollment
from apps.face_recognition.models import FaceRegistrationImage
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

        # Create User (Inactive and Unapproved)
        user = User.objects.create_user(
            email=validated_data['email'],
            password=password,
            first_name=validated_data['first_name'],
            last_name=validated_data['last_name'],
            role='student',
            college=college,
            is_active=False,
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
            is_active=False
        )

        # ── Process and Save Face Image ───────────────────
        import base64
        from django.core.files.base import ContentFile
        import uuid

        try:
            # Handle potential header in base64 string
            if "base64," in face_image_b64:
                face_image_b64 = face_image_b64.split("base64,")[1]
            
            format, imgstr = face_image_b64.split(';base64,') if ';base64,' in face_image_b64 else (None, face_image_b64)
            ext = 'jpg' # Default extension
            
            image_data = base64.b64decode(imgstr)
            filename = f"registration_{profile.id}_{uuid.uuid4().hex[:8]}.jpg"
            
            # Save to FaceRegistrationImage
            # Note: Since image_path is a CharField in the model, we save the relative path
            # We'll assume a 'faces/' subdirectory in MEDIA_ROOT
            face_dir = os.path.join(settings.MEDIA_ROOT, 'faces')
            if not os.path.exists(face_dir):
                os.makedirs(face_dir)
            
            file_path = os.path.join(face_dir, filename)
            with open(file_path, 'wb') as f:
                f.write(image_data)
            
            FaceRegistrationImage.objects.create(
                student=profile,
                image_path=f"faces/{filename}",
                angle='front'
            )
        except Exception as e:
            # Log error but don't fail registration
            print(f"Error saving face image: {e}")
            # Fallback placeholder
            FaceRegistrationImage.objects.create(
                student=profile,
                image_path=f"faces/placeholder.jpg",
                angle='front'
            )

        return profile
