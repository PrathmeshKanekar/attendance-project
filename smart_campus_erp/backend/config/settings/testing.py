from .base import *
import os

db_url = env('DATABASE_URL', default='postgres://avnadmin:password@localhost:5432/defaultdb')
if not ENABLE_GIS:
    db_url = db_url.replace('postgis://', 'postgres://')

DATABASES = {
    'default': env.db_url_config(db_url)
}
DATABASES['default']['ENGINE'] = 'django.contrib.gis.db.backends.postgis'


# Celery
CELERY_TASK_ALWAYS_EAGER = True
CELERY_TASK_EAGER_PROPAGATES = True

# Faster password hashing
PASSWORD_HASHERS = [
    'django.contrib.auth.hashers.MD5PasswordHasher',
]

# Email
EMAIL_BACKEND = 'django.core.mail.backends.locmem.EmailBackend'

# Media
DEFAULT_FILE_STORAGE = 'django.core.files.storage.FileSystemStorage'
MEDIA_ROOT = os.path.join(BASE_DIR, 'test_media')

# Disable security features that might interfere with tests
SECURE_SSL_REDIRECT = False
SESSION_COOKIE_SECURE = False
CSRF_COOKIE_SECURE = False

# Debugging
DEBUG = False
TEMPLATES[0]['OPTIONS']['debug'] = False
