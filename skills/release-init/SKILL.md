---
description: >
  Initialize a new project with release-sdk. Asks stack questions (Django / React TSX / fullstack),
  captures vision + architecture decisions, locks LOCK-01..LOCK-12 for full-stack projects.
  Produces PROJECT.md, ROADMAP.md, STATE.md, REQUIREMENTS.md.
  Use when: starting a new project OR importing an existing GSD project with --gsd-context.
allowed_tools: Agent, Read, Write, Bash, Grep, Glob
---

# /release:init — Full-Stack Project Initialization

Captures project vision and architecture. Locks decisions as LOCK-XX in PROJECT.md.

## Usage

```
/release:init                        # interactive — asks all questions
/release:init --backend-only         # Django-only project (same as /django:init)
/release:init --frontend-only        # React-only project
/release:init --gsd-context          # import from existing GSD .planning/ — skips answered questions
```

---

## GSD Context Mode (`--gsd-context`)

Use when the project already has GSD installed and `.planning/` exists.
Reads GSD artifacts, extracts architecture decisions, maps to LOCK-XX, asks only about gaps.

### Step 1 — Verify GSD presence

```bash
ls .planning/
```

If `.planning/` or `.planning/PROJECT.md` not found → abort with:
> "GSD planning directory not found. Run `/release:init` (no flags) for a fresh project."

### Step 2 — Read GSD artifacts in parallel

Read ALL of these that exist (skip gracefully if missing):

| File | Extracts |
|---|---|
| `.planning/PROJECT.md` | project name, domain, multi-tenancy, auth model, team, requirements |
| `.planning/codebase/STACK.md` | full stack versions (backend + frontend + testing) |
| `.planning/codebase/ARCHITECTURE.md` | patterns, API contract, tenancy strategy |
| `.planning/codebase/CONVENTIONS.md` | ORM rules, serializer rules, forbidden patterns |
| `.planning/codebase/TESTING.md` | test framework, test strategy |
| `.planning/ROADMAP.md` (first 80 lines) | milestone/phase overview |
| `.planning/config.json` | GSD config (branching strategy, workflow flags) |

### Step 3 — Extract and map to LOCKs

For each LOCK, extract from the files above. Mark as `[EXTRACTED]`, `[INFERRED]`, or `[MISSING]`.

| LOCK | Source file | What to look for |
|---|---|---|
| LOCK-01 | STACK.md | Django version, DRF version, Python version |
| LOCK-02 | PROJECT.md + ARCHITECTURE.md | `empresa_id`, `TenantModel`, `django-rls`, multi-tenancy pattern |
| LOCK-03 | PROJECT.md + ARCHITECTURE.md | JWT, httpOnly cookie, session, token header, auth strategy |
| LOCK-04 | STACK.md | Celery version, Redis, `.delay()` vs `.delay_on_commit()` rule |
| LOCK-05 | CONVENTIONS.md + ARCHITECTURE.md | `select_related`/`prefetch_related` requirement, N+1 policy |
| LOCK-06 | CONVENTIONS.md | `fields = '__all__'` forbidden rule, serializer explicitness |
| LOCK-07 | STACK.md | React version, Vite/Next.js, TypeScript version, shadcn/MUI/none |
| LOCK-08 | STACK.md | Zustand, TanStack Query, Redux, context-only |
| LOCK-09 | PROJECT.md + ARCHITECTURE.md | httpOnly cookie only, localStorage tokens forbidden |
| LOCK-10 | STACK.md + CONVENTIONS.md | `strict` TypeScript, `any` forbidden, Zod for API responses |
| LOCK-11 | STACK.md + TESTING.md | Vitest, pytest, RTL, MSW, factory-boy |
| LOCK-12 | ARCHITECTURE.md + CONVENTIONS.md | snake_case backend, camelCase frontend, Axios interceptor |

### Step 4 — Present extraction report

Show user a table of what was found:

```
GSD Context Import — Extraction Report
════════════════════════════════════════
Project: [name from PROJECT.md]

LOCK-01  [EXTRACTED]  Django 5.2 + DRF 3.16 + Python 3.12
LOCK-02  [EXTRACTED]  Multi-tenant: empresa_id via TenantModel + django-rls
LOCK-03  [EXTRACTED]  Auth: JWT httpOnly cookie + X-CSRFToken
LOCK-04  [EXTRACTED]  Celery 5.x + Redis; .delay_on_commit() mandatory
LOCK-05  [INFERRED]   N+1 policy not explicit — will confirm
LOCK-06  [EXTRACTED]  fields='__all__' forbidden (from CONVENTIONS.md)
LOCK-07  [EXTRACTED]  React 19 + Vite + TypeScript 5.7 + shadcn/ui
LOCK-08  [EXTRACTED]  Zustand 5 (client) + TanStack Query 5 (server)
LOCK-09  [EXTRACTED]  httpOnly cookie only; localStorage tokens = BLOCKER
LOCK-10  [EXTRACTED]  TypeScript strict; no `any`; Zod 4 for API responses
LOCK-11  [EXTRACTED]  pytest + Vitest + RTL + MSW + factory-boy
LOCK-12  [MISSING]    API contract (snake_case↔camelCase) — will ask
════════════════════════════════════════
```

### Step 5 — Ask only about gaps

For each `[MISSING]` or `[INFERRED]` LOCK, ask ONE targeted question. Do not re-ask about `[EXTRACTED]` items.

