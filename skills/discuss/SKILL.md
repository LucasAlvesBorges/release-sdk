---
name: discuss
description: >
  Context-aware phase discussion. Detects phase type from ROADMAP.md, routes to backend-focused or
  frontend-focused questions, or runs both for fullstack phases. Locks D-XX decisions in CONTEXT.md.
  Use when: phase added to ROADMAP, ready to gather decisions before planning.
---

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation.

---

# /release:discuss — Context-Aware Phase Discussion

Detects phase type and asks the right questions. Produces CONTEXT.md with locked D-XX decisions.

## Usage

```
/release:discuss 01                  # auto-detect, ask questions, lock decisions
/release:discuss 01 --backend        # force backend discussion
/release:discuss 01 --frontend       # force frontend discussion
/release:discuss 01 --fullstack      # both question sets
```

## Detection

Same as `/release:plan` — reads ROADMAP.md phase goal + tags. Classifies as backend/frontend/fullstack.

## Pre-discussion assumptions probe (release:release-assumptions-analyzer)

**Immediately after stack detection, before the D-XX questioning loop**, spawn `release:release-assumptions-analyzer`:

```
Agent({
  subagent_type: "release:release-assumptions-analyzer",
  phase: "{NN}",
  slug: "{slug}",
  stack: "{django|react|fullstack}"  # pass-through from detection
})
```

The analyzer reads `{NN}-SPEC.md`, scans the codebase, and produces `.release-planning/phases/{NN}-{slug}/{NN}-ASSUMPTIONS.md` containing:
- Hidden assumptions (`A-XX`) with `file:line` evidence and HIGH/MED/LOW risk
- Recommended discuss prompts (`DP-XX`) — one per HIGH/MED assumption

**Skip rule:** if `{NN}-ASSUMPTIONS.md` already exists for the phase (analyzer ran in a prior session) → skip the spawn, but still read the file to include its DP-XX items in the question batch below.

**Integration with D-XX questioning:** before asking the dimension 1-10 questions, surface every `DP-XX` from ASSUMPTIONS.md to the user via `AskUserQuestion` as:

> *"Hidden assumption — confirm or override:"* {DP-XX question text + options}

The user's answer locks a corresponding `D-XX` in CONTEXT.md (cite the `A-XX` resolved). Then proceed to the standard backend/frontend/fullstack dimension questions for any decision not already locked by a DP-XX answer.

## Backend question dimensions (Django)

Spawns `release:django-discuss-orchestrator` for 10 dimensions:
1. Data model changes? (models, migrations, FK graph)
2. Multi-tenancy scope? (TenantModel, empresa filter)
3. Auth + permissions? (permission classes, roles)
4. Celery tasks? (.delay_on_commit strategy)
5. Bulk operations? (iterator, memray)
6. Concurrent mutations? (F(), select_for_update)
7. API contract? (serializer fields, pagination, filters)
8. Performance baseline? (select_related, prefetch_related targets)
9. Test strategy? (factories, test data)
10. Migration risk? (data migration, downtime)

## Frontend question dimensions (React)

Asks 10 React-specific dimensions:
1. New components? (list/form/modal/detail — which type)
2. State management? (new Zustand slice? or extend existing?)
3. Data fetching? (new TanStack Query key? cache strategy?)
4. Routing? (new route, nested, protected?)
5. Form handling? (react-hook-form + Zod schema shape)
6. API integration? (endpoint URL, request shape, response shape)
7. Error + loading UX? (skeleton design, error boundary placement)
8. Accessibility requirements? (keyboard nav, screen reader)
9. Test strategy? (RTL interactions to cover, MSW handlers needed)
10. TypeScript contracts? (new types/interfaces, Zod schemas)

## Fullstack

Runs both dimension sets. Groups decisions:
- `D-01` to `D-10` → backend decisions
- `D-11` to `D-20` → frontend decisions
- Integration decisions locked explicitly: API contract, auth model, error handling

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-CONTEXT.md

---
phase: {NN}
stack: backend | frontend | fullstack
---

# Phase {NN} Decisions

## Backend Decisions
D-01: [LOCKED] TenantModel required for InvoiceModel
D-02: [LOCKED] endpoint: GET /api/invoices/ with empresa filter + pagination

## Frontend Decisions
D-11: [LOCKED] New Zustand slice: invoiceStore (selectedId, filters)
D-12: [LOCKED] TanStack Query key: ['invoices', { filters }]
D-13: [LOCKED] Zod schema: InvoiceSchema { id, amount, status, createdAt }

## Integration Decisions
D-21: [LOCKED] API response uses camelCase (DRF CamelCaseRenderer)
D-22: [LOCKED] Auth: httpOnly cookie, Django CsrfViewMiddleware active
```

## Notes / Constraints

- v0.7.0 wires `release:release-assumptions-analyzer` BEFORE D-XX questioning. It produces `{NN}-ASSUMPTIONS.md` with DP-XX prompts; the orchestrator surfaces those DP-XX items first as "Hidden assumption — confirm or override:" questions, then proceeds to standard dimension questions. Skipped (file already read) if ASSUMPTIONS.md already exists.
