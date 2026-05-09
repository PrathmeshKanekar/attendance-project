from django.apps import AppConfig
from django.db import connection

class CoreConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.core'

    def ready(self):
        # HACK: Enable geo_db_type fallback if spatial engine isn't fully loaded
        # This allows migrations with PointField to pass on standard PostgreSQL backends
        if not hasattr(connection.ops, 'geo_db_type'):
            try:
                connection.ops.geo_db_type = lambda x: 'GEOMETRY'
            except Exception:
                pass
