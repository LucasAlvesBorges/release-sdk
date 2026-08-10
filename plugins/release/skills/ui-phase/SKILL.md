---
name: ui-phase
description: >
  Frontend design contract generator. Produces UI-SPEC.md BEFORE React TDD coding starts —
  component inventory, routes, state contracts (loading/empty/error/success), a11y contract,
  performance budgets, Zustand/TanStack Query patterns, optimistic UI plan.
  Detects existing design system (tailwind, shadcn, MUI) and locks tokens.
  Use when: phase is frontend or fullstack AND no UI-SPEC.md exists yet. Refuses backend-only phases.
---

## Codex runtime contract (generated; overrides incompatible source directives)

This skill is the Codex edition of release-sdk. The source workflow below is
kept for behavioral parity, but this contract has precedence whenever the
source mentions Claude Code primitives.

### Isolation

- Never create, edit, delete, or inspect runtime state under `~/.claude`,
  `.claude/`, `.claude-plugin/`, `.claude-plugin-cache/`, or `CLAUDE.md`.
- Release planning artifacts remain under `.release-planning/`. Durable Codex
  project guidance belongs in `AGENTS.md` only when the workflow explicitly
  needs to add it.
- Resolve `RELEASE_PLUGIN_ROOT` as the directory two levels above this
  `SKILL.md`. Resolve `RELEASE_PLUGIN_DATA` from `PLUGIN_DATA` when supplied;
  otherwise use `${CODEX_HOME:-$HOME/.codex}/release-sdk`.

### Step 0 — AGENTS.md gate

Before any Write/Edit/apply_patch, the target project MUST have a root
`AGENTS.md`. `release-agents-md-guard.js` enforces this at the hook level and
will block the write — do not try to route around it. If it blocks:
`.codex/config.toml`'s `[agents_md] mode` is `strict` (default: stop, tell the
user `AGENTS_MD_REQUIRED`) or `bootstrap` (spawn `release-agents-md-builder`
read-only, let it draft and save `AGENTS.md`, then stop and tell the user to
re-run the original task). Never fabricate the file yourself outside that
role, and never inline the full `AGENTS.md` content into a subagent prompt —
let Codex discover it normally from `cwd`.

### Step 1 — score complexity, then decide whether to spawn anything

Self-score the task C0–C4 using `complexity-rubric.md` before touching
anything else, apply the risk floors, then use `routing-policy.md`'s fleet
table for the level. Default is **no subagents** (`spawn = false`). Spawn one
only when ALL of:

```text
bounded_subtask
AND explicit_success_criteria
AND (independent OR noisy_output OR specialist_required OR broad_read_avoided)
AND estimated_context_avoided > spawn_overhead
```

Never spawn for C0. Never spawn just to "use multiagent." Never spawn a
subtask that immediately depends on another subtask's result and can't run in
parallel. Group reads over the same files instead of one agent per file.

**Read vs write:** read-only agents may run in parallel freely. Writers never
share a file set — one writer per path set, sequential when there's a
dependency, parallel only with disjoint scopes or isolated worktrees (declare
`allowed_paths`/`forbidden_paths` up front either way).

### Invoking a subagent

```text
Role: {role}
Single objective: {subtask_objective}

Allowed scope:
{allowed_paths}

Do not access:
{forbidden_paths}

Minimal context:
{task_specific_context}

Completion criteria:
{success_criteria}

Rules:
- Follow the AGENTS.md chain applicable to cwd.
- Do not expand scope on your own — return needs_scope_expansion instead.
- Do not restate the prompt back.
- Do not return full logs.
- Stop as soon as the criteria are met.
- Return only JSON matching SubagentResultV1.
```

Pass only this delta — never the full parent transcript, never the full
`AGENTS.md`, never whole files already in the workspace, never full logs.

### Handoff

Only when the task continues in another thread/session — see
`handoff-template.md` (60 lines / ~500 tokens max). Not a substitute for the
normal end-of-task summary.

### Tools

- Treat `Read`, `Write`, `Edit`, `Bash`, `Grep`, and `Glob` in the source as
  conceptual operations. Use the Codex tools currently available: targeted
  file reads, `apply_patch` for edits, `exec_command` for commands, and `rg`
  or `rg --files` for search.
- A source reference to `AskUserQuestion` means: use the structured user-input
  tool when it is available to the parent agent. A subagent must instead
  return `USER_INPUT_REQUIRED` with the exact question and 2-3 choices so the
  parent can ask it. If no structured input tool is available, ask one concise
  question in the parent task.
- A source reference to a `Skill` tool means to run the installed
  `release:<skill-name>` skill. If there is no callable skill tool, delegate to
  a `default` subagent with a task that explicitly names that installed skill,
  pass the original arguments unchanged, wait for it, and surface its result.

### Subagents

- Source agent names `release:<name>` are mapped in this generated edition to
  Codex custom agents named `release-<name>`.
- Spawn agents only through Codex collaboration tools. Do not emulate a
  subagent with a shell command and do not use a nonexistent `Task` or `Agent`
  tool.
- Prefer the named `release-<name>` agent when it is available. These agents
  are installed by the `release:setup-codex` skill and become available in a
  new task.
