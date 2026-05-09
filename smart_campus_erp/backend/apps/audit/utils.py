from .models import AuditLog

def audit_action(user, action, resource_type, resource_id, request=None, extra={}):
    """
    Manual audit logging function for specific business events.
    """
    college = getattr(user, 'college', None) if user else None
    
    ip_address = None
    user_agent = ''
    device_id = ''
    
    if request:
        x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
        ip_address = x_forwarded_for.split(',')[0] if x_forwarded_for else request.META.get('REMOTE_ADDR')
        user_agent = request.META.get('HTTP_USER_AGENT', '')
        device_id = request.headers.get('X-Device-ID', '')

    return AuditLog.objects.create(
        college=college,
        user=user,
        action=action,
        resource_type=resource_type,
        resource_id=str(resource_id),
        ip_address=ip_address,
        user_agent=user_agent,
        device_id=device_id,
        request_data=extra
    )
