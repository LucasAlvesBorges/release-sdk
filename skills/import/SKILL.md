---
name: import
description: >
  One-shot mass importer for projects that already use upstream GSD. Reads GSD `.planning/`
  (PROJECT.md, ROADMAP.md, STATE.md, ARCHITECTURE.md, CONVENTIONS.md, config.json, and every
  `.planning/phases/*/` artifact) and writes release-sdk artifacts to a parallel `.release-planning/`
  tree. Extracts LOCK-01..LOCK-12 into `.release-planning/RELEASE-LOCKS.md`, and ports each phase's
  GSD SPEC/CONTEXT/PLAN/VERIFICATION into release-sdk-native `{NN}-*.md` files under
  `.release-planning/phases/{NN}-{slug}/` (with stack-aware UI-SPEC / AI-SPEC / SECURITY stubs as
  needed). Files under `.planning/` are NEVER modified — the two trees coexist.
  Use when: an existing GSD project wants to switch to release-sdk in one pass — replaces the
  per-skill `--gsd-context` flag that was scattered across release-init/spec/plan/review/ui/ai.
---

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation.

---

# /release:import — Mass GSD → release-sdk Importer

Single-pass importer. After it runs once, every other release-sdk skill (`/release:status`,
`/release:plan`, `/release:execute`, `/release:review`, `/release:ui-phase`, `/release:ai-phase`)
can assume native format — no runtime translation needed.

## Usage

```
/release:import                          # full import — project locks + every phase
/release:import --dry-run                # report what would be ported, no writes
/release:import --phases=01,03,07        # only import these phase NN prefixes
/release:import --no-stubs               # skip UI-SPEC/AI-SPEC stub seeding
/release:import --force                  # re-import (overwrites RELEASE-LOCKS.md after confirm)
```

Flags compose: `/release:import --dry-run --phases=01,02` previews the import of just phases 01 + 02.

## When to use

- The repo already has `.planning/PROJECT.md` and `.planning/phases/*/` written by upstream GSD.
- You want every release-sdk skill to find native `{NN}-SPEC.md`, `{NN}-PLAN.md`, etc., without
  re-running each `--gsd-context` flow.
- You want a single auditable extraction report (LOCKs + per-phase port).

Do NOT use if:
- The project has no `.planning/` directory — run `/release:init` instead.
- You already imported once and just want to re-check gaps — use `/release:status` and then
  `/release:spec` or `/release:ui-phase` per phase to fill the gaps.

## Pre-checks (hard gates)

1. **GSD presence:** `.planning/` and at least one of `.planning/PROJECT.md` or
   `.planning/phases/` must exist. Else abort with:
   > "No GSD planning artifacts detected at `.planning/`. Run `/release:init` for a fresh project."
2. **Already imported:** if `.release-planning/RELEASE-LOCKS.md` exists and `--force` is NOT
   set, abort with:
   > "Project already imported (.release-planning/RELEASE-LOCKS.md present). Re-run with
   > `--force` to overwrite or use `/release:status` to inspect current state."
3. **Force confirmation:** if `--force` is set, ask via `AskUserQuestion`:
   > "Overwriting `.release-planning/RELEASE-LOCKS.md` and any existing `{NN}-*.md` files under
   > `.release-planning/phases/`? This is irreversible. GSD `.planning/` is untouched either
   > way." — options: `Yes, overwrite` / `Abort`. Only proceed on explicit Yes.
4. **Phases filter:** if `--phases=NN[,NN]` is set, verify each NN matches an existing phase
   directory. Unknown NN → abort and list available phases.

## Detection — project-level

Read ALL of these that exist (skip gracefully if missing) — every read MUST capture file:line for
the extraction report:

| File | Extracts |
|---|---|
| `.planning/PROJECT.md` | project name, domain, multi-tenancy, auth model, team, requirements |
| `.planning/ARCHITECTURE.md` (root or `.planning/codebase/ARCHITECTURE.md`) | patterns, API contract, tenancy strategy |
| `.planning/CONVENTIONS.md` (root or `.planning/codebase/CONVENTIONS.md`) | ORM rules, serializer rules, forbidden patterns |
| `.planning/codebase/STACK.md` | full stack versions (backend + frontend + testing) |
| `.planning/codebase/TESTING.md` | test framework, test strategy |
| `.planning/STATE.md` | active phase cursor, history |
| `.planning/ROADMAP.md` (first 80 lines) | milestone/phase overview |
| `.planning/config.json` | GSD mode, granularity, branching strategy |

