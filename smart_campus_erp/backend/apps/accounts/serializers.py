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
    password  = serializers.CharField(
        write_only=True, 
        min_length=8,
        error_messages={
            'min_length': 'Password must be at least 8 characters long.',
        }
    )
    prn       = serializers.CharField(required=False, allow_blank=True, max_length=50)
    roll_number = serializers.CharField(required=False, allow_blank=True, max_length=20)
    year_of_study = serializers.IntegerField(required=False, min_value=1, max_value=10)
    division_id = serializers.UUIDField(required=False)

    class Meta:
        model = User
        fields = [
            'email', 'password', 'first_name', 'last_name',
            'phone', 'role',
            'prn', 'roll_number', 'year_of_study', 'division_id',
        ]

    def _sanitize_string(self, value):
        if value:
            # Remove multiple spaces and strip
            import re
            value = re.sub(r'\s+', ' ', value).strip()
            # Prevent SQL/Script injection symbols
            forbidden = ['<', '>', ';', '--', '/*', '*/', 'xp_']
            for char in forbidden:
                if char in value:
                    raise serializers.ValidationError(f'Character "{char}" is not allowed.')
        return value

    def validate_first_name(self, value):
        val = self._sanitize_string(value)
        if not val:
            raise serializers.ValidationError('First name cannot be empty.')
        if len(val) < 2:
            raise serializers.ValidationError('First name is too short.')
        return val

    def validate_last_name(self, value):
        val = self._sanitize_string(value)
        if not val:
            raise serializers.ValidationError('Last name cannot be empty.')
        return val

    def validate_email(self, value):
        import re
        val = value.strip().lower()
        email_regex = r'^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'
        if not re.match(email_regex, val):
            raise serializers.ValidationError('Invalid email format.')
        if User.objects.filter(email=val).exists():
            raise serializers.ValidationError('A user with this email already exists.')
        return val

    def validate_phone(self, value):
        if value:
            import re
            # Only digits allowed (plus optional + at start)
            val = value.strip().replace(' ', '')
            phone_regex = r'^\+?\d{10,15}$'
            if not re.match(phone_regex, val):
                raise serializers.ValidationError('Phone must be 10-15 digits only.')
            return val
        return value

    def validate_password(self, value):
        import re
        if not re.search(r'[A-Z]', value):
            raise serializers.ValidationError('Password must contain at least one uppercase letter.')
        if not re.search(r'[a-z]', value):
            raise serializers.ValidationError('Password must contain at least one lowercase letter.')
        if not re.search(r'\d', value):
            raise serializers.ValidationError('Password must contain at least one digit.')
        if not re.search(r'[!@#$%^&*(),.?":{}|<>]', value):
            raise serializers.ValidationError('Password must contain at least one special character.')
        return value

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

    def validate(self, data):
        role = data.get('role')
        if role == 'student':
            # Check PRN and Roll Number
            if not data.get('prn'):
                raise serializers.ValidationError({'prn': 'PRN is required for students.'})
            if not data.get('roll_number'):
                raise serializers.ValidationError({'roll_number': 'Roll number is required for students.'})
            if not data.get('division_id'):
                raise serializers.ValidationError({'division_id': 'Division is required for students.'})
            
            # Sanitize them
            data['prn'] = self._sanitize_string(data.get('prn', ''))
            data['roll_number'] = self._sanitize_string(data.get('roll_number', ''))
            
        return data


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
            'id', 'email', 'first_name', 'last_name', 'full_name', 
            'role', 'phone', 'college_name', 'is_approved', 
            'is_active', 'created_at',
        ]

    def get_full_name(self, obj):
        return f'{obj.first_name} {obj.last_name}'
