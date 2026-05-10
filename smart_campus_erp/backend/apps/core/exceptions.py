from rest_framework.views import exception_handler
from rest_framework.response import Response
from rest_framework import status
import logging

logger = logging.getLogger(__name__)

def custom_exception_handler(exc, context):
    # Call DRF's default exception handler first
    response = exception_handler(exc, context)

    if response is not None:
        # Standardize error response
        custom_data = {
            'success': False,
            'error_code': exc.__class__.__name__,
            'message': str(exc.detail) if hasattr(exc, 'detail') else str(exc),
            'details': response.data
        }
        
        # If detail was a dict, it's already in details. 
        # If it was a string/list, we refine the message.
        if isinstance(response.data, dict) and 'detail' in response.data:
            custom_data['message'] = response.data['detail']
            
        response.data = custom_data
    else:
        # Handle non-DRF exceptions (500 errors)
        from django.db import OperationalError
        
        if isinstance(exc, OperationalError):
            logger.error(f"Database Connectivity Error: {exc}")
            return Response({
                'success': False,
                'error_code': 'DatabaseUnavailable',
                'message': 'The database is temporarily unavailable. Please try again in a few moments.',
                'details': {'exception_type': 'OperationalError'}
            }, status=status.HTTP_503_SERVICE_UNAVAILABLE)

        logger.error(f"Unhandled Exception: {exc}", exc_info=True)
        
        return Response({
            'success': False,
            'error_code': 'InternalServerError',
            'message': str(exc),
            'details': {
                'exception_type': exc.__class__.__name__,
            }
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    return response