## LOCK extraction (mirrors /release:init --gsd-context)

For each LOCK, extract from the files above. Mark as `[EXTRACTED]`, `[INFERRED]`, or `[MISSING]`.

| LOCK | Source file | What to look for |
|---|---|---|
| LOCK-01 | STACK.md / PROJECT.md | Django version, DRF version, Python version |
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

Status vocabulary (same as `/release:init`):

- `[EXTRACTED]` — verbatim value found in GSD file at a citable file:line
- `[INFERRED]` — implied by stack defaults / adjacent statement; not stated verbatim
- `[MISSING]` — no signal at all; user must clarify later via `/release:spec` or `/release:plan`

## Detection — phase-level

Glob both common layouts:

```bash
.planning/phases/*/
.planning/milestones/v*-phases/*/   # upstream Redux layout fallback
```

For each phase directory `{NN}-{slug}/`, detect stack by grepping the GSD artifacts inside it:

| Signal (in any of SPEC.md/PLAN.md/CONTEXT.md/VERIFICATION.md) | Classification |
|---|---|
| `.py` paths in PLAN tasks, mentions of `Django`/`DRF`/`ORM`/`migration`/`manage.py`/`viewset`/`serializer`/`models.py` | `django` |
| `.tsx`/`.ts` paths in PLAN tasks, mentions of `React`/`component`/`route`/`Zustand`/`TanStack` | `react` |
| Both kinds of signals present | `fullstack` |
| Neither | `unknown` — ask user via `AskUserQuestion` once at the end of detection |

**Stack detection MUST be evidence-based.** The orchestrator records the exact grep hit
(`file:line`) that proved the classification — this appears in the extraction report.

Additional stack-modifier probes (used to decide whether to seed UI-SPEC / AI-SPEC stubs):

| Probe | Signal | Output |
|---|---|---|
| UI surface | React/fullstack stack AND any of `route`/`page`/`modal`/`component`/`form` in SPEC or PLAN | seed `{NN}-UI-SPEC.md` stub |
| AI/LLM surface | grep for `openai`/`anthropic`/`llm`/`prompt`/`embedding`/`bedrock`/`vertex`/`langchain` in any phase file | seed `{NN}-AI-SPEC.md` stub |
| Threat model present | PLAN.md contains `threat_model:` block or `SECURITY.md` exists | seed `{NN}-SECURITY.md` placeholder |

## Port mapping (per phase)

For each phase dir, produce release-sdk equivalents alongside the GSD originals. The GSD files
are NEVER renamed, deleted, or modified — only `{NN}-*.md` siblings are written.

| GSD source | release-sdk target | Shape source | Notes |
|---|---|---|---|
| `SPEC.md` | `{NN}-SPEC.md` | `templates/SPEC.md` | rewritten in stack-aware shape: Goal, Stack Detection, Scope (in/out), Acceptance, Open Questions HIGH/MED/LOW. Preserve content verbatim where it maps; mark un-mapped fields `[NEEDS REVIEW]` |
| `CONTEXT.md` | `{NN}-CONTEXT.md` | `templates/CONTEXT.md` | preserve every D-XX. If new D-XX are needed to lock stack defaults (e.g., LOCK-04 forces `.delay_on_commit()`), append at the end with `source: import-default` |
| `PLAN.md` | `{NN}-PLAN.md` | `templates/PLAN.md` | preserve tasks + frontmatter. Inject RC1-RC7 (planner readiness), Q1-Q7 (author checklist), and the 9-category security threat-model block if missing |
| `VERIFICATION.md` | `{NN}-VERIFICATION.md` + `{NN}-UAT.md` | `templates/UAT.md` | split static/machine-verifiable items into VERIFICATION.md, user-observable / UAT items into UAT.md |
| `RESEARCH.md` | (none) | n/a | leave in place — release-sdk reads it as-is when needed |
| `REVIEW.md` | (none) | n/a | leave in place; `/release:review` writes a new `{NN}-REVIEW.md` on next run |

Stubs (only seeded when `--no-stubs` is NOT set):

| Stub | When seeded | Content |
|---|---|---|
| `{NN}-UI-SPEC.md` | UI surface detected | from `templates/UI-SPEC.md` with `[NEEDS REVIEW]` markers on every UI-DEC slot. Frontmatter `ready_for_plan: false`. User must run `/release:ui-phase {NN}` to fill |
| `{NN}-AI-SPEC.md` | AI/LLM surface detected | from `templates/AI-SPEC.md` with `[NEEDS REVIEW]` markers on provider/model/hosting. `ready_for_plan: false`. User runs `/release:ai-phase {NN}` to fill |
| `{NN}-SECURITY.md` | threat model present in PLAN | placeholder header only — retro auditors fill via `/release:secure-phase {NN}` after ship |

