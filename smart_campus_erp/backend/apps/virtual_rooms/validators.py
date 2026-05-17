from django.core.exceptions import ValidationError
from django.utils.translation import gettext_lazy as _

def validate_room_name(value):
    if len(value) < 3:
        raise ValidationError(
            _('%(value)s is too short for a room name'),
            params={'value': value},
        )

def validate_coordinate(value):
    if not (-180 <= value <= 180):
        raise ValidationError(
            _('%(value)s is not a valid coordinate'),
            params={'value': value},
        )
