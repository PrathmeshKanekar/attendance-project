import json
import logging
from django.utils.deprecation import MiddlewareMixin
from .models import AuditLog

logger = logging.getLogger(__name__)

class AuditMiddleware(MiddlewareMixin):
    def process_response(self, request, response):
        # Skip GET requests and specific paths
        if request.method == 'GET':
            return response
            
        path = request.path
        if any(p in path for p in ['/api/docs/', '/admin/static/', '/favicon.ico']):
            return response

        # Only audit authenticated users or login attempts
        user = request.user if request.user.is_authenticated else None
        college = getattr(user, 'college', None) if user else None

        # Sanitize sensitive data
        request_data = {}
        if request.method in ['POST', 'PUT', 'PATCH']:
            try:
                if request.content_type == 'application/json':
                    request_data = json.loads(request.body.decode('utf-8'))
                else:
                    request_data = request.POST.dict()
                
                # Sanitize
                sensitive_keys = ['password', 'token', 'otp', 'secret', 'access', 'refresh']
                for key in list(request_data.keys()):
                    if any(s in key.lower() for s in sensitive_keys):
                        request_data[key] = '********'
            except Exception:
                request_data = {'error': 'Could not parse request body'}

        # Extract action from path
        # e.g. /api/v1/attendance/mark/ -> attendance.mark
        action = path.strip('/').replace('/api/v1/', '').replace('/', '.')

        try:
            AuditLog.objects.create(
                college=college,
                user=user,
                action=action,
                resource_type='APIRequest',
                resource_id=path,
                ip_address=self._get_client_ip(request),
                device_id=request.headers.get('X-Device-ID', ''),
                user_agent=request.META.get('HTTP_USER_AGENT', ''),
                request_data=request_data,
                response_status=response.status_code
            )
        except Exception as e:
            logger.error(f"Audit Log creation failed: {e}")

        return response

    def _get_client_ip(self, request):
        x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
        if x_forwarded_for:
            ip = x_forwarded_for.split(',')[0]
        else:
            ip = request.META.get('REMOTE_ADDR')
        return ip
