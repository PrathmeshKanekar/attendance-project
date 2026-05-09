from rest_framework import serializers
from .models import (
    Department, Course, AcademicYear,
    Division, Subject, SubjectAllocation,
)
from apps.students.models import StudentSubjectEnrollment


class DepartmentSerializer(serializers.ModelSerializer):
    hod_name = serializers.SerializerMethodField()

    class Meta:
        model  = Department
        fields = [
            'id', 'name', 'code', 'hod', 'hod_name',
            'is_active', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']

    def get_hod_name(self, obj):
        if obj.hod:
            return f'{obj.hod.first_name} {obj.hod.last_name}'
        return None

    def validate_code(self, value):
        return value.strip().upper()


class CourseSerializer(serializers.ModelSerializer):
    department_name = serializers.CharField(
        source='department.name', read_only=True
    )

    class Meta:
        model  = Course
        fields = [
            'id', 'name', 'code', 'department', 'department_name',
            'duration_years', 'is_active', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']

    def validate_code(self, value):
        return value.strip().upper()


class AcademicYearSerializer(serializers.ModelSerializer):
    class Meta:
        model  = AcademicYear
        fields = [
            'id', 'name', 'start_date', 'end_date',
            'is_current', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']


class DivisionSerializer(serializers.ModelSerializer):
    course_name      = serializers.CharField(source='course.name',      read_only=True)
    course_code      = serializers.CharField(source='course.code',      read_only=True)
    academic_year_name = serializers.CharField(source='academic_year.name', read_only=True)
    coordinator_name = serializers.SerializerMethodField()
    student_count    = serializers.SerializerMethodField()

    class Meta:
        model  = Division
        fields = [
            'id', 'name', 'year_of_study', 'course', 'course_name',
            'course_code', 'academic_year', 'academic_year_name',
            'class_coordinator', 'coordinator_name',
            'capacity', 'student_count', 'is_active',
            'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']

    def get_coordinator_name(self, obj):
        if obj.class_coordinator:
            return f'{obj.class_coordinator.first_name} {obj.class_coordinator.last_name}'
        return None

    def get_student_count(self, obj):
        from apps.students.models import StudentProfile
        return StudentProfile.objects.filter(
            division=obj, is_active=True
        ).count()


class SubjectSerializer(serializers.ModelSerializer):
    department_name = serializers.CharField(source='department.name', read_only=True)
    course_name     = serializers.CharField(source='course.name',     read_only=True)

    class Meta:
        model  = Subject
        fields = [
            'id', 'name', 'code', 'department', 'department_name',
            'course', 'course_name', 'year_of_study', 'semester',
            'credits', 'is_lab', 'is_active', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']

    def validate_code(self, value):
        return value.strip().upper()


class SubjectAllocationSerializer(serializers.ModelSerializer):
    subject_name    = serializers.CharField(source='subject.name',     read_only=True)
    subject_code    = serializers.CharField(source='subject.code',     read_only=True)
    teacher_name    = serializers.SerializerMethodField()
    teacher_email   = serializers.CharField(source='teacher.email',    read_only=True)
    division_name   = serializers.CharField(source='division.name',    read_only=True)
    division_year   = serializers.IntegerField(source='division.year_of_study', read_only=True)
    academic_year_name = serializers.CharField(source='academic_year.name', read_only=True)
    enrollment_count = serializers.SerializerMethodField()

    class Meta:
        model  = SubjectAllocation
        fields = [
            'id', 'subject', 'subject_name', 'subject_code',
            'teacher', 'teacher_name', 'teacher_email',
            'division', 'division_name', 'division_year',
            'academic_year', 'academic_year_name',
            'enrollment_count', 'is_active',
            'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']

    def get_teacher_name(self, obj):
        return f'{obj.teacher.first_name} {obj.teacher.last_name}'

    def get_enrollment_count(self, obj):
        from apps.students.models import StudentSubjectEnrollment
        return StudentSubjectEnrollment.objects.filter(
            subject_allocation=obj, is_active=True
        ).count()

    def validate_teacher(self, value):
        if value.role != 'teacher':
            raise serializers.ValidationError(
                'Selected user is not a teacher.'
            )
        return value


class BulkEnrollSerializer(serializers.Serializer):
    subject_allocation_id = serializers.UUIDField()
    student_ids           = serializers.ListField(
        child=serializers.UUIDField(),
        min_length=1,
    )
