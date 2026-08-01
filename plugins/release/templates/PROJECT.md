<!--
# PROJECT.md template
# Defines project vision, locked architectural decisions, and conventions.
# Every planning artifact downstream honors what's locked here.
# Edit this file once at project init via /django:init, then rarely.
-->

# {Project Name}

## Vision

{One-paragraph statement of what this product does and for whom. The reason the codebase exists.}

## Domain

{Industry / use case. Affects security categories, regulatory constraints, performance targets.}

Examples:
- "Multi-tenant ERP for urban bus transport companies"
- "B2B SaaS scheduling platform"
- "Internal admin tool for marketing operations"

## Core Value

{One sentence describing the single most important invariant the system MUST preserve. The thing that, if broken, makes everything else worthless.}

Example: "Total data isolation between tenants — if everything else fails, no data can leak between companies."

---

## Locked Architectural Decisions

These are FINAL. Every plan, every implementation honors them. Reference by ID (LOCK-XX) in PLAN.md tasks for traceability.

### LOCK-01: Backend Stack
- Python {3.12+}
- Django {5.2 LTS}
- DRF {3.16.x}
- PostgreSQL {15+}
- Redis {7.x}
- Celery {5.5.x}

### LOCK-02: Frontend Stack
- {React 19.x + TypeScript 5.7+ + Vite}
- {Tailwind CSS 4.x (CSS-first, no tailwind.config.js)}
- {shadcn/ui via CLI (components copied, not npm dep)}
- {TanStack Query for server state}
- {Zustand for client UI state}
- {React Hook Form + Zod for forms}

### LOCK-03: Multi-Tenancy
- `empresa_id` field on every tenant-scoped model
- `TenantModel` base class + `TenantAwareManager` (app layer)
- `django-rls` middleware + PostgreSQL RLS (defense-in-depth)
- 5-layer isolation: model → manager → middleware → RLS → application code

### LOCK-04: Authentication
- {djangorestframework-simplejwt}
- {JWT in httpOnly + Secure + SameSite cookie, NOT localStorage}
- {Refresh rotation + blacklist on logout}

### LOCK-05: Background Jobs
- Celery 5.5.x
- ALWAYS `.delay_on_commit()`, NEVER `.delay()`
- Tasks in `tasks.py` per app
- `task_routes` separates priority queues

### LOCK-06: Database Conventions
- All custom models: UUID primary keys (NOT integer)
- All tenant-scoped models: inherit `TenantModel`
- Built-in Django models (auth.Group, ContentType): integer PK preserved

### LOCK-07: Testing Discipline
- TDD: failing test before implementation, no exceptions
- 9 security categories tested per feature (cross-tenant, IDOR, vertical escalation, mass assignment, JWT, injection, auth transitions, CSRF, cookie/token)
- Race tests for any numeric mutation (`threading.Barrier(2)`)
- Memray tests for bulk export (>1000 rows)

### LOCK-08: Code Quality
- Ruff for lint + format
- mypy --strict (optional but supported)
- Pre-commit hooks enforce: ruff, makemigrations check, smoke tests
- Conventional Commits with Django scopes

### LOCK-09: History / Audit
- {apps.historico (`MovimentacaoRegistry` + `HistoricoService`)}
- NOT django-auditlog
- Models with lifecycle (status/workflow), movement, or financial ops MUST register

### LOCK-10: Forbidden Patterns
- `fields = '__all__'` in serializers
- `.delay()` outside test files
- `Model.objects.unscoped()` in app code (outside data migrations)
- `models.Model` inheritance (use `TenantModel` unless explicitly opted out)
- `@csrf_exempt` on session-auth endpoints
- Raw SQL with f-string interpolation
- `psycopg2` (use psycopg3)
- `django-tenants` (use django-rls)
- `formik` (use React Hook Form + Zod)
- `Redux` (use TanStack Query + Zustand)

---

## Author Checklist Q1-Q7 (LOCKED)

Every feature plan MUST answer these before writing the view. See `~/release/personal/django-sdk/agents/django-checklist-verifier.md` for full grep patterns.

| # | Question | Default |
|---|----------|---------|
| Q1 | Every FK accessed in serializer is in `select_related()`? | apply |
| Q2 | Every reverse-FK/M2M iterated is in `prefetch_related()`? | apply |
| Q3 | `SerializerMethodField` counts → `annotate(Count())`? | apply |
| Q4 | Per-row computation → `Subquery/OuterRef`? | apply |
| Q5 | Numeric mutation uses `F()` OR `atomic + select_for_update`? | apply |
| Q6 | Celery dispatch uses `.delay_on_commit()`? | LOCKED — always |
| Q7 | Queryset >1000 rows uses `.iterator(chunk_size=N)`? | apply if applicable |

---

## Domain-Specific Conventions

{Project-specific patterns. Examples:}

### {SearchableCombobox usage}
{Frontend selector with >10 items, search, or inline creation must use `SearchableCombobox`. Simple `<10 items` use shadcn Select.}

### {ArrayField + GinIndex for enum-multi-valor}
{≤10 fixed values, no metadata → ArrayField + GinIndex. Otherwise M2M.}

### {Histórico tracking}
{New TenantModel with lifecycle/workflow/financial ops MUST register via `MovimentacaoRegistry` in `apps.py::ready()`.}

---

## Out of Scope

{Explicitly NOT building. Surface to prevent scope creep:}

- {Real-time WebSocket features (Phase 2)}
- {Mobile app (separate project)}
- {AI/ML features beyond rule-based heuristics}

---

_Edit conventions: change LOCK-XX entries via `/django:roadmap` after team alignment. Adding new LOCK-XX is allowed; removing requires explicit migration plan._
