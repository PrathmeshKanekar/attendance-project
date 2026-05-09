class CollegeScopedMixin:
    """
    Mixin to automatically filter querysets by the user's college.
    """
    def get_queryset(self):
        queryset = super().get_queryset()
        user = self.request.user
        
        if user.is_authenticated:
            if user.role == 'super_admin':
                return queryset
            if hasattr(user, 'college') and user.college:
                # Handle cases where the model has 'college' field
                return queryset.filter(college=user.college)
        
        return queryset.none()