## Workflow

1. Skill resolves flags (`--dry-run`, `--force`, `--phases`, `--no-stubs`).
2. Skill runs pre-checks (GSD presence, idempotency, force confirmation, phase filter validation).
3. Skill spawns `release:release-import-orchestrator` agent with:
   - `dry_run: bool`
   - `force: bool`
   - `phases: string[]` (empty = all)
   - `seed_stubs: bool` (default true)
4. Orchestrator reads project-level artifacts, extracts LOCK-01..LOCK-12 with citations.
5. Orchestrator iterates phases (in NN order), detects stack per phase, ports files.
6. Orchestrator writes `.release-planning/RELEASE-LOCKS.md` and every `{NN}-*.md` file under
   `.release-planning/phases/{NN}-{slug}/`. `.planning/` is never written to.
7. Orchestrator prints final extraction report (project LOCKs table + per-phase port table +
   gap-to-fill table + next steps).

## Output

### Files written (project-level)

- `.release-planning/RELEASE-LOCKS.md` — canonical LOCK-01..LOCK-12 (NEW)
- `.release-planning/STATE.md` — release-sdk-owned cursor + history (NEW; GSD's
  `.planning/STATE.md` stays untouched)
- `CLAUDE.md` (repo root) — delimited `<!-- release-sdk:start --> ... <!-- release-sdk:end -->`
  block injected. Idempotent: created if missing, block replaced if present, appended
  otherwise. Every other byte preserved. See `init` SKILL for the block contents.

### Layout after import (two coexisting trees)

```
.planning/phases/{NN}-{slug}/             # GSD source — ALL files UNTOUCHED
  SPEC.md                                 # read by import
  CONTEXT.md                              # read by import
  PLAN.md                                 # read by import
  VERIFICATION.md                         # read by import
  RESEARCH.md                             # read by import
  REVIEW.md                               # read by import

.release-planning/phases/{NN}-{slug}/     # release-sdk dest — written by import
  {NN}-SPEC.md             # NEW — release-sdk-native
  {NN}-CONTEXT.md          # NEW — release-sdk-native (preserves D-XX)
  {NN}-PLAN.md             # NEW — release-sdk-native (Q1-Q7 + 9-cat injected)
  {NN}-VERIFICATION.md     # NEW — static gate
  {NN}-UAT.md              # NEW — user gate
  {NN}-UI-SPEC.md          # NEW only if UI surface, stub with [NEEDS REVIEW]
  {NN}-AI-SPEC.md          # NEW only if AI surface, stub with [NEEDS REVIEW]
  {NN}-SECURITY.md         # NEW placeholder only if PLAN had threat_model
```

Per-phase files only written when the source GSD file existed OR a stub condition fires.

### Extraction report (printed to user)

