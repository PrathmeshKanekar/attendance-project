import uuid
from django.db import models
from django.conf import settings

class Department(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='departments')
    hod = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='hod_department')
    name = models.CharField(max_length=255)
    code = models.CharField(max_length=50)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('college', 'code')
        db_table = 'academic_department'

    def __str__(self):
        return f"{self.name} ({self.code})"

class Course(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='courses')
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name='courses')
    name = models.CharField(max_length=255)
    code = models.CharField(max_length=50)
    duration_years = models.IntegerField(default=4)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('college', 'code')
        db_table = 'academic_course'

    def __str__(self):
        return f"{self.name} ({self.code})"

class AcademicYear(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='academic_years')
    name = models.CharField(max_length=50) # e.g. 2025-2026
    start_date = models.DateField()
    end_date = models.DateField()
    is_current = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('college', 'name')
        db_table = 'academic_year'

    def save(self, *args, **kwargs):
        if self.is_current:
            # Unset other current years for this college
            AcademicYear.objects.filter(college=self.college, is_current=True).exclude(pk=self.pk).update(is_current=False)
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.name} ({self.college.name})"

class Division(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='divisions')
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='divisions')
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.CASCADE, related_name='divisions')
    name = models.CharField(max_length=20)
    year_of_study = models.IntegerField()
    class_coordinator = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='coordinating_divisions')
    capacity = models.IntegerField(default=60)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('course', 'academic_year', 'name', 'year_of_study')
        db_table = 'academic_division'

    def __str__(self):
        return f"{self.course.code} - {self.name} (Year {self.year_of_study})"

class Subject(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='subjects')
    department = models.ForeignKey(Department, on_delete=models.CASCADE, related_name='subjects')
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='subjects')
    name = models.CharField(max_length=255)
    code = models.CharField(max_length=50)
    year_of_study = models.IntegerField()
    semester = models.IntegerField()
    credits = models.IntegerField(default=4)
    is_lab = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('college', 'code')
        db_table = 'academic_subject'

    def __str__(self):
        return f"{self.name} ({self.code})"

class SubjectAllocation(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='subject_allocations')
    subject = models.ForeignKey(Subject, on_delete=models.CASCADE, related_name='allocations')
    teacher = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='subject_allocations')
    division = models.ForeignKey(Division, on_delete=models.CASCADE, related_name='subject_allocations')
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.CASCADE, related_name='allocations')
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('subject', 'teacher', 'division', 'academic_year')
        db_table = 'academic_subject_allocation'

    def __str__(self):
        return f"{self.subject.code} - {self.teacher} in {self.division}"

class Semester(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='semesters')
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='semesters')
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.CASCADE, related_name='semesters')
    semester_number = models.IntegerField()
    start_date = models.DateField()
    end_date = models.DateField()
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'academic_semester'

    def __str__(self):
        return f"Sem {self.semester_number} - {self.course.name}"

class Timetable(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    college = models.ForeignKey('tenants.College', on_delete=models.CASCADE, related_name='timetables')
    division = models.ForeignKey(Division, on_delete=models.CASCADE, related_name='timetable')
    subject_allocation = models.ForeignKey(SubjectAllocation, on_delete=models.CASCADE, related_name='timetable')
    day_of_week = models.IntegerField()
    start_time = models.TimeField()
    end_time = models.TimeField()
    room_number = models.CharField(max_length=50)
    is_active = models.BooleanField(default=True)
    effective_from = models.DateField()
    effective_to = models.DateField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'academic_timetable'

    def __str__(self):
        return f"{self.division.name} - Day {self.day_of_week}"

