<!--
# SECURITY.md — Retroactive Security Scorecard
#
# Produced by /release:secure-phase AFTER a phase has shipped.
# Written by django-security-retro and/or release-react-security-retro agents.
# Distinct from author-time guidance produced by /release:security.
#
# Read-only audit: this file is the ONLY artifact the retro auditors are allowed to create.
# No source files, settings, tests, or migrations may be edited during the audit.
-->

---
phase: {NN}
slug: {phase-slug}
audited_at: {YYYY-MM-DDTHH:MM:SSZ}
stack: {django | react-tsx | fullstack}
diff_range: {git_rev_a..git_rev_b}        # commits in scope for evidence search
auditors:
  - django-security-retro          # if stack includes django
  - release-react-security-retro           # if stack includes react-tsx
verdict: {PASS | FLAG | BLOCK}
totals:
  mitigated: {N}
  partial: {N}
  missing: {N}
  not_applicable: {N}
regressions: {N}                            # categories that flipped CLOSED→MISSING vs author-time SECURITY.md
---

# Retroactive Security Scorecard — Phase {NN}: {phase-name}

**Audited at:** {YYYY-MM-DD HH:MM UTC}
**Stack:** {django | react-tsx | fullstack}
**Scope:** {N} files in commit range `{rev_a..rev_b}`
**Verdict:** **{PASS | FLAG | BLOCK}**

> **PASS** — every declared threat MITIGATED (or justified N/A); safe to merge.
> **FLAG** — no MISSING but at least one PARTIAL; merge allowed with review acknowledgement.
> **BLOCK** — at least one declared threat MISSING, or at least one regression vs author-time SECURITY.md; merge gated until Action Items resolved.

---

## 9-Category Scorecard

### Backend (Django) — _omit if frontend-only phase_

| # | Category | Threat ID | Status | Evidence (file:line) | Remediation |
|---|----------|-----------|--------|----------------------|-------------|
| 1 | Cross-Tenant Isolation | T-XX | MITIGATED \| PARTIAL \| MISSING \| N/A | `backend/apps/{app}/views.py:42` | — _(or concrete fix)_ |
| 2 | Intra-Tenant IDOR | T-XX | … | `backend/apps/{app}/views.py:NN` | … |
| 3 | Vertical Privilege Escalation | T-XX | … | … | … |
| 4 | Mass Assignment | T-XX | … | `backend/apps/{app}/serializers.py:NN` | … |
| 5 | JWT Lifecycle | T-XX | … | `backend/settings/base.py:NN` | … |
| 6 | Input Validation / Injection (+ N+1) | T-XX | … | `backend/apps/{app}/views.py:NN` | … |
| 7 | Auth State Transitions | T-XX | … | … | … |
| 8 | CSRF / ALLOWED_HOSTS | T-XX | … | `backend/settings/base.py:NN` | … |
| 9 | Cookie / Token Security / CORS | T-XX | … | `backend/settings/base.py:NN` | … |

_Undeclared categories audited (rows with note `undeclared_in_plan` or `unregistered_surface`):_

| # | Category | Status | Evidence | Note |
|---|----------|--------|----------|------|
| _ | _ | _ | _ | _ |

### Frontend (React/TSX) — _omit if backend-only phase_

| # | Category | Threat ID | Status | Evidence (file:line) | Remediation |
|---|----------|-----------|--------|----------------------|-------------|
| 1 | XSS Prevention | T-XX | … | `src/features/{Feature}/{Component}.tsx:NN` | … |
| 2 | Auth Token Storage | T-XX | … | _no localStorage token write found_ | — |
| 3 | CSRF Plumbing | T-XX | … | `src/api/client.ts:NN` | … |
| 4 | Client-side IDOR | T-XX | … | … | … |
| 5 | API Key / Secret Exposure | T-XX | … | `src/config.ts:NN` (+ `npm audit` summary) | … |
| 6 | Content Injection (Markdown) | T-XX | … | … | … |
| 7 | eval / Open Redirect / Unsafe Sinks | T-XX | … | `src/routes/{Route}.tsx:NN` | … |
| 8 | Sensitive Data Logging | T-XX | … | … | … |
| 9 | Input Validation (Zod runtime) | T-XX | … | `src/features/{Feature}/schema.ts:NN` | … |

_Undeclared categories audited:_

| # | Category | Status | Evidence | Note |
|---|----------|--------|----------|------|
| _ | _ | _ | _ | _ |

---

## Full-Stack Cross-Cutting (fullstack phases only)

| Check | Status | Evidence |
|-------|--------|----------|
| Auth model coherence: Django HttpOnly cookie ↔ React never reads tokens | {MITIGATED \| PARTIAL \| MISSING} | _both stack rows above_ |
| CSRF coherence: Django `CsrfViewMiddleware` enabled ↔ React sends `X-CSRFToken` | … | … |
| Permission depth: every Django permission_class has a matching React route guard | … | … |

---

## Drift vs Author-Time `SECURITY.md`

_Populated only when an earlier author-time `SECURITY.md` (from `/release:security`) exists. Omit otherwise._

| Category | Author-time status | Retro status | Drift |
|----------|--------------------|--------------|-------|
| 4. Mass Assignment | CLOSED | MISSING | **REGRESSION** _(BLOCKER)_ |
| 8. CSRF | OPEN | MITIGATED | fixed |
| 9. Cookie Security | PARTIAL | MITIGATED | closed |

---

## Action Items

_One bullet per non-MITIGATED row. Concrete, code-level, executable. Used by `/release:execute` resume-mode or follow-up phase planning._

- [ ] **[BLOCK] T-04 / Mass Assignment** — Replace `fields = '__all__'` at `backend/apps/financeiro/serializers.py:18` with explicit list `['codigo', 'descricao', 'valor', 'empresa', 'created_at', 'usuario']`; add `read_only_fields = ['empresa', 'created_at', 'usuario']`; add test `test_mass_assignment_blocked` (POST with `is_staff: True` + `empresa: <other>` → both fields ignored).
- [ ] **[FLAG] T-03 / CSRF Plumbing (frontend)** — CSRF header sent on JSON requests but absent on multipart at `src/api/upload.ts:24`; add header in axios `transformRequest` for FormData branch.
- [ ] **[FLAG] Category 5 / Dependency CVE (informational)** — `npm audit` reports 2 HIGH CVEs in transitive deps (`xxx@1.2.3`, `yyy@4.5.6`); bump or pin.

---

## Verdict Rationale

{1–2 sentences explaining why verdict is PASS / FLAG / BLOCK. Cite the specific MISSING / regression that drove BLOCK, or the PARTIAL row(s) that drove FLAG.}

---

_Audited by release-secure-phase (release-sdk). Read-only artifact — never commit changes to source from this audit. To resolve BLOCK items, plan a follow-up phase or resume the current one via `/release:execute`._
