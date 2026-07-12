# Django Security Reference

## Table of Contents

1. [OWASP Top 10 in Django Context](#owasp-top-10-in-django-context)
2. [Secure File Handling](#secure-file-handling)
3. [Rate Limiting & Abuse Prevention](#rate-limiting--abuse-prevention)
4. [Audit Logging](#audit-logging)
5. [Environment & Secrets Management](#environment--secrets-management)
6. [Security Headers & Middleware](#security-headers--middleware)

---

## OWASP Top 10 in Django Context

### A01: Broken Access Control

The #1 vulnerability. In Django/DRF projects, this usually means:

**IDOR (Insecure Direct Object Reference):**
```python
# VULNERABLE — any authenticated user can access any order by ID
class OrderViewSet(ModelViewSet):
    queryset = Order.objects.all()
    permission_classes = [IsAuthenticated]

# SECURE — users can only access their own orders
class OrderViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Order.objects.filter(user=self.request.user)
```

**Missing function-level access control:**
```python
# VULNERABLE — forgot to restrict admin-only endpoint
class UserViewSet(ModelViewSet):
    queryset = User.objects.all()
    # No permission_classes!

# SECURE
class UserViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated, IsAdminUser]

    def get_queryset(self):
        if self.request.user.is_staff:
            return User.objects.all()
        return User.objects.filter(pk=self.request.user.pk)
```

### A02: Cryptographic Failures

- Never store passwords in plain text. Django's `make_password()` / `check_password()` use PBKDF2 by default. Consider upgrading to Argon2:

```python
# settings/base.py
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.Argon2PasswordHasher",  # pip install argon2-cffi
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2SHA1PasswordHasher",
]
```

- Use `django.utils.crypto.get_random_string()` or `secrets.token_urlsafe()` for generating tokens.
- Never log sensitive data (passwords, tokens, PII).
- Use HTTPS everywhere in production.

### A03: Injection

**SQL Injection** — Django's ORM is safe by default, but watch for:
```python
# VULNERABLE
User.objects.raw(f"SELECT * FROM users WHERE name = '{name}'")
User.objects.extra(where=[f"name = '{name}'"])

# SAFE — parameterized
User.objects.raw("SELECT * FROM users WHERE name = %s", [name])
User.objects.filter(name=name)
```

**Command Injection** — avoid `os.system()` and `subprocess` with `shell=True`:
```python
# VULNERABLE
os.system(f"convert {user_filename} output.png")

# SAFE
import subprocess
subprocess.run(["convert", user_filename, "output.png"], check=True)
```

### A04: Insecure Design

- Implement rate limiting on authentication endpoints to prevent brute force.
- Use password validators:
```python
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator", "OPTIONS": {"min_length": 10}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]
```

### A05: Security Misconfiguration

Common Django misconfigurations:
- `DEBUG = True` in production
- `SECRET_KEY` hardcoded or committed to version control
- `ALLOWED_HOSTS = ["*"]`
- Default admin URL at `/admin/` (change it to something less guessable)
- Database credentials in settings files instead of environment variables

### A07: Cross-Site Scripting (XSS)

Django templates auto-escape by default. Danger points:
```python
# VULNERABLE — bypasses auto-escaping
{{ user_input|safe }}
{% autoescape off %}{{ user_input }}{% endautoescape %}
mark_safe(user_input)

# SAFE
{{ user_input }}  # Auto-escaped
mark_safe(bleach.clean(user_input))  # Sanitized first
```

For DRF API responses (JSON), XSS is less of a concern since browsers don't render JSON as HTML, but ensure `Content-Type: application/json` is always set (DRF handles this).

---

## Secure File Handling

```python
# settings/base.py
FILE_UPLOAD_MAX_MEMORY_SIZE = 5 * 1024 * 1024  # 5 MB
DATA_UPLOAD_MAX_MEMORY_SIZE = 5 * 1024 * 1024

# Validation in serializer
import os
from django.core.exceptions import ValidationError


def validate_file_extension(value):
    allowed = [".pdf", ".png", ".jpg", ".jpeg", ".doc", ".docx"]
    ext = os.path.splitext(value.name)[1].lower()
    if ext not in allowed:
        raise ValidationError(f"File type '{ext}' is not allowed.")


def validate_file_size(value):
    max_size = 10 * 1024 * 1024  # 10 MB
    if value.size > max_size:
        raise ValidationError(f"File size exceeds {max_size // (1024*1024)} MB limit.")


class DocumentSerializer(serializers.ModelSerializer):
    file = serializers.FileField(validators=[validate_file_extension, validate_file_size])
```

**Storage**: In production, use cloud storage (S3, GCS) via `django-storages`. Never serve uploaded files from the same domain as your application without proper configuration.

```python
# settings/production.py (S3 example)
DEFAULT_FILE_STORAGE = "storages.backends.s3boto3.S3Boto3Storage"
AWS_STORAGE_BUCKET_NAME = os.environ["AWS_STORAGE_BUCKET_NAME"]
AWS_S3_REGION_NAME = os.environ.get("AWS_S3_REGION_NAME", "us-east-1")
AWS_DEFAULT_ACL = "private"  # Don't make uploads public by default
AWS_S3_FILE_OVERWRITE = False
```

---

## Rate Limiting & Abuse Prevention

### DRF Throttling

```python
# Custom throttle for sensitive endpoints
from rest_framework.throttling import SimpleRateThrottle


class LoginRateThrottle(SimpleRateThrottle):
    scope = "login"

    def get_cache_key(self, request, view):
        # Throttle by IP for login attempts
        return self.cache_format % {
            "scope": self.scope,
            "ident": self.get_ident(request),
        }


class PasswordResetThrottle(SimpleRateThrottle):
    scope = "password_reset"

    def get_cache_key(self, request, view):
        return self.cache_format % {
            "scope": self.scope,
            "ident": self.get_ident(request),
        }
```

```python
# settings
REST_FRAMEWORK = {
    "DEFAULT_THROTTLE_RATES": {
        "login": "5/minute",
        "password_reset": "3/hour",
        "anon": "100/hour",
        "user": "1000/hour",
    },
}
```

---

## Audit Logging

For applications that handle sensitive data, track who did what:

```python
# apps/core/mixins.py
import logging

audit_logger = logging.getLogger("audit")


class AuditLogMixin:
    """Add to ViewSets to automatically log create/update/delete actions."""

    def perform_create(self, serializer):
        instance = serializer.save()
        audit_logger.info(
            "Object created",
            extra={
                "action": "create",
                "model": instance.__class__.__name__,
                "object_id": instance.pk,
                "user_id": self.request.user.id,
                "data": serializer.validated_data,
            },
        )

    def perform_update(self, serializer):
        instance = serializer.save()
        audit_logger.info(
            "Object updated",
            extra={
                "action": "update",
                "model": instance.__class__.__name__,
                "object_id": instance.pk,
                "user_id": self.request.user.id,
                "changed_fields": list(serializer.validated_data.keys()),
            },
        )

    def perform_destroy(self, instance):
        audit_logger.info(
            "Object deleted",
            extra={
                "action": "delete",
                "model": instance.__class__.__name__,
                "object_id": instance.pk,
                "user_id": self.request.user.id,
            },
        )
        instance.delete()
```

---

## Environment & Secrets Management

**Never commit secrets.** Use environment variables or a secrets manager.

```python
# Using django-environ
import environ

env = environ.Env()
environ.Env.read_env(os.path.join(BASE_DIR, ".env"))

SECRET_KEY = env("SECRET_KEY")
DEBUG = env.bool("DEBUG", default=False)
DATABASE_URL = env.db("DATABASE_URL")
```

`.env.example` (committed to repo as documentation):
```
SECRET_KEY=your-secret-key-here
DEBUG=True
DATABASE_URL=postgres://user:pass@localhost:5432/dbname
REDIS_URL=redis://localhost:6379/0
ALLOWED_HOSTS=localhost,127.0.0.1
CORS_ALLOWED_ORIGINS=http://localhost:3000
```

`.env` (never committed — in `.gitignore`):
```
SECRET_KEY=actual-secret-key
...
```

---

## Security Headers & Middleware

Ensure these middleware are in your production settings:

```python
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",  # Must be first (or after whitenoise)
    "corsheaders.middleware.CorsMiddleware",           # Before CommonMiddleware
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    # ...
]
```

The order matters. `SecurityMiddleware` handles HTTPS redirects and security headers. `CorsMiddleware` must come before anything that generates responses.
