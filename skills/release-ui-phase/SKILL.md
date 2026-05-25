---
description: >
  Frontend design contract generator. Produces UI-SPEC.md BEFORE React TDD coding starts —
  component inventory, routes, state contracts (loading/empty/error/success), a11y contract,
  performance budgets, Zustand/TanStack Query patterns, optimistic UI plan.
  Detects existing design system (tailwind, shadcn, MUI) and locks tokens.
  Use when: phase is frontend or fullstack AND no UI-SPEC.md exists yet. Refuses backend-only phases.
allowed_tools: Agent, Read, Write, Bash, Grep, Glob, AskUserQuestion
---

# /release:ui-phase — React TSX Design Contract

Generates `UI-SPEC.md` for a React phase: a design contract the TDD executor honors before any
component or test is written. Mirrors the upstream `gsd-ui-phase` flow, stack-locked to the
release-sdk React defaults (LOCK-07..LOCK-12).

## Usage

```
/release:ui-phase 03                 # auto-detect phase, gather, produce UI-SPEC.md
/release:ui-phase 03 --frontend      # force frontend pipeline (skip stack detection)
/release:ui-phase 03 --fullstack     # treat phase as fullstack — produce frontend-only spec
/release:ui-phase 03 --revise        # re-run with prior UI-SPEC.md as input
```

> Previously: `--gsd-context` flag. Removed in v0.4.0 — use `/release:import` once to convert GSD planning files; all skills then assume release-sdk native format.

## Stack guard — React only

This skill MUST refuse backend-only phases.

1. Read `.planning/ROADMAP.md` → extract phase goal and tags.
2. If `.planning/phases/{NN}-{slug}/{NN}-CONTEXT.md` exists → read `stack:` frontmatter.
3. Classify (same signal logic as `/release:plan`):

| Signal | Classification | Action |
|---|---|---|
| component, UI, React, page, form, screen, modal, table, dashboard, route | `frontend` | proceed |
| `frontend` or `fullstack` in CONTEXT.md frontmatter | proceed | proceed |
| API, endpoint, model, serializer, migration, Celery, queryset, ONLY | `backend` | **refuse** |
| Both signal sets present | `fullstack` | proceed (frontend-only output) |
| Neither clear | ask user via AskUserQuestion | proceed if user confirms React surface |

4. `--frontend` / `--fullstack` overrides detection. `--backend` flag is rejected.

### Refusal message (backend-only phase)

If detection resolves to backend OR user confirms phase has no UI surface:

> Phase {NN} appears to be backend-only — no React TSX surface detected.
> `/release:ui-phase` is React-only by design.
>
> If you need a backend contract: run `/release:spec {NN}` (requirements) or
> `/release:plan {NN} --django` (Django planning).
>
> If you believe the phase does have a frontend surface, re-run with
> `/release:ui-phase {NN} --frontend` to force the pipeline.

Exit cleanly. Do not write any artifact.

---

## Workflow (frontend / fullstack)

### Step 1 — Load context

Read in parallel (skip gracefully if missing):

| File | Used for |
|---|---|
| `.planning/RELEASE-LOCKS.md` *(if present)* | LOCK-07..LOCK-12 (frontend stack, state, auth, types, tests, contract) |
| `.planning/PROJECT.md` *(fallback)* | LOCK-07..LOCK-12 if no RELEASE-LOCKS.md |
| `.planning/ROADMAP.md` | phase goal, tags |
| `.planning/phases/{NN}-{slug}/{NN}-SPEC.md` *(if present)* | WHAT the phase delivers |
| `.planning/phases/{NN}-{slug}/{NN}-CONTEXT.md` *(if present)* | locked D-XX decisions (especially D-11..D-20 frontend bucket) |
| `.planning/phases/{NN}-{slug}/{NN}-RESEARCH-FRONTEND.md` *(if present)* | researcher output |

RELEASE-LOCKS.md takes precedence over PROJECT.md when both exist (same precedence rule as
`/release:plan`).

### Step 2 — Detect existing design system

Probe the repo for the established frontend stack so the spec aligns with reality, not defaults:

```bash
# tailwind
ls tailwind.config.* 2>/dev/null
test -f postcss.config.js && grep -l tailwindcss postcss.config.js 2>/dev/null

# shadcn/ui
test -f components.json && cat components.json
find src -type d -name "ui" 2>/dev/null | head -5

# MUI
grep -l "@mui/material" package.json 2>/dev/null

# component library hints
grep -E '"@mui|"@chakra|"@mantine|"@radix-ui|"shadcn|"tailwindcss"' package.json 2>/dev/null

# routing
grep -E '"react-router|"@tanstack/react-router|"next"' package.json 2>/dev/null

# forms
grep -E '"react-hook-form|"formik|"zod"' package.json 2>/dev/null

# state
grep -E '"zustand|"@tanstack/react-query|"jotai|"redux"' package.json 2>/dev/null
```

Populate a detected-stack table. Mark each row `EXTRACTED` / `INFERRED` / `MISSING`.

### Step 3 — Route to `release-ui-researcher` agent

Spawn the agent with these inputs:

