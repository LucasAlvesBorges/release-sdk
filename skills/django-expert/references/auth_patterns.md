# Django Authentication Patterns Reference

## Table of Contents

1. [JWT Authentication Flows](#jwt-authentication-flows)
2. [Social Authentication](#social-authentication)
3. [Multi-Tenancy Permissions](#multi-tenancy-permissions)
4. [API Key Management](#api-key-management)
5. [Two-Factor Authentication](#two-factor-authentication)

---

## JWT Authentication Flows

### Complete Login/Refresh/Logout Flow

```python
# apps/accounts/urls.py
from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView
from . import views

urlpatterns = [
    path("auth/login/", views.LoginView.as_view(), name="token_obtain"),
    path("auth/refresh/", TokenRefreshView.as_view(), name="token_refresh"),
    path("auth/logout/", views.LogoutView.as_view(), name="token_logout"),
    path("auth/register/", views.RegisterView.as_view(), name="register"),
    path("auth/me/", views.CurrentUserView.as_view(), name="current_user"),
]
```

```python
# apps/accounts/views.py
from rest_framework import generics, status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework_simplejwt.tokens import RefreshToken


class LoginView(TokenObtainPairView):
    """Custom login that can return user data alongside tokens."""
    serializer_class = CustomTokenObtainPairSerializer


class RegisterView(generics.CreateAPIView):
    permission_classes = [AllowAny]
    serializer_class = RegisterSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()

        refresh = RefreshToken.for_user(user)
        return Response(
            {
                "user": UserSerializer(user).data,
                "tokens": {
                    "refresh": str(refresh),
                    "access": str(refresh.access_token),
                },
            },
            status=status.HTTP_201_CREATED,
        )


class LogoutView(generics.GenericAPIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            refresh_token = request.data.get("refresh")
            token = RefreshToken(refresh_token)
            token.blacklist()
            return Response(status=status.HTTP_205_RESET_CONTENT)
        except Exception:
            return Response(status=status.HTTP_400_BAD_REQUEST)


class CurrentUserView(generics.RetrieveUpdateAPIView):
    permission_classes = [IsAuthenticated]
    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user
```

### Custom Token Claims

Add custom data to JWT tokens (useful for frontend to avoid extra API calls):

```python
# apps/accounts/serializers.py
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer


class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        # Add custom claims
        token["username"] = user.username
        token["email"] = user.email
        token["role"] = user.role
        return token

    def validate(self, attrs):
        data = super().validate(attrs)
        data["user"] = {
            "id": self.user.id,
            "username": self.user.username,
            "email": self.user.email,
            "role": self.user.role,
        }
        return data
```

---

## Social Authentication

For projects that need Google, GitHub, or other OAuth providers, `dj-rest-auth` with `django-allauth` is the standard combination:

```python
# requirements/base.txt
dj-rest-auth[with_social]
django-allauth

# settings/base.py
INSTALLED_APPS = [
    # ...
    "django.contrib.sites",
    "allauth",
    "allauth.account",
    "allauth.socialaccount",
    "allauth.socialaccount.providers.google",
    "allauth.socialaccount.providers.github",
    "dj_rest_auth",
    "dj_rest_auth.registration",
]

SITE_ID = 1

# allauth settings
ACCOUNT_EMAIL_REQUIRED = True
ACCOUNT_USERNAME_REQUIRED = False
ACCOUNT_AUTHENTICATION_METHOD = "email"
ACCOUNT_EMAIL_VERIFICATION = "mandatory"

REST_AUTH = {
    "USE_JWT": True,
    "JWT_AUTH_HTTPONLY": False,  # Set True if using cookie-based auth
}
```

---

## Multi-Tenancy Permissions

For SaaS-style applications where users belong to organizations:

```python
# apps/organizations/models.py
class Organization(models.Model):
    name = models.CharField(max_length=255)
    slug = models.SlugField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)


class Membership(models.Model):
    class Role(models.TextChoices):
        OWNER = "owner", "Owner"
        ADMIN = "admin", "Admin"
        MEMBER = "member", "Member"
        VIEWER = "viewer", "Viewer"

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="memberships")
    organization = models.ForeignKey(Organization, on_delete=models.CASCADE, related_name="memberships")
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.MEMBER)

    class Meta:
        unique_together = ["user", "organization"]
```

```python
# apps/organizations/permissions.py
class IsOrganizationMember(BasePermission):
    def has_permission(self, request, view):
        org_slug = view.kwargs.get("org_slug")
        if not org_slug:
            return False
        return Membership.objects.filter(
            user=request.user,
            organization__slug=org_slug,
        ).exists()


class IsOrganizationAdmin(BasePermission):
    def has_permission(self, request, view):
        org_slug = view.kwargs.get("org_slug")
        if not org_slug:
            return False
        return Membership.objects.filter(
            user=request.user,
            organization__slug=org_slug,
            role__in=[Membership.Role.OWNER, Membership.Role.ADMIN],
        ).exists()
```

```python
# apps/organizations/mixins.py
class OrganizationQuerySetMixin:
    """Filter queryset by the current organization from URL."""

    def get_organization(self):
        return Organization.objects.get(slug=self.kwargs["org_slug"])

    def get_queryset(self):
        return super().get_queryset().filter(organization=self.get_organization())

    def perform_create(self, serializer):
        serializer.save(organization=self.get_organization())
```

URL structure for multi-tenant APIs:
```python
# config/urls.py
urlpatterns = [
    path("api/v1/orgs/<slug:org_slug>/", include("apps.organizations.urls")),
]

# apps/organizations/urls.py
urlpatterns = [
    path("projects/", views.ProjectViewSet.as_view({"get": "list", "post": "create"})),
    path("projects/<int:pk>/", views.ProjectViewSet.as_view({"get": "retrieve", "put": "update"})),
    path("members/", views.MembershipViewSet.as_view({"get": "list", "post": "create"})),
]
```

---

## API Key Management

For service-to-service or third-party integrations:

```python
# apps/core/models.py
import secrets
from django.db import models


class APIKey(models.Model):
    name = models.CharField(max_length=255, help_text="Description of what this key is for")
    key = models.CharField(max_length=64, unique=True, db_index=True)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="api_keys")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_used_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)

    def save(self, *args, **kwargs):
        if not self.key:
            self.key = secrets.token_urlsafe(48)
        super().save(*args, **kwargs)

    @property
    def is_valid(self):
        from django.utils import timezone
        if not self.is_active:
            return False
        if self.expires_at and self.expires_at < timezone.now():
            return False
        return True
```

```python
# apps/core/authentication.py
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed
from django.utils import timezone


class APIKeyAuthentication(BaseAuthentication):
    keyword = "Api-Key"

    def authenticate(self, request):
        api_key = request.headers.get("X-API-Key") or request.query_params.get("api_key")
        if not api_key:
            return None

        try:
            key_obj = APIKey.objects.select_related("user").get(key=api_key)
        except APIKey.DoesNotExist:
            raise AuthenticationFailed("Invalid API key.")

        if not key_obj.is_valid:
            raise AuthenticationFailed("API key is expired or inactive.")

        # Track usage
        key_obj.last_used_at = timezone.now()
        key_obj.save(update_fields=["last_used_at"])

        return (key_obj.user, key_obj)
```

---

## Two-Factor Authentication

For applications requiring MFA, `django-otp` with `djangorestframework-totp` provides the foundation.

Key considerations:
- Store backup codes for account recovery (hashed, not plain text)
- Rate-limit TOTP verification attempts
- Allow users to manage their own MFA devices
- Consider WebAuthn/FIDO2 for hardware key support via `django-fido2`

The implementation details vary significantly based on your exact requirements, but the core principle is: MFA should be enforced at the authentication layer, not sprinkled across individual views.
