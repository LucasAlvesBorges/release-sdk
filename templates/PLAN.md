<!--
# PLAN.md — Phase {NN}: {phase-slug}
#
# Produced by django-feature-planner after reading CONTEXT.md + RESEARCH.md + PATTERNS.md.
# Verified by django-plan-checker before execution.
# Consumed by django-tdd-executor.
#
# This file IS the prompt the executor reads — not a document that becomes a prompt.
-->

---
phase: {NN}
slug: {phase-slug}
created: {YYYY-MM-DDTHH:MM:SSZ}
revised: {YYYY-MM-DDTHH:MM:SSZ}
status: ready                     # ready | executing | complete
context_ref: {NN}-CONTEXT.md
research_ref: {NN}-RESEARCH.md
patterns_ref: {NN}-PATTERNS.md
must_haves:
  truths:
    - "User can {observable outcome 1}"
    - "User can {observable outcome 2}"
  artifacts:
    - path: backend/apps/{app}/models.py
      provides: "{Model class}"
    - path: backend/apps/{app}/views.py
      provides: "{ViewSet class}"
    - path: backend/apps/{app}/migrations/00XX_xxx.py
      provides: "DB schema change"
  key_links:
    - from: views.py
      to: serializers.py
      via: "ViewSet.serializer_class"
    - from: views.py
      to: tasks.py
      via: ".delay_on_commit() dispatch"
threat_model:
  - id: T-01
    category: cross_tenant
    disposition: mitigate
    plan: "TenantModel inheritance + view-level filter by request.user.empresa"
  - id: T-02
    category: mass_assignment
    disposition: mitigate
    plan: "Serializer fields explicit, empresa + created_at read_only"
  - id: T-03
    category: intra_tenant_idor
    disposition: mitigate
    plan: "permission_classes + get_object_or_404 with owner filter"
  # Cover all 9 categories — see /django:security for full audit
covers_decisions:
  - D-01
  - D-02
  - D-03
---

# Phase {NN} Plan: {phase-name}

## Objective

{What and why. Reference D-XX decisions from CONTEXT.md. NO "v1", "simplified", "placeholder" language.}

## Context

@{NN}-CONTEXT.md
@{NN}-RESEARCH.md
@{NN}-PATTERNS.md
@CLAUDE.md
@backend/apps/{app}/models.py

---

## Tasks

### T01 — RED: Write failing tests

**Type:** `tdd-red`
**Files:**
- `backend/apps/{app}/tests/test_{feature}.py` — create
- `backend/apps/{app}/tests/factories.py` — modify (add new factory)