```yaml
phase_number: "{NN}"
phase_dir: ".planning/phases/{NN}-{slug}"
required_reading:
  - .planning/RELEASE-LOCKS.md OR .planning/PROJECT.md
  - .planning/phases/{NN}-{slug}/{NN}-SPEC.md (if exists)
  - .planning/phases/{NN}-{slug}/{NN}-CONTEXT.md (if exists)
  - .planning/phases/{NN}-{slug}/{NN}-RESEARCH-FRONTEND.md (if exists)
detected_stack:
  routing: react-router-v6 | tanstack-router | next-app | UNKNOWN
  styling: tailwind | shadcn | mui | chakra | mantine | custom | UNKNOWN
  state_client: zustand | redux | jotai | context | UNKNOWN
  state_server: tanstack-query-v5 | swr | custom | UNKNOWN
  forms: react-hook-form+zod | formik | native | UNKNOWN
  tests: vitest+rtl+msw | jest+rtl | UNKNOWN
locks:
  LOCK-07: "{frontend stack value}"
  LOCK-08: "{state mgmt value}"
  LOCK-09: "{auth storage value}"
  LOCK-10: "{type safety value}"
  LOCK-11: "{test framework value}"
  LOCK-12: "{API contract value}"
```

The agent (`release-ui-researcher`) will:
1. Read all required reading.
2. Probe component inventory, routes, states currently in repo.
3. Use `AskUserQuestion` for ONLY unanswered dimensions (skip anything locked in CONTEXT.md D-11..D-20 or LOCK-07..LOCK-12).
4. Produce `{NN}-UI-SPEC.md` from `templates/UI-SPEC.md`.

### Step 4 — Output

```
.planning/phases/{NN}-{slug}/
  {NN}-UI-SPEC.md           # design contract (component inventory, states, a11y, perf, optimistic)
```

### Step 5 — Report

```
✓ UI-SPEC.md produced at .planning/phases/{NN}-{slug}/{NN}-UI-SPEC.md

Detected stack:
  Routing:   react-router-v6     [EXTRACTED]
  Styling:   tailwind + shadcn   [EXTRACTED]
  State:     zustand + TQv5      [EXTRACTED from LOCK-08]
  Forms:     react-hook-form+zod [EXTRACTED]
  Tests:     vitest + RTL + MSW  [EXTRACTED from LOCK-11]

Components inventoried: {N} (M new, K reused)
Routes added: {N}
State contracts: loading/empty/error/success defined for every async view
A11y contract: keyboard map + ARIA roles + contrast targets locked
Perf budgets: TTI < {Xms}, LCP < {Yms}, bundle delta < {Z}kb

Open questions remaining: {N} (see UI-SPEC.md § Open Questions)

Next: /release:plan {NN} --react
      (or /release:plan {NN} --fullstack to plan backend + frontend together)
```

---

## Decisions encoded as UI-DEC-XX

Inside `UI-SPEC.md`, the researcher locks frontend-design decisions as `UI-DEC-01`..`UI-DEC-NN`.
These are read by `react-feature-planner` during `/release:plan --react` and become the design
contract every TDD task must honor.

| ID prefix | Bucket |
|---|---|
| `UI-DEC-01..09` | Component inventory + composition |
| `UI-DEC-10..19` | Routing + navigation |
| `UI-DEC-20..29` | State contracts (loading/empty/error/success) |
| `UI-DEC-30..39` | A11y contract (keyboard, ARIA, contrast) |
| `UI-DEC-40..49` | Performance budgets |
| `UI-DEC-50..59` | Optimistic UI / mutation strategy |

UI-DEC-XX are immutable after UI-SPEC.md is written. Changes require re-running
`/release:ui-phase {NN} --revise`.

---

## Example

```
/release:ui-phase 03

→ Reading ROADMAP Phase 03: "Invoice list page with status filter and CSV export trigger"
→ Detection: keywords "list page", "filter" → frontend signals
→ CONTEXT.md frontmatter: stack: fullstack → proceed (frontend-only output)

→ Detected stack:
  • Routing: react-router-v6     [EXTRACTED — package.json]
  • Styling: tailwind + shadcn   [EXTRACTED — tailwind.config.ts + components.json]
  • State:   zustand + TQv5      [EXTRACTED — LOCK-08]
  • Forms:   react-hook-form+zod [EXTRACTED — package.json]
  • Tests:   vitest + RTL + MSW  [EXTRACTED — LOCK-11]

→ Spawning release-ui-researcher...
  Reading SPEC.md, CONTEXT.md (D-11..D-15 already locked frontend decisions)
  Probing src/features/, src/components/ui/, src/routes/

→ Researcher: 3 open questions remaining
  Q1: Empty state copy when zero invoices match filter?  → user: "Show CTA to clear filters"
  Q2: Optimistic UI on bulk-archive?                     → user: "Yes, rollback toast on 4xx"
  Q3: Perf budget LCP target on /invoices?               → user: "1.5s on 3G Fast"

→ Writing .planning/phases/03-invoice-list/03-UI-SPEC.md
  • 7 components inventoried (4 reuse, 3 new)
  • 1 new route: /invoices (under <ProtectedRoute>)
  • Loading: shadcn Skeleton; Empty: custom EmptyState; Error: ErrorBoundary toast
  • A11y: full keyboard nav (arrow + enter on rows), aria-rowcount, contrast AA
  • Perf: LCP ≤ 1.5s, bundle delta ≤ 30kb, TanStack staleTime 60s
  • Optimistic: bulk-archive with onMutate rollback

→ Next: /release:plan 03 --react
```
