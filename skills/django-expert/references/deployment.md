# Django Deployment & Migrations Reference

## Table of Contents

1. [Gunicorn Configuration](#gunicorn-configuration)
2. [Docker Patterns](#docker-patterns)
3. [Safe Migrations](#safe-migrations)
4. [Health Checks](#health-checks)

---

## Gunicorn Configuration

### Production Config

```python
# gunicorn.conf.py
import multiprocessing

# Workers: 2-4 per CPU core
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "gthread"     # Thread-based for I/O-bound apps
threads = 4                  # Threads per worker
max_requests = 1000          # Restart workers after N requests (prevents memory leaks)
max_requests_jitter = 50     # Randomize restart to avoid thundering herd
timeout = 30                 # Kill worker if request takes > 30s
graceful_timeout = 10        # Time to finish ongoing requests on restart
keepalive = 5

# Logging
accesslog = "-"              # stdout
errorlog = "-"               # stderr
loglevel = "info"

# Security
limit_request_line = 8190
limit_request_fields = 100
```

```bash
# Run
gunicorn config.wsgi:application -c gunicorn.conf.py --bind 0.0.0.0:8000
```

### Key Decisions

| Setting | CPU-bound app | I/O-bound app |
|---------|--------------|---------------|
| `worker_class` | `sync` (default) | `gthread` or `gevent` |
| `workers` | `cpu_count * 2 + 1` | `cpu_count * 2 + 1` |
| `threads` | 1 | 2-4 |

---

## Docker Patterns

### Production Dockerfile

```dockerfile
# Multi-stage build
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev gcc && \
    rm -rf /var/lib/apt/lists/*

# Install Python deps (cached layer)
COPY requirements/production.txt requirements/base.txt ./requirements/
RUN pip install --no-cache-dir -r requirements/production.txt

# Copy app code
COPY . .
RUN python manage.py collectstatic --noinput

# Non-root user
RUN adduser --disabled-password --no-create-home appuser
USER appuser

EXPOSE 8000
CMD ["gunicorn", "config.wsgi:application", "-c", "gunicorn.conf.py", "--bind", "0.0.0.0:8000"]
```

### docker-compose.yml (development)

```yaml
services:
  web:
    build: .
    command: python manage.py runserver 0.0.0.0:8000
    volumes:
      - .:/app
    ports:
      - "8000:8000"
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER}"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

---

## Safe Migrations

### Zero-Downtime Migration Rules

1. **Never rename a column directly.** Instead: add new column -> backfill data -> update code -> drop old column.

2. **Never remove a column directly.** Instead: stop using it in code -> deploy -> remove column in next release.

3. **Add nullable columns first**, then backfill, then add NOT NULL:
```python
# Migration 1: Add nullable column
migrations.AddField(
    model_name='order',
    name='tracking_code',
    field=models.CharField(max_length=100, null=True),
)

# Migration 2: Backfill (data migration)
def backfill_tracking_code(apps, schema_editor):
    Order = apps.get_model('orders', 'Order')
    Order.objects.filter(tracking_code__isnull=True).update(tracking_code='')

migrations.RunPython(backfill_tracking_code, reverse_code=migrations.RunPython.noop)

# Migration 3: Add NOT NULL (only after backfill deployed)
migrations.AlterField(
    model_name='order',
    name='tracking_code',
    field=models.CharField(max_length=100, default=''),
)
```

4. **Add indexes CONCURRENTLY** in PostgreSQL (avoid table lock):
```python
from django.contrib.postgres.operations import AddIndexConcurrently

class Migration(migrations.Migration):
    atomic = False  # Required for CONCURRENTLY

    operations = [
        AddIndexConcurrently(
            model_name='order',
            index=models.Index(fields=['status', 'created_at'], name='idx_order_status_date'),
        ),
    ]
```

5. **Data migrations** — always provide `reverse_code`:
```python
def forward(apps, schema_editor):
    User = apps.get_model('accounts', 'User')
    User.objects.filter(role='').update(role='member')

def backward(apps, schema_editor):
    pass  # Or actual reverse logic

migrations.RunPython(forward, backward)
```

### Migration Checklist

- [ ] `python manage.py makemigrations --check` no CI (detect missing migrations)
- [ ] Migration tested with existing data (not just empty DB)
- [ ] No `RunSQL` without reverse SQL
- [ ] No table-locking operations on large tables during peak hours
- [ ] Backwards-compatible: old code works with new schema during deploy

---

## Health Checks

```python
# apps/core/views.py
from django.db import connection
from django.http import JsonResponse
from django.core.cache import cache


def health_check(request):
    """Lightweight health check for load balancer."""
    return JsonResponse({"status": "ok"})


def readiness_check(request):
    """Deep health check — verifies dependencies."""
    checks = {}

    # Database
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        checks["database"] = "ok"
    except Exception as e:
        checks["database"] = str(e)

    # Cache/Redis
    try:
        cache.set("health_check", "ok", timeout=5)
        checks["cache"] = "ok" if cache.get("health_check") == "ok" else "fail"
    except Exception as e:
        checks["cache"] = str(e)

    status_code = 200 if all(v == "ok" for v in checks.values()) else 503
    return JsonResponse(
        {"status": "ok" if status_code == 200 else "degraded", "checks": checks},
        status=status_code,
    )
```

```python
# config/urls.py — health checks OUTSIDE authentication
urlpatterns = [
    path("health/", health_check),
    path("ready/", readiness_check),
    # ...
]
```

**Important:** Health check endpoints must NOT require authentication and should NOT expose software versions or internal details.