**Action:**
1. Add factory-boy fixture `{Model}Factory` with TenantModel sub-factory.
2. Write smoke test `test_{endpoint}_list_smoke` using `django_assert_max_num_queries(20)`.
3. Write CRUD tests: list, retrieve, create, update, delete.
4. Run pytest, confirm RED (all fail because endpoint doesn't exist).
5. Commit: `test({app}): add failing tests for {feature}`

**Author Checklist:** N/A (test-only commit).

**Done when:**
- 5+ failing tests written
- `pytest <test_file>` shows expected failures
- Test file committed as RED

### T02 — GREEN: Model + Migration

**Type:** `tdd-green`
**Files:**
- `backend/apps/{app}/models.py` — modify (add `class {Model}(TenantModel)`)
- `backend/apps/{app}/migrations/00XX_*.py` — create via `makemigrations`

**Action per D-01, D-03:**
1. Define `class {Model}(TenantModel)` with:
   - `id = UUIDField(primary_key=True, default=uuid.uuid4, editable=False)`
   - `empresa = ForeignKey('users.Empresa', on_delete=PROTECT)` (inherited from TenantModel)
   - {domain fields per D-01}
   - Meta: `unique_together = [('empresa', '{codigo}')]` per D-02
2. Run `python backend/manage.py makemigrations {app}`.
3. Run pytest — RED tests must still fail (endpoint not yet wired).
4. Commit migration separately: `feat({app}): add {Model} table`

**Author Checklist:** N/A for model commit itself; Q1-Q7 applied in T03 (view).

**Done when:**
- Model defined per D-XX decisions
- Migration generated, no drift
- `makemigrations --check --dry-run` clean
- Committed

### T03 — GREEN: Serializer + ViewSet + URL

**Type:** `tdd-green`
**Files:**
- `backend/apps/{app}/serializers.py` — modify
- `backend/apps/{app}/views.py` — modify
- `backend/apps/{app}/urls.py` — modify

**Action per D-01:**
1. Define `{Model}Serializer` with explicit `fields = [...]`, `read_only_fields = ['empresa', 'created_at', 'usuario']`.
2. Define `{Model}ViewSet(ModelViewSet)`:
   - `permission_classes = [IsAuthenticated, {RoleSpecificPerm}]`
   - `get_queryset(self).select_related(...).prefetch_related(...).annotate(...)`
   - Tenant scope from `self.request.user.empresa`
3. Register: `router.register(r'{slug}', {Model}ViewSet)`.
4. Run pytest — RED tests now pass.
5. Commit: `feat({app}): implement {feature} CRUD`

**Author Checklist:**
- **Q1 select_related:** `['empresa', '{fk1}', '{fk2}']` — accessed in serializer
- **Q2 prefetch_related:** `['{m2m1}']` — iterated in nested serializer
- **Q3 annotate Count:** `'{x_count}'` via `Count('{related}')` instead of method
- **Q4 Subquery:** N/A — no per-row aggregation
- **Q5 F() / select_for_update:** N/A — no numeric mutation
- **Q6 delay_on_commit:** N/A — no Celery dispatch here
- **Q7 iterator:** N/A — bounded list endpoint

**Done when:**
- All T01 tests pass
- Smoke test under `django_assert_max_num_queries(20)` budget
- Committed

### T04 — SECURITY: 9-category tests

**Type:** `auto`
**Files:**
- `backend/apps/{app}/tests/test_{feature}_security.py` — create

**Action:** Write test for each of 9 categories (use template from `django-test-auditor`):

| # | Test | Assertion |
|---|------|-----------|
| 1 | `test_cross_tenant_isolation` | empresa A user → empresa B object → 404 |
| 2 | `test_intra_tenant_idor` | user A → user B's owned object → 403 |
| 3 | `test_privilege_escalation` | regular user → admin action → 403 |
| 4 | `test_mass_assignment_blocked` | POST `is_staff: True` → ignored |
| 5 | `test_jwt_expired_rejected` | expired token → 401 |
| 6 | `test_injection_payload_rejected` | `'; DROP TABLE` → 400 or sanitized |
| 7 | `test_auth_state_transitions` | password-reset token reuse → 400 |
| 8 | `test_csrf_required` | session-auth POST without CSRF → 403 (or N/A if JWT-only) |
| 9 | `test_cookie_security_flags` | Set-Cookie has HttpOnly+Secure+SameSite |

**Done when:**
- All 9 tests written
- All pass
- Committed: `test({app}): add 9-category security tests for {feature}`

### T05 (conditional — only if Q5 active) — RACE TEST

**Type:** `auto`
**Files:**
- `backend/apps/{app}/tests/test_{feature}_race.py` — create

**Action:** Write `threading.Barrier(2)` test asserting no lost-update under concurrent {operation}.

**Done when:**
- Test passes deterministically
- Committed: `test({app}): add race test for {feature}`

### T06 (conditional — only if Q7 active) — MEMRAY TEST

**Type:** `auto`
**Files:**
- `backend/apps/{app}/tests/test_{feature}_memray.py` — create

**Action:** Write `@pytest.mark.limit_memory("X MB")` test asserting bulk export stays within memory budget.

**Done when:**
- Test passes under `pytest --memray`
- Committed: `test({app}): add memray test for {feature}`

---

## Wave Structure

```yaml
wave_0:  # serial — must complete before wave_1
  - T01_red_tests
wave_1:  # parallel where independent
  - T02_model_migration
  - T03_serializer_view_url  # depends on T02
wave_2:
  - T04_security_tests
wave_3:  # conditional
  - T05_race_test       # only if Q5 active
  - T06_memray_test     # only if Q7 active
```

---

## Success Criteria

- [ ] All tasks T01-T06 (or applicable subset) complete
- [ ] All tests pass: `pytest backend/apps/{app}/tests/ -q`
- [ ] `makemigrations --check --dry-run` exits 0
- [ ] `ruff check` clean
- [ ] django-checklist-verifier: all Q1-Q7 PASS or justified N/A
- [ ] django-security-auditor: 9/9 CLOSED
- [ ] All Decisions D-XX from CONTEXT.md visible in implementation (referenced in commit body)
- [ ] Phase verifier (goal-backward): all `must_haves.truths` VERIFIED

---

_Edit only via /django:plan (re-runs planning). Manual edits risk de-syncing CONTEXT.md alignment._