- If the exact named agent is not available, prefer this plugin's own generic
  roster before Codex's bare defaults: `release-explorer-fast` /
  `release-explorer-deep` for read-only research, `release-worker` /
  `release-worker-lite` / `release-worker-complex` for implementation,
  `release-reviewer` / `release-security-reviewer` for judgment-heavy review,
  `release-planner` for orchestration. Only fall back to Codex's bare
  `explorer` / `worker` / `default` if none of those are installed either —
  and in that case give the fallback agent the absolute path to
  `agents/release-<name>.toml` under `RELEASE_PLUGIN_ROOT` and require it to
  read and follow the `developer_instructions` before working.
- For write tasks, assign explicit file ownership and tell every worker that
  other agents may be editing the repository; it must preserve and integrate
  others' changes. Parallelize only independent scopes and respect the current
  session's concurrency limit.
- Wait for required agents, collect their final results, and keep completion
  judgment in the parent/orchestrator. A worker never declares the overall
  workflow complete.

### Models and reasoning

- Ignore source instructions that pin or derive Claude model tiers such as
  Fable, Opus, Sonnet, or Haiku, and ignore `CLAUDE_EFFORT`. Those do not
  apply in Codex.
- Every `release-<name>` custom agent already carries its own
  `model`/`reasoning_effort` per `routing-policy.md` — spawn it as-is. Only
  request a higher reasoning effort than the agent's default when the C0–C4
  fleet table for this task's level calls for it (`complexity-rubric.md`);
  never request a lower one.
- Preserve maker-versus-checker independence by using distinct agent turns —
  a checker runs as its own spawn, never as a self-review by the maker.

### Invocation vocabulary

- `/release:<name>` in the source is a workflow label retained for
  compatibility. In Codex Desktop the user selects the `release` plugin or its
  `release:<name>` skill from the composer.
- `claude` CLI launch examples map to `codex` in this generated edition.

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation.

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

1. Read `.release-planning/ROADMAP.md` → extract phase goal and tags.
2. If `.release-planning/phases/{NN}-{slug}/{NN}-CONTEXT.md` exists → read `stack:` frontmatter.
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
| `.release-planning/RELEASE-LOCKS.md` *(if present)* | LOCK-07..LOCK-12 (frontend stack, state, auth, types, tests, contract) |
| `.release-planning/PROJECT.md` *(fallback)* | LOCK-07..LOCK-12 if no RELEASE-LOCKS.md |
| `.release-planning/ROADMAP.md` | phase goal, tags |
| `.release-planning/phases/{NN}-{slug}/{NN}-SPEC.md` *(if present)* | WHAT the phase delivers |
| `.release-planning/phases/{NN}-{slug}/{NN}-CONTEXT.md` *(if present)* | locked D-XX decisions (especially D-11..D-20 frontend bucket) |
| `.release-planning/phases/{NN}-{slug}/{NN}-RESEARCH-FRONTEND.md` *(if present)* | researcher output |

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

### Step 3 — Route to `release-react-ui-researcher` agent

Spawn the agent with these inputs:

```yaml
phase_number: "{NN}"
phase_dir: ".release-planning/phases/{NN}-{slug}"
required_reading:
  - .release-planning/RELEASE-LOCKS.md OR .release-planning/PROJECT.md
  - .release-planning/phases/{NN}-{slug}/{NN}-SPEC.md (if exists)
  - .release-planning/phases/{NN}-{slug}/{NN}-CONTEXT.md (if exists)
  - .release-planning/phases/{NN}-{slug}/{NN}-RESEARCH-FRONTEND.md (if exists)
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

The agent (`release-react-ui-researcher`) will:
1. Read all required reading.
2. Probe component inventory, routes, states currently in repo.
3. Use `AskUserQuestion` for ONLY unanswered dimensions (skip anything locked in CONTEXT.md D-11..D-20 or LOCK-07..LOCK-12).
4. Produce `{NN}-UI-SPEC.md` from `templates/UI-SPEC.md`.

### Step 4 — Output

```
.release-planning/phases/{NN}-{slug}/
  {NN}-UI-SPEC.md           # design contract (component inventory, states, a11y, perf, optimistic)
```

### Step 5 — Report

```
✓ UI-SPEC.md produced at .release-planning/phases/{NN}-{slug}/{NN}-UI-SPEC.md

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
These are read by `release-feature-planner` during `/release:plan --react` and become the design
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

→ Spawning release-react-ui-researcher...
  Reading SPEC.md, CONTEXT.md (D-11..D-15 already locked frontend decisions)
  Probing src/features/, src/components/ui/, src/routes/

→ Researcher: 3 open questions remaining
  Q1: Empty state copy when zero invoices match filter?  → user: "Show CTA to clear filters"
  Q2: Optimistic UI on bulk-archive?                     → user: "Yes, rollback toast on 4xx"
  Q3: Perf budget LCP target on /invoices?               → user: "1.5s on 3G Fast"

→ Writing .release-planning/phases/03-invoice-list/03-UI-SPEC.md
  • 7 components inventoried (4 reuse, 3 new)
  • 1 new route: /invoices (under <ProtectedRoute>)
  • Loading: shadcn Skeleton; Empty: custom EmptyState; Error: ErrorBoundary toast
  • A11y: full keyboard nav (arrow + enter on rows), aria-rowcount, contrast AA
  • Perf: LCP ≤ 1.5s, bundle delta ≤ 30kb, TanStack staleTime 60s
  • Optimistic: bulk-archive with onMutate rollback

→ Next: /release:plan 03 --react
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
