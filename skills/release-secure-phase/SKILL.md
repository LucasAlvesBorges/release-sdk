---
description: >
  Retroactive (post-implementation) security audit. Reads the phase PLAN.md threat model and
  the author-time 9-category checklist, then greps shipped source/diff for evidence that
  every declared threat is actually mitigated. Routes .py files to release-django-security-retro
  and .tsx/.ts files to release-react-security-retro. Produces SECURITY.md scorecard.
  Use when: phase shipped, before merge to main, periodic post-merge verification, audit recovery.
  Distinct from /release:security (author-time, runs during planning/execution).
allowed_tools: Agent, Read, Write, Bash, Grep, Glob
---

# /release:secure-phase — Retroactive Threat Mitigation Audit

Runs AFTER a phase is implemented and committed. Verifies that every threat declared
in the phase PLAN.md `threat_model` block has a corresponding mitigation grep-provable
in the shipped code. Distinct from `/release:security` which is author-time guidance.

## Difference vs /release:security

| Axis | `/release:security` (author-time) | `/release:secure-phase` (retroactive) |
|---|---|---|
| When | During planning/execution | After phase ships |
| Input | Code currently being written | Frozen commits + PLAN.md threat model |
| Tone | Recommends mitigations | Verifies mitigations exist |
| Output | Inline guidance / SECURITY.md (open issues) | SECURITY.md scorecard (PASS/BLOCK/FLAG) |
| Modifies code | No (advisory) | No (read-only audit) |
| Agents | release-security-auditor / release-security-auditor | release-django-security-retro / release-react-security-retro |

## Usage

```
/release:secure-phase 01                         # audit phase 01 against its declared threat model
/release:secure-phase 01 --backend               # Django retro audit only
/release:secure-phase 01 --frontend              # React retro audit only
/release:secure-phase 01 --diff main..HEAD       # constrain evidence search to shipped diff
/release:secure-phase 01 --strict                # MISSING anywhere → BLOCK verdict
```

## Detection / Scope Resolution

1. Locate `.planning/phases/{NN}-{slug}/{NN}-PLAN.md`.
2. Parse `threat_model:` block from frontmatter (list of T-XX entries with category + plan).
3. Parse `{NN}-SUMMARY.md` for `stack:` field → `django`, `react-tsx`, or both.
4. Resolve files in scope:
   - Default: union of files touched in phase commits (`git log --name-only` between phase start and HEAD).
   - `--diff REV..REV`: explicit diff range.
5. Split by extension: `.py` → django retro agent, `.tsx/.ts` → react retro agent.
6. Run in parallel when both stacks present.

## Retroactive verification model

For each threat T-XX from PLAN.md frontmatter:

1. **Look up mitigation grep pattern** for its category (9-category matrix from `/release:security`).
2. **Run grep against shipped source** (scoped to files in step 4 above).
3. **Classify status:**
   - `MITIGATED` — grep matches evidence in shipped code AND (if applicable) test asserts attack blocked.
   - `PARTIAL` — code mitigation present but test missing OR test exists but weak/narrow.
   - `MISSING` — no code evidence (treated as BLOCKER for verdict).
   - `N/A` — category not applicable to this phase (e.g., no file upload → no MIME check).
4. **Record evidence** as `file:line` (mitigation) and `test_file::test_name` (test).
5. **Remediation block** populated only for MISSING / PARTIAL.

## Author-time checklist re-verification

If `<NN>-SECURITY.md` from author-time `/release:security` exists, cross-check:
- Categories marked CLOSED at author-time should still grep-prove MITIGATED at retro-time.
- Drift detection: anything that flipped CLOSED → MISSING is logged under "Regression" in scorecard.

## Django 9-category retro greps (backend)

| # | Category | Retro grep |
|---|----------|------------|
| 1 | Cross-Tenant Isolation | `TenantModel` inheritance, `get_queryset.*filter\(empresa=` |
| 2 | Intra-Tenant IDOR | `get_object_or_404.*owner=request.user`, ownership permission classes |
| 3 | Vertical Privilege Escalation | `permission_classes.*IsAdminUser`, `is_staff` guards |
| 4 | Mass Assignment | absence of `fields = '__all__'`, presence of `read_only_fields` |
| 5 | JWT Lifecycle | `BLACKLIST_AFTER_ROTATION`, `ROTATE_REFRESH_TOKENS`, blacklist on logout |
| 6 | Input Validation / Injection | absence of `.raw(.*f"`, `.extra(where=`, validators on serializer fields |
| 7 | Auth State Transitions | single-use reset tokens, `AnonRateThrottle` on login |
| 8 | CSRF | `CsrfViewMiddleware`, no `@csrf_exempt` on session-auth views, `ALLOWED_HOSTS` set |
| 9 | Cookie / Token Security | `HttpOnly` + `Secure` + `SameSite`, `SESSION_COOKIE_SECURE`, CORS allowlist (no `CORS_ALLOW_ALL_ORIGINS = True`) |

