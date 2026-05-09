from django_filters import rest_framework as filters
from .models import StudentProfile

class StudentFilter(filters.FilterSet):
    has_low_attendance = filters.BooleanFilter(method='filter_low_attendance')
    
    class Meta:
        model = StudentProfile
        fields = ['department', 'course', 'division', 'batch_year', 'is_active']

    def filter_low_attendance(self, queryset, name, value):
        if value:
            # Placeholder for attendance logic when attendance app is ready
            # Should filter students where overall attendance < threshold
            return queryset
        return queryset
