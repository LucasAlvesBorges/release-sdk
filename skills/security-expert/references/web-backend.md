# Web and backend threat guide

Load this reference only for an authorized web/API/backend review.

## High-value traces

- **Authorization:** route to queryset/resource scope to object/action permission. Check tenant boundaries, indirect identifiers, bulk actions, exports, and background jobs.
- **Injection:** untrusted input reaching SQL, shell, templates, expression engines, deserializers, file paths, redirects, headers, or logs. Prefer parameterization and allowlists.
- **Server-side requests:** user-controlled scheme, host, redirects, DNS resolution, or credentials reaching HTTP clients. Block private/link-local ranges after resolution and on redirects.
- **Authentication/session:** token issuance, rotation, revocation, fixation, reset flows, MFA recovery, cookie flags, CSRF, and sensitive state changes.
- **Data exposure:** serializers, error bodies, logs, caches, object storage, debug endpoints, source maps, backups, and cross-tenant cache keys.
- **Files:** extension/MIME/signature mismatch, path traversal, archive expansion, public serving, active content, overwrite, and processing isolation.
- **Business logic:** replay, race conditions, idempotency, price/role manipulation, quota bypass, and state transitions performed out of order.
- **Supply/config:** exposed secrets, unsafe defaults, permissive CORS/hosts, debug mode, dependency provenance, and privileged CI tokens.

## Evidence standard

A confirmed finding needs a reachable source, a security-relevant sink or missing decision, and realistic preconditions. Use a harmless local request or focused test when needed. Do not assign critical/high severity from a pattern match alone.

Severity follows demonstrated impact and reachability:

- Critical: broad compromise with practical exploitation and little user interaction.
- High: account/tenant compromise, sensitive data access, or privileged execution.
- Medium: meaningful exposure requiring constraints or user interaction.
- Low: limited impact or defense-in-depth weakness.

Every finding includes the smallest viable fix and a regression-test idea.