```
release-sdk Import — Extraction Report
═══════════════════════════════════════════════════════════
Project: {name from PROJECT.md:line}
Source:  GSD .planning/ ({phase_count} phases discovered)
Mode:    {full | dry-run | phases=01,03,07}

── Project LOCKs ──────────────────────────────────────────
LOCK-01  [EXTRACTED]  Django 5.2 + DRF 3.16 + Python 3.12
                      source: STACK.md:14
LOCK-02  [EXTRACTED]  Multi-tenant: empresa_id via TenantModel + django-rls
                      source: ARCHITECTURE.md:42
LOCK-03  [EXTRACTED]  Auth: JWT httpOnly cookie + X-CSRFToken
                      source: PROJECT.md:88
LOCK-04  [INFERRED]   Celery present; .delay_on_commit() rule not explicit
                      source: STACK.md:31 (no commit-rule in CONVENTIONS.md)
LOCK-05  [EXTRACTED]  N+1 = BLOCKER; select_related/prefetch required
                      source: CONVENTIONS.md:12
LOCK-06  [EXTRACTED]  fields='__all__' forbidden
                      source: CONVENTIONS.md:27
LOCK-07  [EXTRACTED]  React 19 + Vite + TypeScript 5.7 + shadcn/ui
                      source: STACK.md:48
LOCK-08  [EXTRACTED]  Zustand 5 (client) + TanStack Query 5 (server)
                      source: STACK.md:55
LOCK-09  [EXTRACTED]  httpOnly cookie only; localStorage tokens = BLOCKER
                      source: PROJECT.md:101
LOCK-10  [EXTRACTED]  TypeScript strict; no `any`; Zod 4 for API responses
                      source: CONVENTIONS.md:44
LOCK-11  [EXTRACTED]  pytest + Vitest + RTL + MSW + factory-boy
                      source: TESTING.md:9
LOCK-12  [MISSING]    API contract (snake_case↔camelCase) — fill via /release:spec

── Phases imported ────────────────────────────────────────
NN  Slug                         Stack       Files ported               Stubs       Gaps
01  veiculo-bulk-import          django      SPEC,CONTEXT,PLAN,VERIF    SECURITY    none
02  invoice-list-page            react       SPEC,CONTEXT,PLAN,VERIF    UI-SPEC*    UI-SPEC needs review
03  invoice-pdf-export           fullstack   SPEC,CONTEXT,PLAN,VERIF    UI-SPEC*    UI-SPEC needs review
04  ai-summarize-orders          fullstack   SPEC,CONTEXT,PLAN          UI,AI*      AI-SPEC needs review

(* = stub seeded; values are placeholders pending /release:ui-phase or /release:ai-phase)

── Summary ────────────────────────────────────────────────
Phases discovered:     4
Phases imported:       4   (skipped: 0)
Files ported:          15
Stubs seeded:          4   (UI: 3, AI: 1, SECURITY: 1)
LOCKs locked:          11 EXTRACTED + 1 INFERRED + 1 MISSING (LOCK-12)

── Next steps ─────────────────────────────────────────────
1. /release:status                         # see active phase + cursor
2. /release:spec   <NN>                    # fill any phase with [NEEDS REVIEW]
3. /release:ui-phase <NN>                  # fill UI-SPEC stubs (phases 02, 03, 04)
4. /release:ai-phase 04                    # fill AI-SPEC stub
5. /release:plan   <NN>                    # re-plan with native artifacts
═══════════════════════════════════════════════════════════
```

## Constraints

- **GSD originals untouched.** Never rename, overwrite, or delete any file under `.planning/`.
  Only WRITE `.release-planning/RELEASE-LOCKS.md` and `{NN}-*.md` files under
  `.release-planning/phases/{NN}-{slug}/`.
- **Every claim is cited.** LOCK-XX status, stack detection, and any port decision must include
  `file:line` evidence in the extraction report.
- **Evidence-based stack detection.** If a phase shows no clear signal, mark `unknown` and ask
  the user via a single `AskUserQuestion` batch — do not guess.
- **Idempotent.** Running `/release:import` twice without `--force` reports "already imported"
  and exits cleanly. With `--force`, requires explicit user confirmation.
- **Non-interactive by default.** `AskUserQuestion` is only used for (a) `--force` confirmation
  and (b) tie-breaking unknown stack detection. Every other step is non-interactive.
- **No commits in this skill.** The orchestrator stages and commits at the end with
  `chore(import): port GSD planning tree to release-sdk format`.

## Example

```
/release:import

→ Pre-check: .planning/ found (GSD source); .release-planning/RELEASE-LOCKS.md not present → proceed
→ Reading project-level GSD artifacts...
  PROJECT.md (137 lines), STACK.md (61), CONVENTIONS.md (52), ROADMAP.md (94)
→ Extracting LOCK-01..LOCK-12 with citations... done (11 EXTRACTED, 1 INFERRED, 0 MISSING)
→ Globbing phases... found 4 phases under .planning/phases/
→ Phase 01 veiculo-bulk-import     → stack: django     (signal: PLAN.md:34 ".py")
→ Phase 02 invoice-list-page       → stack: react      (signal: PLAN.md:21 ".tsx")
→ Phase 03 invoice-pdf-export      → stack: fullstack  (signals: PLAN.md:14, PLAN.md:42)
→ Phase 04 ai-summarize-orders     → stack: fullstack  (+ AI surface @ PLAN.md:18)
→ Writing .release-planning/RELEASE-LOCKS.md...
→ Writing 15 phase files + 4 stubs under .release-planning/phases/...
→ Committing: chore(import): port GSD planning tree to release-sdk format
→ Done. Report ↑

Next: /release:status
```

---

_Driven by `release:release-import-orchestrator` (release-sdk). One-shot. Replaces the per-skill
`--gsd-context` flag scattered across release-init/spec/plan/review/ui-phase/ai-phase._
