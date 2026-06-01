---
name: security
description: >
  Context-aware 9-category security audit PLUS an always-on advanced-threat audit. Routes .py
  files to release-security-auditor and .tsx/.ts files to release-security-auditor, and ALWAYS
  spawns release-advanced-threat-auditor in parallel (A1-A13 Django + RA1-RA5 React: race/TOCTOU,
  SSRF, deserialization, command injection, SSTI, XXE, JWT forgery, exploitation-grade SQLi,
  image/media DoS+RCE, AWS cloud-infra incl. IaC static checks). Produces one unified SECURITY.md.
  Use when: feature complete, pre-merge, or periodic security review.
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
3. **ALWAYS** spawn `release-advanced-threat-auditor` over the SAME resolved scope, regardless of
   detected surface (it is never conditional on a trigger surface being present). It runs in
   PARALLEL with the 9-category `release-security-auditor` pass.
4. Run all auditors in parallel; their findings merge into ONE SECURITY.md (the advanced auditor
   APPENDS its `## Advanced Threat Audit` section to the same per-phase SECURITY.md — no separate file).
5. Merge into SECURITY.md with per-stack category tables.

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
  ## Advanced Threat Audit            ← appended by release-advanced-threat-auditor (always-on)
    ### Django Advanced (A1-A13)
      | Cat | Threat | Status | Evidence |
      A1 SSRF · A2 Deserialization · A3 Command Injection · A4 SSTI/Path-Traversal ·
      A5 XXE/Header-Log Injection · A6 ORM-level Injection · A7 Concurrency/TOCTOU/idempotency ·
      A8 JWT Forgery & Auth-Identity · A9 Constant-Time/Signed-Payload · A10 Transport/Headers/CORS ·
      A11 SQLi (exploitation-grade) · A12 Image/Media DoS+RCE · A13 AWS Cloud-Infra
    ### React Advanced (RA1-RA5)
      | Cat | Threat | Status | Evidence |
      RA1 URL-scheme/DOM sinks · RA2 postMessage/client-SSRF · RA3 CSP/Trusted-Types ·
      RA4 Build/supply-chain · RA5 SSR/hydration/DOM-clobbering/JSON-hijacking
    ### Advanced Open Issues (BLOCKER)
      ...auto-OPEN triggers + remediation...
```

Evidence model in the Advanced Threat Audit section is split:
- Most categories are **[pytest]** — proven by a runtime test asserting DATA-LAYER / behavioral impact
  (sentinel row survives, row-count baseline, wall-time < 1s, zero outbound egress), cited as `file::test_name`.
  A test whose ONLY assertion is an HTTP status code (e.g. `assert r.status_code in (201, 400)`) is HOLLOW
  and is itself a finding — it accepts a STORED payload and manufactures a false PASS.
- The AWS half of **A13** (sub-cats A13.2/.4/.6/.7/.9/.10, and parts of .1/.8) is **[IaC/CSPM static]** —
  proven by a passing `check_*` static gate over `terraform/*.tf`, `serverless.yml`, `cdk/`, policy JSON,
  `settings.py`, `.env` (tfsec/checkov/conftest/CI grep), NOT a pytest. Evidence is cited as the `check_*` name.

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

→ Advanced threat audit (release-advanced-threat-auditor, always-on)...
  Cat A1 (SSRF): OPEN — requests.get(user_url) at services/preview.py:34 with no link-local denylist
  Cat A7 (TOCTOU): OPEN — coupon.is_valid()→coupon.redeem() outside select_for_update/atomic; no race test
  Cat A11 (SQLi): OPEN — ?ordering reaches .order_by() with no allowlist; only test asserts status (HOLLOW)
  Cat A13.1 (IMDS): OPEN [IaC] — launch template http_tokens not "required" (check_imds_v2_required FAIL)
  Cat A13.2 (S3 public): OPEN [IaC] — bucket policy Principal:"*" unconditioned (check_no_wildcard_principal FAIL)
  Cat RA1 (URL-scheme): PARTIAL — href={userUrl} has no scheme allowlist; test_dynamic_href_rejects_javascript_scheme missing

→ SECURITY.md written
   Backend: 1 OPEN, 1 PARTIAL, 7 CLOSED
   Frontend: 0 OPEN, 1 PARTIAL, 8 CLOSED
   Advanced: 5 OPEN (3 [pytest], 2 [IaC static]), 1 PARTIAL — see ## Advanced Threat Audit
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.

In addition to the stack-dispatched `release-security-auditor`, this skill ALWAYS spawns `release-advanced-threat-auditor` over the same scope (it is unconditional — never gated on a detected trigger surface) and runs it in parallel. It applies the matching stack's advanced catalog (Django A1-A13 / React RA1-RA5) and appends its `## Advanced Threat Audit` section to the same SECURITY.md.
