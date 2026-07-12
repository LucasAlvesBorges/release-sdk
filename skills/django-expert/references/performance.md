# Django Performance Reference

## Table of Contents

1. [ORM Query Optimization](#orm-query-optimization)
2. [Caching Strategies](#caching-strategies)
3. [Database Tuning](#database-tuning)
4. [Async Views & Background Tasks](#async-views--background-tasks)
5. [Serialization Performance](#serialization-performance)

---

## ORM Query Optimization

### Diagnosing N+1 Queries

Use `django-debug-toolbar` in development or add query logging:

```python
# settings/development.py
LOGGING = {
    "version": 1,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "loggers": {
        "django.db.backends": {
            "level": "DEBUG",
            "handlers": ["console"],
        },
    },
}
```

Or use `assertNumQueries` in tests:
```python
def test_order_list_queries(self):
    OrderFactory.create_batch(10)
    with self.assertNumQueries(2):  # 1 for orders + 1 for prefetch
        response = self.client.get("/api/v1/orders/")
```

### Advanced Prefetch Patterns

**Chained prefetches** for deeply nested data:
```python
queryset = (
    User.objects
    .prefetch_related(
        "orders",
        "orders__items",
        "orders__items__product",
        "orders__items__product__category",
    )
)
```

**Prefetch with aggregation** — avoid the temptation to compute in Python:
```python
from django.db.models import Count, Sum, Avg, Q

orders = (
    Order.objects
    .annotate(
        item_count=Count("items"),
        total_revenue=Sum("items__price"),
        pending_items=Count("items", filter=Q(items__status="pending")),
    )
    .select_related("user")
)
```

**Subqueries** for complex lookups:
```python
from django.db.models import Subquery, OuterRef

latest_order = (
    Order.objects
    .filter(user=OuterRef("pk"))
    .order_by("-created_at")
    .values("created_at")[:1]
)

users = User.objects.annotate(
    last_order_date=Subquery(latest_order)
)
```

### QuerySet Methods Performance

| Method | Use When | Avoid When |
|--------|----------|------------|
| `.values()` / `.values_list()` | You only need specific columns | You need model instances |
| `.only()` | You need model instances but not all fields | The excluded fields are accessed later |
| `.defer()` | You want all fields except a few heavy ones | The deferred fields are frequently accessed |
| `.exists()` | You only check if something exists | You also need the data |
| `.count()` | You need the total count | You also need the records |
| `.iterator()` | Processing large querysets row by row | You need to access the data multiple times |
| `bulk_create()` | Inserting many records | You need signals to fire |
| `bulk_update()` | Updating many records | You need signals or per-object logic |

### Avoiding Common Traps

**Evaluating querysets multiple times:**
```python
# BAD — hits the database twice
if queryset.count() > 0:
    items = list(queryset)

# GOOD — single database hit
items = list(queryset)
if items:
    ...
```

**Using `.all()` when you don't need everything:**
```python
# BAD — loads all fields of all records
users = User.objects.all()
names = [u.username for u in users]

# GOOD
names = list(User.objects.values_list("username", flat=True))
```

---

## Caching Strategies

### Cache Hierarchy

From fastest to slowest: Local memory → Redis → Database → Recompute

**Per-view caching** (for views that rarely change):
```python
from django.views.decorators.cache import cache_page
from django.utils.decorators import method_decorator

class PublicProductViewSet(ReadOnlyModelViewSet):
    @method_decorator(cache_page(60 * 15))  # 15 minutes
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)
```

**Fragment caching** (for expensive computations):
```python
from django.core.cache import cache

def get_dashboard_stats(user_id):
    cache_key = f"dashboard_stats_{user_id}"
    stats = cache.get(cache_key)
    if stats is None:
        stats = _compute_expensive_stats(user_id)
        cache.set(cache_key, stats, timeout=60 * 5)  # 5 minutes
    return stats
```

**Cache invalidation** — the hard part. Use signals judiciously:
```python
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver

@receiver([post_save, post_delete], sender=Order)
def invalidate_dashboard_cache(sender, instance, **kwargs):
    cache_key = f"dashboard_stats_{instance.user_id}"
    cache.delete(cache_key)
```

### Redis Configuration

```python
# settings/base.py
CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": os.environ.get("REDIS_URL", "redis://localhost:6379/0"),
        "OPTIONS": {
            "CLIENT_CLASS": "django_redis.client.DefaultClient",
        },
        "TIMEOUT": 300,  # Default 5 minutes
    }
}

# Use Redis for sessions too
SESSION_ENGINE = "django.contrib.sessions.backends.cache"
SESSION_CACHE_ALIAS = "default"
```

---

## Database Tuning

### Connection Pooling

Django creates a new DB connection per request by default. For high-traffic apps:

```python
# settings/production.py
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.environ.get("DB_NAME"),
        "USER": os.environ.get("DB_USER"),
        "PASSWORD": os.environ.get("DB_PASSWORD"),
        "HOST": os.environ.get("DB_HOST"),
        "PORT": os.environ.get("DB_PORT", "5432"),
        "CONN_MAX_AGE": 600,  # Keep connections alive for 10 minutes
        "CONN_HEALTH_CHECKS": True,  # Django 4.1+
        "OPTIONS": {
            "connect_timeout": 5,
        },
    }
}
```

For even better pooling, consider `pgbouncer` in front of PostgreSQL.

### Indexes Strategy

Think about indexes based on your actual query patterns:

```python
class Order(models.Model):
    class Meta:
        indexes = [
            # Composite index for common filter + sort
            models.Index(fields=["user", "-created_at"], name="idx_user_recent_orders"),

            # Partial index — only index rows that matter
            models.Index(
                fields=["status"],
                condition=models.Q(status__in=["pending", "processing"]),
                name="idx_active_orders",
            ),

            # GIN index for full-text search (PostgreSQL)
            # models.Index(fields=["search_vector"], name="idx_search"),
        ]
```

---

## Async Views & Background Tasks

### When to Use Async Views (Django 4.1+)

Async views shine when you have I/O-bound operations that can run concurrently (external API calls, file operations). They do NOT help with CPU-bound work or ORM queries (the ORM is still sync under the hood).

```python
import httpx
from django.http import JsonResponse


async def fetch_external_data(request):
    async with httpx.AsyncClient() as client:
        response = await client.get("https://api.example.com/data")
    return JsonResponse(response.json())
```

### Celery for Background Tasks

For anything that doesn't need to happen in the request-response cycle:

```python
# apps/orders/tasks.py
from celery import shared_task
import logging

logger = logging.getLogger(__name__)


@shared_task(
    bind=True,
    max_retries=3,
    default_retry_delay=60,
    acks_late=True,
)
def send_order_confirmation(self, order_id):
    try:
        order = Order.objects.select_related("user").get(id=order_id)
        # send email...
        logger.info("Order confirmation sent", extra={"order_id": order_id})
    except Order.DoesNotExist:
        logger.warning("Order not found for confirmation", extra={"order_id": order_id})
    except Exception as exc:
        logger.exception("Failed to send order confirmation")
        raise self.retry(exc=exc)
```

Key settings:
- `acks_late=True` — acknowledge task after completion, not before. Prevents task loss if the worker crashes.
- `bind=True` — gives access to `self` for retries.
- Always handle the case where the object no longer exists by the time the task runs.

---

## Serialization Performance

### Avoid Serializer Overhead for Simple Cases

If you're returning simple data that doesn't need validation:
```python
from rest_framework.response import Response

class StatsView(APIView):
    def get(self, request):
        stats = Order.objects.aggregate(
            total=Sum("amount"),
            count=Count("id"),
        )
        return Response(stats)  # No serializer needed
```

### Optimize `to_representation`

If you must override `to_representation`, be aware it runs per-object:
```python
# BAD — database query per object
class OrderSerializer(serializers.ModelSerializer):
    discount = serializers.SerializerMethodField()

    def get_discount(self, obj):
        return Discount.objects.filter(order=obj).first()  # N+1!

# GOOD — use prefetched data
class OrderSerializer(serializers.ModelSerializer):
    discount = serializers.SerializerMethodField()

    def get_discount(self, obj):
        # Requires prefetch_related("discounts") on the queryset
        discounts = getattr(obj, "prefetched_discounts", [])
        return discounts[0] if discounts else None
```
