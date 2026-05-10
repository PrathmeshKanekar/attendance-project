from django.db import connection, OperationalError
import logging

logger = logging.getLogger(__name__)

class DatabaseConnectionMiddleware:
    """
    Middleware to handle stale database connections, especially useful for 
    cloud-hosted databases (like Aiven) that may drop idle connections.
    """
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        try:
            # Trigger a health check on the connection before starting the request
            # This is redundant if CONN_HEALTH_CHECKS is True, but provides extra 
            # safety for middleware that might run before Django's internal check.
            connection.ensure_connection()
        except OperationalError:
            logger.warning("Database connection health check failed. Attempting to close stale connection.")
            connection.close()
        
        response = self.get_response(request)
        return response

    def process_exception(self, request, exception):
        """
        Catch transient database errors and ensure the connection is closed 
        so the next request starts with a fresh connection.
        """
        if isinstance(exception, OperationalError):
            logger.error(f"Database OperationalError detected: {exception}. Closing connection.")
            connection.close()
        return None
