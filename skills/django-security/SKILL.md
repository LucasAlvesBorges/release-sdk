---
description: >
  Adversarial security audit against 9 mandatory categories — cross-tenant isolation, intra-tenant IDOR,
  vertical privilege escalation, mass assignment, JWT lifecycle, input validation/injection,
  auth state transitions, CSRF, cookie/token security. Verifies code mitigation AND test coverage.
  Use when: shipping new feature, pre-prod audit, security review.
allowed_tools: Agent, Read, Bash, Grep, Glob
---

# /django:security — 9-Category Django Security Audit

Audits Django/DRF feature against the 9 mandatory security categories. Verifies both mitigation in code AND test coverage. Produces SECURITY.md.

## Usage

```
/django:security backend/apps/financeiro/
/django:security --feature=parcela_baixa
```

## Arguments

- `$ARGUMENTS` — App directory or feature name
- `--security-path=PATH` — Where to write SECURITY.md (default: `./SECURITY.md`)

## Workflow

1. Parse arguments — resolve feature scope
2. Spawn `release-security-auditor` agent
3. Agent audits 9 categories:
   - Cross-tenant isolation
   - Intra-tenant IDOR
   - Vertical privilege escalation
   - Mass assignment
   - JWT lifecycle
   - Input validation / injection
   - Auth state transitions
   - CSRF
   - Cookie / token security
4. Each category: CLOSED (mitigation + test) | PARTIAL (mitigation, no test) | OPEN (neither)
5. Produces SECURITY.md with status SECURED / OPEN_THREATS / PARTIAL

## Output

```yaml
categories:
  cross_tenant: CLOSED          # ✓ TenantModel + get_queryset filter + test
  intra_tenant_idor: PARTIAL    # ⚠ Permission check present, no test
  vertical_escalation: CLOSED
  mass_assignment: OPEN         # ✗ fields = '__all__' detected!
  jwt_lifecycle: CLOSED
  input_validation: CLOSED
  auth_transitions: PARTIAL
  csrf: CLOSED
  cookie_token_security: CLOSED
totals:
  closed: 6
  partial: 2
  open: 1
status: OPEN_THREATS
```

If any OPEN → status = OPEN_THREATS (BLOCKER for ship).


---

## Stack dispatch

This skill spawns merged `release-*` agents (one agent per role, dispatched internally by `stack`). All agent spawns from this skill pass `stack: django` as input. The agents apply Django-stack rules from their `<django-stack>` blocks.
