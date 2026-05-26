---
name: init
description: >
  Initialize a new project with release-sdk. Asks stack questions (Django / React TSX / fullstack),
  captures vision + architecture decisions, locks LOCK-01..LOCK-12 for full-stack projects.
  Produces PROJECT.md, ROADMAP.md, STATE.md, REQUIREMENTS.md.
  Use when: starting a new project from scratch.
---

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation.

---

# /release:init — Full-Stack Project Initialization

Captures project vision and architecture. Locks decisions as LOCK-XX in PROJECT.md.

> Importing from an existing GSD project? Use `/release:import` first to mass-port `.release-planning/` artifacts, then run `/release:init` to fill any remaining gaps.

## Usage

```
/release:init                        # interactive — asks all questions
/release:init --backend-only         # Django-only project (same as /django:init)
/release:init --frontend-only        # React-only project
```

> Previously: `--gsd-context` flag. Removed in v0.4.0 — use `/release:import` once to convert GSD planning files; all skills then assume release-sdk native format.

---

## Questions asked

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

## Output

```
.release-planning/
  PROJECT.md       # vision + LOCK-01..LOCK-12
  ROADMAP.md       # empty phases template
  REQUIREMENTS.md  # REQ-XX
  STATE.md         # cursor

CLAUDE.md          # root — delimited release-sdk block injected (created if missing)
```

## CLAUDE.md injection (always last step)

After `.release-planning/` writes succeed, inject a delimited block into the repo-root
`CLAUDE.md` so every future Claude Code session knows release-sdk is installed and where
the artifacts live.

Behavior:

1. If `CLAUDE.md` does NOT exist → create with a minimal header + the release-sdk block.
2. If `CLAUDE.md` exists AND contains `<!-- release-sdk:start -->` → replace only the
   delimited block; preserve everything else byte-for-byte.
3. If `CLAUDE.md` exists AND no delimited block → append the block at the end (two blank
   lines before it).

Block content (rendered with project name + stack from PROJECT.md):

```markdown
<!-- release-sdk:start -->
## release-sdk framework

This project uses **release-sdk** ({stack}). Planning artifacts live at
`.release-planning/`.

- LOCK-XX rules: `.release-planning/RELEASE-LOCKS.md`
- Active phase cursor: `.release-planning/STATE.md`
- Phase artifacts: `.release-planning/phases/{NN}-{slug}/`

Entry point: **`/release:auto <freeform intent>`** — routes to the right `/release:*`
skill (status / spec / discuss / plan / execute / review / verify / ui-phase / ai-phase /
secure-phase / debug / fast / quick / ship / import / workstreams / checklist).

GSD coexistence: if `.planning/` is also present, it belongs to upstream GSD and is
read-only from release-sdk's side. `/release:import` is the bridge.
<!-- release-sdk:end -->
```

Idempotent. Re-running `/release:init` updates the block in place without disturbing the
rest of `CLAUDE.md`.

## Example

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
→ Injecting release-sdk block into CLAUDE.md (created — no existing file)...

→ Done. Next: /release:roadmap  (decompose milestone into phases)
```