Example gap questions:
- LOCK-05 `[INFERRED]`: "Is N+1 detection enforced? (select_related/prefetch required, N+1 = BLOCKER?)"
- LOCK-12 `[MISSING]`: "API response format — does Django return snake_case and the frontend transforms to camelCase via Axios interceptor?"

### Step 6 — Write output

Write `.planning/RELEASE-LOCKS.md` — do NOT overwrite existing GSD files (PROJECT.md, ROADMAP.md, STATE.md).

```markdown
# Release SDK — Architecture Locks
<!-- Generated by /release:init --gsd-context on {date} -->
<!-- Source: GSD .planning/ artifacts -->

## LOCK-01 — Backend Stack
Django 5.2 + DRF 3.16 + Python 3.12

## LOCK-02 — Multi-Tenancy
...

## LOCK-03 — Auth Model
...

[... all 12 LOCKs ...]

## GSD Integration Notes
- GSD config: .planning/config.json (mode: {mode}, granularity: {granularity})
- Branching: {branch_strategy}
- Active phase: {from STATE.md if readable}
- Phases overview: {milestone count} milestones, {phase count} phases in ROADMAP.md

## Release SDK Usage
Skills use LOCK values from this file as authoritative constraints.
/release:plan, /release:execute, /release:review will enforce these LOCKs.
```

### Step 7 — Output summary

```
✓ GSD context imported
✓ LOCK-01..LOCK-12 locked in .planning/RELEASE-LOCKS.md

GSD files untouched: PROJECT.md, ROADMAP.md, STATE.md

Next steps:
  /release:plan    → plan next phase (reads GSD ROADMAP.md for phase context)
  /release:review  → review changed files against LOCKs
  /release:execute → execute current GSD phase plan with TDD enforcement
```

---

## Standard Mode (no flags)

### Questions asked

#### 1. Project identity
- Project name, domain, target users
- Team size (solo, small team)

#### 2. Stack selection
- Backend: Django + DRF? (versions, Python version)
- Frontend: React + TSX? (Vite or Next.js, React Router version)
- Database: PostgreSQL? Redis?

#### 3. Backend architecture (if Django)
- Multi-tenancy? (empresa_id isolation, django-rls)
- Auth model: JWT httpOnly cookie / session / token header
- Celery + Redis? Worker strategy?
- API style: DRF ViewSet / APIView / mixed
- OpenAPI docs: drf-spectacular?

#### 4. Frontend architecture (if React)
- State management: Zustand + TanStack Query (default)
- Routing: React Router v6 / TanStack Router / Next.js App Router
- Form library: react-hook-form + zod (default)
- Component library: shadcn/ui / MUI / custom / none
- Test framework: Vitest + RTL (default)

#### 5. Full-stack integration (if both)
- API convention: REST / GraphQL
- Response format: snake_case (Django) + camelCase transform (Axios interceptor)?
- Auth cookie strategy: same-domain or CORS?
- CSRF strategy: Cookie-to-header (csrftoken → X-CSRFToken)

#### 6. Forbidden patterns (project-level LOCK)
- Backend: `fields = '__all__'`? Direct `.delay()`?
- Frontend: `localStorage` for auth tokens? `any` TypeScript?
- Both: Unreviewed raw SQL? Hardcoded secrets?

## Locks produced

| LOCK | Domain | Example |
|---|---|---|
| LOCK-01 | Backend stack | Django 5.2 + DRF 3.16 + Python 3.12 |
| LOCK-02 | Multi-tenancy | empresa_id via django-rls, TenantModel required |
| LOCK-03 | Auth model | JWT httpOnly cookie + X-CSRFToken header |
| LOCK-04 | Celery | .delay_on_commit() mandatory; .delay() = BLOCKER |
| LOCK-05 | ORM | select_related/prefetch required; N+1 = BLOCKER |
| LOCK-06 | Mass assignment | fields = '__all__' forbidden = BLOCKER |
| LOCK-07 | Frontend stack | React 18 + Vite + TypeScript strict |
| LOCK-08 | State management | Zustand (client) + TanStack Query (server) |
| LOCK-09 | Frontend auth | httpOnly cookie only; localStorage tokens = BLOCKER |
| LOCK-10 | Type safety | no `any`; Zod for API responses = BLOCKER if missing |
| LOCK-11 | Tests | Vitest + RTL; MSW for API mocks |
| LOCK-12 | API contract | snake_case backend, camelCase frontend via interceptor |

## Standard Output

```
.planning/
  PROJECT.md       # vision + LOCK-01..LOCK-12
  ROADMAP.md       # empty phases template
  REQUIREMENTS.md  # REQ-XX
  STATE.md         # cursor
```

## Example (standard mode)

```
/release:init

→ What is the project? "Invoice management SaaS for logistics companies"
→ Backend: Django 5.2 + DRF
→ Frontend: React 18 + Vite + TSX
→ Multi-tenant: YES (empresa_id)
→ Auth: JWT httpOnly cookie
→ State: Zustand + TanStack Query
→ Forbidden: fields='__all__', localStorage tokens, any type

→ Writing PROJECT.md (LOCK-01 to LOCK-12)...
→ Writing ROADMAP.md (template)...
→ Writing STATE.md...
→ Writing REQUIREMENTS.md...

→ Done. Next: /release:roadmap  (decompose milestone into phases)
```
