# Django Testing Reference

## Table of Contents

1. [pytest-django Setup](#pytest-django-setup)
2. [Factory Boy Patterns](#factory-boy-patterns)
3. [API Testing with DRF](#api-testing-with-drf)
4. [Performance Testing](#performance-testing)
5. [Test Organization](#test-organization)

---

## pytest-django Setup

### Configuration

```python
# pyproject.toml
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.test"
python_files = ["test_*.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
addopts = [
    "--reuse-db",           # Reutiliza DB entre runs (muito mais rápido)
    "--strict-markers",     # Falha se marker não registrado
    "-x",                   # Para no primeiro erro
    "--tb=short",           # Traceback curto
]
markers = [
    "slow: marks tests as slow (deselect with '-m \"not slow\"')",
    "integration: marks integration tests",
]
```

```python
# settings/test.py
from .base import *  # noqa

# Faster password hashing for tests
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]

# In-memory email
EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"

# Faster storage
DEFAULT_FILE_STORAGE = "django.core.files.storage.InMemoryStorage"  # Django 4.2+

# Disable migrations for speed (use with caution)
# MIGRATION_MODULES = {app: None for app in INSTALLED_APPS}
```

### Essential Fixtures (conftest.py)

```python
# conftest.py (project root)
import pytest
from rest_framework.test import APIClient
from apps.accounts.tests.factories import UserFactory


@pytest.fixture
def api_client():
    """Unauthenticated API client."""
    return APIClient()


@pytest.fixture
def user(db):
    """Regular user."""
    return UserFactory()


@pytest.fixture
def admin_user(db):
    """Admin user."""
    return UserFactory(is_staff=True, is_superuser=True)


@pytest.fixture
def auth_client(user):
    """Authenticated API client."""
    client = APIClient()
    client.force_authenticate(user=user)
    return client


@pytest.fixture
def admin_client(admin_user):
    """Admin-authenticated API client."""
    client = APIClient()
    client.force_authenticate(user=admin_user)
    return client
```

---

## Factory Boy Patterns

### Base Factory

```python
# apps/accounts/tests/factories.py
import factory
from django.contrib.auth import get_user_model

User = get_user_model()


class UserFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = User
        skip_postgeneration_save = True  # factory_boy 3.3+

    username = factory.Sequence(lambda n: f"user_{n}")
    email = factory.LazyAttribute(lambda obj: f"{obj.username}@example.com")
    first_name = factory.Faker("first_name")
    last_name = factory.Faker("last_name")
    is_active = True

    @factory.post_generation
    def password(self, create, extracted, **kwargs):
        password = extracted or "testpass123"
        self.set_password(password)
        if create:
            self.save(update_fields=["password"])
```

```python
# apps/orders/tests/factories.py
import factory
from apps.accounts.tests.factories import UserFactory
from apps.orders.models import Order, OrderItem


class OrderFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Order

    user = factory.SubFactory(UserFactory)
    status = "pending"
    total = factory.Faker("pydecimal", left_digits=4, right_digits=2, positive=True)

    @factory.post_generation
    def items(self, create, extracted, **kwargs):
        if not create:
            return
        if extracted:
            for item in extracted:
                self.items.add(item)


class OrderItemFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = OrderItem

    order = factory.SubFactory(OrderFactory)
    product_name = factory.Faker("word")
    quantity = factory.Faker("random_int", min=1, max=10)
    price = factory.Faker("pydecimal", left_digits=3, right_digits=2, positive=True)
```

### Factory Traits

```python
class UserFactory(factory.django.DjangoModelFactory):
    # ...

    class Params:
        admin = factory.Trait(
            is_staff=True,
            is_superuser=True,
            username=factory.Sequence(lambda n: f"admin_{n}"),
        )
        inactive = factory.Trait(is_active=False)

# Usage:
# UserFactory(admin=True)
# UserFactory(inactive=True)
```

---

## API Testing with DRF

### CRUD Test Pattern

```python
# apps/orders/tests/test_views.py
import pytest
from django.urls import reverse
from rest_framework import status
from .factories import OrderFactory


@pytest.mark.django_db
class TestOrderViewSet:
    endpoint = reverse("order-list")

    def test_list_returns_only_own_orders(self, auth_client, user):
        own_order = OrderFactory(user=user)
        OrderFactory()  # Another user's order

        response = auth_client.get(self.endpoint)

        assert response.status_code == status.HTTP_200_OK
        assert len(response.data["results"]) == 1
        assert response.data["results"][0]["id"] == own_order.id

    def test_create_order(self, auth_client, user):
        payload = {"items": [{"product_id": 1, "quantity": 2}]}

        response = auth_client.post(self.endpoint, payload, format="json")

        assert response.status_code == status.HTTP_201_CREATED
        assert response.data["user"] == user.id

    def test_cannot_access_other_users_order(self, auth_client):
        other_order = OrderFactory()

        response = auth_client.get(
            reverse("order-detail", kwargs={"pk": other_order.pk})
        )

        assert response.status_code == status.HTTP_404_NOT_FOUND

    def test_unauthenticated_returns_401(self, api_client):
        response = api_client.get(self.endpoint)
        assert response.status_code == status.HTTP_401_UNAUTHORIZED
```

### Permission Testing

```python
@pytest.mark.django_db
class TestOrderPermissions:
    def test_regular_user_cannot_delete(self, auth_client, user):
        order = OrderFactory(user=user)
        url = reverse("order-detail", kwargs={"pk": order.pk})

        response = auth_client.delete(url)

        assert response.status_code == status.HTTP_403_FORBIDDEN

    def test_admin_can_delete(self, admin_client):
        order = OrderFactory()
        url = reverse("order-detail", kwargs={"pk": order.pk})

        response = admin_client.delete(url)

        assert response.status_code == status.HTTP_204_NO_CONTENT
```

### Serializer Testing

```python
@pytest.mark.django_db
class TestUserSerializer:
    def test_read_only_fields_not_writable(self):
        user = UserFactory()
        serializer = UserSerializer(
            user,
            data={"is_superuser": True, "is_staff": True},
            partial=True,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        user.refresh_from_db()

        assert user.is_superuser is False
        assert user.is_staff is False
```

---

## Performance Testing

### Query Count Assertions

```python
@pytest.mark.django_db
class TestOrderQueries:
    def test_list_endpoint_query_count(self, auth_client, user, django_assert_num_queries):
        OrderFactory.create_batch(10, user=user)

        # Expect: 1 (auth) + 1 (orders) + 1 (prefetch items) + 1 (count for pagination)
        with django_assert_num_queries(4):
            auth_client.get(reverse("order-list"))

    def test_detail_endpoint_query_count(self, auth_client, user, django_assert_num_queries):
        order = OrderFactory(user=user)

        with django_assert_num_queries(2):  # 1 auth + 1 order
            auth_client.get(reverse("order-detail", kwargs={"pk": order.pk}))
```

---

## Test Organization

```
apps/orders/tests/
├── __init__.py
├── conftest.py          # App-specific fixtures
├── factories.py         # Factory Boy factories
├── test_models.py       # Model validation, methods, properties
├── test_views.py        # API endpoint tests (status codes, permissions, data)
├── test_serializers.py  # Field validation, read_only enforcement
├── test_services.py     # Business logic tests
└── test_filters.py      # Filter/search tests
```

**Rules of thumb:**
- Use `@pytest.mark.django_db` on every test that touches the database
- Use `force_authenticate` instead of real login for API tests (faster)
- Test permissions explicitly — don't assume DRF defaults
- Test edge cases: empty lists, missing fields, wrong types, boundary values
- Use `create_batch` for list tests, single factories for detail tests
