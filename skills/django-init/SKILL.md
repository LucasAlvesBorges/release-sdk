---
description: >
  Initialize .planning/ structure for a new Django project. Creates PROJECT.md (vision + LOCK-XX),
  ROADMAP.md, STATE.md, REQUIREMENTS.md from templates. Asks user about Django version, multi-tenancy,
  auth strategy, and other project-level locks. Foundation for all subsequent /django:* workflows.
  Use when: starting a new Django project, or adopting django-sdk in existing project for first time.
allowed_tools: Agent, Read, Write, Bash, AskUserQuestion
---

# /django:init — Initialize Project Planning

Scaffolds `.planning/` directory with PROJECT.md, ROADMAP.md, STATE.md, REQUIREMENTS.md. Locks project-level architectural decisions that all subsequent planning honors.

## Usage

```
/django:init
/django:init --vision="Multi-tenant ERP for bus companies"
```

## Arguments

- `--vision=...` — Skip vision-gathering prompt
- `--existing` — Adopt for project with existing .planning/ from another tool (audit + merge)

## Workflow

1. Check `.planning/` doesn't already exist (else suggest `/django:roadmap` instead).
2. Spawn `django-discuss-orchestrator` in INIT MODE — asks user:
   - Project vision (one-paragraph)
   - Domain (industry / use case)
   - Core value invariant (single most important thing)
   - Django version preference (5.2 LTS default)
   - Multi-tenant? (Y/N — almost always Y)
   - Auth strategy (JWT cookie? Session? Both?)
   - Frontend stack (React+Vite default, or specify)
   - TDD discipline (mandatory by default)
3. Translate answers to PROJECT.md LOCK-01 to LOCK-10.
4. Asks: "Do you have initial requirements? (Y → batch entry / N → skip, add later)".
5. If Y: gather REQ-01 to REQ-NN.
6. Spawn `django-roadmapper` to scaffold ROADMAP.md from REQUIREMENTS.md.
7. Create STATE.md with empty cursor.
8. Commit:
   ```
   docs: initialize django-sdk planning ({N} requirements, {M} phases)
   ```

## Output

```
.planning/
├── PROJECT.md          # vision + LOCK-01 to LOCK-10 + Author Checklist (LOCKED)
├── ROADMAP.md          # phase list with goal, success_criteria, depends_on
├── REQUIREMENTS.md     # REQ-XX atomic requirements
├── STATE.md            # cursor (active_phase=null initially)
└── phases/             # populated per /django:phase add
```

## What's locked

Once `/django:init` completes, these are LOCKED:
- Backend stack (Django version, DRF version, PostgreSQL, Celery)
- Frontend stack (React, Vite, Tailwind, shadcn, TanStack, Zustand)
- Multi-tenancy strategy (TenantModel + django-rls)
- Auth (simplejwt + cookie)
- UUID PKs on all custom models
- TDD discipline
- 9 security categories per feature
- Forbidden patterns (`fields='__all__'`, `.delay()`, etc)
- Author Checklist Q1-Q7 (Q6 LOCKED always)

Changing locks later requires explicit migration plan + team alignment.

## Example

```
/django:init

→ "What's the project vision?"
  > "Multi-tenant ERP for urban bus transport companies"

→ "Domain?"
  > "Public transportation operations management"

→ "Core value invariant?"
  > "Total data isolation between empresas — never leak data across tenants"

→ "Django version?"
  > 5.2 LTS [default — accepts Enter]

→ "Multi-tenant?"
  > Yes, TenantModel + django-rls + 5-layer isolation [default]

→ "Add initial requirements?"
  > Yes: REQ-01 Veiculo CRUD, REQ-02 Bulk import, REQ-03 Daily fueling, ...

→ Spawning django-roadmapper...
  → Roadmap with 5 phases scaffolded.

→ Committed: docs: initialize django-sdk planning (8 requirements, 5 phases)

→ Next: /django:discuss 01 — gather decisions for Phase 01 (foundation)
```
