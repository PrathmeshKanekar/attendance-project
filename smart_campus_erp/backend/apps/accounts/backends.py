from django.contrib.auth.backends import ModelBackend
from .models import User

class PRNAuthBackend(ModelBackend):
    """
    Authenticate against the PRN number.
    """
    def authenticate(self, request, username=None, password=None, **kwargs):
        prn = kwargs.get('prn') or username
        try:
            user = User.objects.get(prn=prn)
            if user.check_password(password):
                return user
        except User.DoesNotExist:
            return None
        return None
