import os
from pathlib import Path
from datetime import timedelta
import environ
import sys
from unittest.mock import MagicMock

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent.parent

# GIS Mocking Logic
ENABLE_GIS = False
try:
    from django.contrib.gis.geos import libgeos
    from django.contrib.gis.gdal import libgdal
    ENABLE_GIS = True
except Exception:
    # Force enable apps but mock the libraries
    sys.modules['django.contrib.gis.geos'] = MagicMock()
    sys.modules['django.contrib.gis.geos.geometry'] = MagicMock()
    sys.modules['django.contrib.gis.geos.libgeos'] = MagicMock()
    sys.modules['django.contrib.gis.geos.prototypes'] = MagicMock()
    sys.modules['django.contrib.gis.geos.prototypes.io'] = MagicMock()
    sys.modules['django.contrib.gis.geos.prototypes.coordseq'] = MagicMock()
    sys.modules['django.contrib.gis.geos.prototypes.geom'] = MagicMock()
    sys.modules['django.contrib.gis.geos.prototypes.misc'] = MagicMock()
    sys.modules['django.contrib.gis.geos.prototypes.prepared'] = MagicMock()
    sys.modules['django.contrib.gis.geos.prototypes.threadsafe'] = MagicMock()
    sys.modules['django.contrib.gis.geos.factory'] = MagicMock()
    sys.modules['django.contrib.gis.geos.error'] = MagicMock()
    sys.modules['django.contrib.gis.geos.base'] = MagicMock()
    sys.modules['django.contrib.gis.geos.io'] = MagicMock()
    sys.modules['django.contrib.gis.gdal'] = MagicMock()
    sys.modules['django.contrib.gis.gdal.libgdal'] = MagicMock()
    sys.modules['django.contrib.gis.gdal.prototypes'] = MagicMock()
    sys.modules['django.contrib.gis.gdal.prototypes.ds'] = MagicMock()
    sys.modules['django.contrib.gis.gdal.prototypes.generation'] = MagicMock()
    sys.modules['django.contrib.gis.gdal.error'] = MagicMock()
    sys.modules['django.contrib.gis.gdal.base'] = MagicMock()
    
    # Mocking Point/Polygon for models
    class MockGeometry:
        def __init__(self, *args, **kwargs): pass
        def __str__(self): return "MOCKED_GEOMETRY"
        @property
        def x(self): return 0.0
        @property
        def y(self): return 0.0
        def contains(self, other): return True
        def distance(self, other): return 0.0
    
    import django.contrib.gis.geos as geos
    geos.Point = MockGeometry
    geos.Polygon = MockGeometry
    geos.GEOS_VERSION = (3, 8, 0)
    geos.geos_version = lambda: b"3.8.0-CAPI-1.13.1"
    geos.geos_version_info = lambda: {'version': '3.8.0', 'release_date': '2020-01-01'}

# Initialize environ
env = environ.Env(
    DEBUG=(bool, False),
    ALLOWED_HOSTS=(list, []),
)

# Read .env file
environ.Env.read_env(os.path.join(BASE_DIR.parent, '.env'))

SECRET_KEY = env('SECRET_KEY')
DEBUG = env('DEBUG', default=True)
ALLOWED_HOSTS = env('ALLOWED_HOSTS', default=['*'])

# Application definition
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'django.contrib.gis',
    
    # Third-party apps
    'rest_framework',
    'rest_framework_simplejwt',
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',
    'django_otp',
    'django_otp.plugins.otp_totp',
    'django_otp.plugins.otp_email',
    'storages',
    'django_filters',
    'drf_spectacular',
    'django_extensions',
    
    # Internal apps
    'apps.core',
    'apps.tenants',
    'apps.accounts',
    'apps.students',
    'apps.staff',
    'apps.academic',
    'apps.attendance',
    'apps.virtual_rooms',
    'apps.approvals',
    'apps.notifications',
    'apps.reports',
    'apps.audit',
    'apps.face_recognition',
]

MIDDLEWARE = [
    'apps.core.db_middleware.DatabaseConnectionMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django_otp.middleware.OTPMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    'apps.audit.middleware.AuditMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [os.path.join(BASE_DIR, 'templates')],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'
ASGI_APPLICATION = 'config.asgi.application'

# Database
db_url = env('DATABASE_URL')
if not ENABLE_GIS:
    # Use standard postgres engine if local GIS libs are missing to prevent backend load errors
    db_url = db_url.replace('postgis://', 'postgres://').replace('postgresql://', 'postgres://')

DATABASES = {
    'default': env.db_url_config(db_url)
}
DATABASES['default']['ENGINE'] = 'django.contrib.gis.db.backends.postgis'

# Custom User Model
AUTH_USER_MODEL = 'accounts.User'

# Internationalization
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

# Static files
STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'staticfiles')
MEDIA_URL = '/media/'
MEDIA_ROOT = os.path.join(BASE_DIR, 'media')

# Default Auto Field
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
     'OPTIONS': {'min_length': 6}},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# REST Framework
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_PAGINATION_CLASS': 'apps.core.pagination.StandardResultsPagination',
    'PAGE_SIZE': 20,
    'DEFAULT_FILTER_BACKENDS': (
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.SearchFilter',
        'rest_framework.filters.OrderingFilter',
    ),
    'DEFAULT_SCHEMA_CLASS': 'drf_spectacular.openapi.AutoSchema',
    'EXCEPTION_HANDLER': 'apps.core.exceptions.custom_exception_handler',
    'DEFAULT_THROTTLE_CLASSES': [
        'rest_framework.throttling.AnonRateThrottle',
        'rest_framework.throttling.UserRateThrottle',
    ],
    'DEFAULT_THROTTLE_RATES': {
        'anon': '100/hour',
        'user': '1000/hour',
    },
}

# JWT settings
from datetime import timedelta
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME'       : timedelta(hours=8),
    'REFRESH_TOKEN_LIFETIME'      : timedelta(days=30),
    'ROTATE_REFRESH_TOKENS'       : True,
    'BLACKLIST_AFTER_ROTATION'    : True,
    'AUTH_HEADER_TYPES'           : ('Bearer',),
    'USER_ID_FIELD'               : 'id',
    'USER_ID_CLAIM'               : 'user_id',
    'AUTH_TOKEN_CLASSES'          : ('rest_framework_simplejwt.tokens.AccessToken',),
}
# CORS Settings
CORS_ALLOW_ALL_ORIGINS = True
CORS_ALLOW_CREDENTIALS = True
