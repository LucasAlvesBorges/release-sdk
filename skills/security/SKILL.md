---
description: >
  Context-aware 9-category security audit. Routes .py files to release-security-auditor and
  .tsx/.ts files to release-security-auditor. Produces unified SECURITY.md.
  Use when: feature complete, pre-merge, or periodic security review.
allowed_tools: Agent, Read, Bash, Grep, Glob
---

# /release:security — Full-Stack Security Audit

Routes to the correct security auditor based on file type. Unified SECURITY.md output.

## Usage

```
/release:security 01                         # audit phase 01 files
/release:security backend/apps/financeiro/   # Django-only audit
/release:security src/features/Invoices/     # React-only audit
/release:security --diff main..HEAD          # audit changed files
```

## Routing logic

1. Resolve scope: phase directory, explicit paths, or git diff.
2. Split `.py` → `release-security-auditor`, `.tsx/.ts` → `release-security-auditor`.
3. Run in parallel if both present.
4. Merge into SECURITY.md with per-stack category tables.

## Django 9 categories (backend)
1. Cross-Tenant Isolation
2. Intra-Tenant IDOR
3. Vertical Privilege Escalation
4. Mass Assignment
5. JWT Lifecycle
6. Input Validation / Injection
7. Auth State Transitions
8. CSRF
9. Cookie / Token Security

## React 9 categories (frontend)
1. XSS Prevention
2. Auth Token Storage (httpOnly cookies only)
3. CSRF (X-CSRFToken header)
4. Client-side IDOR
5. API Key / Secret Exposure
6. Content Injection (Markdown/rich text)
7. Prototype Pollution
8. Sensitive Data Logging
9. Input Validation (Zod schemas)

## Full-stack cross-cutting checks

When both stacks present:
- Auth model consistent: Django sets httpOnly cookie + React never touches localStorage
- CSRF consistent: Django `CsrfViewMiddleware` active + React sends `X-CSRFToken` header
- Permission model consistent: Django permission classes match React route guards (defense in depth)

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-SECURITY.md
  ## Backend Security (Django)
    | Category | Status | Evidence |
  ## Frontend Security (React)
    | Category | Status | Evidence |
  ## Full-Stack Cross-Cutting
    | Check | Status |
  ## Open Issues (BLOCKER)
    ...remediation steps...
```

## Example

```
/release:security 01

→ Scope: FULLSTACK
→ Django files: 3 (.py)
→ React files: 4 (.tsx/.ts)

→ Backend audit (release-security-auditor)...
  Cat 1 (Cross-Tenant): CLOSED — TenantModel used, empresa filter in get_queryset
  Cat 4 (Mass Assignment): OPEN — InvoiceSerializer uses fields = '__all__'
  ...

→ Frontend audit (release-security-auditor)...
  Cat 2 (Auth Token): CLOSED — no localStorage usage found
  Cat 3 (CSRF): PARTIAL — X-CSRFToken header set, but missing in multipart form requests
  ...

→ Cross-cutting:
  Auth model: CONSISTENT ✓ (httpOnly cookie Django ↔ credentials:include React)
  CSRF: PARTIAL — see Cat 3 above

→ SECURITY.md written
   Backend: 1 OPEN, 1 PARTIAL, 7 CLOSED
   Frontend: 0 OPEN, 1 PARTIAL, 8 CLOSED
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
