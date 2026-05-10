from .base import *
from decouple import config

DEBUG = False

SECRET_KEY = config('SECRET_KEY')

ALLOWED_HOSTS = config('ALLOWED_HOSTS', default='').split(',')

# ── Database ───────────────────────────────────────────────
DATABASES = {
    'default': {
        'ENGINE'  : 'django.db.backends.postgresql',
        'NAME'    : config('DB_NAME'),
        'USER'    : config('DB_USER'),
        'PASSWORD': config('DB_PASSWORD'),
        'HOST'    : config('DB_HOST', default='localhost'),
        'PORT'    : config('DB_PORT', default='5432'),
        'OPTIONS' : {
            'connect_timeout': 10,
            'sslmode': 'require',
            # TCP Keepalives to prevent cloud database timeouts
            'keepalives': 1,
            'keepalives_idle': 60,
            'keepalives_interval': 10,
            'keepalives_count': 5,
        },
        'CONN_MAX_AGE': 600,
        'CONN_HEALTH_CHECKS': True,
    }
}

# ── Security ───────────────────────────────────────────────
SECURE_BROWSER_XSS_FILTER         = True
SECURE_CONTENT_TYPE_NOSNIFF       = True
X_FRAME_OPTIONS                   = 'DENY'
SECURE_HSTS_SECONDS               = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS    = True
SECURE_HSTS_PRELOAD               = True

# Only enable these if you have HTTPS configured
# SECURE_SSL_REDIRECT               = True
# SESSION_COOKIE_SECURE             = True
# CSRF_COOKIE_SECURE                = True

# ── CORS ──────────────────────────────────────────────────
CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOWED_ORIGINS   = config(
    'CORS_ALLOWED_ORIGINS',
    default='http://localhost',
).split(',')

# ── Static and Media files ─────────────────────────────────
STATIC_URL  = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
MEDIA_URL   = '/media/'
MEDIA_ROOT  = BASE_DIR / 'media'

# ── Logging ────────────────────────────────────────────────
LOGGING = {
    'version'                 : 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{levelname} {asctime} {module} {message}',
            'style' : '{',
        },
    },
    'handlers': {
        'file': {
            'level'    : 'ERROR',
            'class'    : 'logging.FileHandler',
            'filename' : BASE_DIR / 'logs' / 'django_errors.log',
            'formatter': 'verbose',
        },
        'console': {
            'level'    : 'INFO',
            'class'    : 'logging.StreamHandler',
            'formatter': 'verbose',
        },
    },
    'root': {
        'handlers': ['file', 'console'],
        'level'   : 'INFO',
    },
    'loggers': {
        'django': {
            'handlers'  : ['file'],
            'level'     : 'ERROR',
            'propagate' : False,
        },
    },
}

# ── Email (optional, for future use) ──────────────────────
EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'

# ── Cache ─────────────────────────────────────────────────
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
    }
}