Plus N+1 spot-check (perf-as-security signal): grep for `select_related` / `prefetch_related` on listed querysets.

## React 9-category retro greps (frontend)

| # | Category | Retro grep |
|---|----------|------------|
| 1 | XSS Prevention | no raw `dangerouslySetInnerHTML`, no `.innerHTML =`, `DOMPurify`/`rehype-sanitize` present where needed |
| 2 | Auth Token Storage | no `localStorage\.setItem.*token`, no `sessionStorage\.setItem.*token` |
| 3 | CSRF Plumbing | `X-CSRFToken` header set in API client, `credentials: 'include'` / `withCredentials: true` |
| 4 | Client-side IDOR | no `?user_id=` from URL parsed and passed to API, auth via session cookie |
| 5 | API Key / Secret Exposure | no `VITE_.*SECRET`, no hardcoded keys (>= 16 char base64-ish in source) |
| 6 | Content Injection | sanitizer applied before any Markdown/HTML render |
| 7 | Open Redirects / eval | no `eval(`, no `new Function(`, no `location.href = userInput` |
| 8 | Sensitive Data Logging | no `console.log(user)`, no `console.log(response)` containing tokens |
| 9 | Input Validation (Zod) | Zod schemas on every form + API response, content sniffing flags reviewed |

Plus dependency CVE flag: pull `npm audit --json` summary if available (informational, not BLOCKER).

## Full-stack cross-cutting retro checks

When both stacks shipped:
- Auth model coherence: Django sets `HttpOnly` cookie AND React never reads tokens.
- CSRF coherence: Django middleware enabled AND React sends `X-CSRFToken`.
- Permission depth: Django permission class for endpoint X corresponds to a React route guard.
- Drift: anything that changed status between author-time SECURITY.md and retro SECURITY.md.

## Output

```
.planning/phases/{NN}-{slug}/{NN}-SECURITY.md
```

Scorecard table format (see `templates/SECURITY.md`):
- One row per declared threat T-XX (and one per untracked category audited).
- Columns: Category | Threat | Status | Evidence (file:line) | Remediation.
- Overall Verdict: `PASS` (all MITIGATED or N/A), `FLAG` (any PARTIAL, no MISSING), `BLOCK` (any MISSING).
- Action Items: concrete fixes for every non-MITIGATED row.

## Routing

- `.py` in scope → spawn `release-django-security-retro` agent.
- `.tsx`/`.ts` in scope → spawn `release-react-security-retro` agent.
- Merge agent outputs into single SECURITY.md with per-stack sections + cross-cutting block.

## Constraints

- Read-only: never edits source, migrations, settings, tests, or commits.
- Evidence must be `file:line`. No claims without grep proof.
- Status values restricted to: `MITIGATED`, `PARTIAL`, `MISSING`, `N/A`.
- Never auto-commits SECURITY.md (left as working-tree artifact for review).

## Example

```
/release:secure-phase 01

→ Phase: 01-invoices-crud
→ Stack: FULLSTACK (django + react-tsx)
→ Threat model: 9 declared threats (T-01 .. T-09)
→ Scope: 7 files (3 .py, 4 .tsx) from a1b2c3..HEAD

→ Backend retro audit (release-django-security-retro)...
  T-01 (cross_tenant): MITIGATED — backend/apps/financeiro/views.py:42 (filter empresa=...)
  T-04 (mass_assignment): MISSING — fields = '__all__' at backend/apps/financeiro/serializers.py:18

→ Frontend retro audit (release-react-security-retro)...
  T-08 (token_storage): MITIGATED — no localStorage.setItem token found
  T-03 (csrf): PARTIAL — X-CSRFToken sent on JSON but absent on multipart at src/api/upload.ts:24

→ Cross-cutting:
  Auth coherence: CONSISTENT
  Drift: T-04 was CLOSED at author-time SECURITY.md → MISSING now (regression)

→ SECURITY.md written
   Verdict: BLOCK (1 MISSING, 1 PARTIAL, 1 REGRESSION)
   Action items: 2
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
