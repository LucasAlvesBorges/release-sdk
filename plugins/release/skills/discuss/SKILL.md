---
name: discuss
description: >
  Context-aware phase discussion. Detects phase type from ROADMAP.md, routes to backend-focused or
  frontend-focused questions, or runs both for fullstack phases. Locks D-XX decisions in CONTEXT.md.
  Use when: phase added to ROADMAP, ready to gather decisions before planning.
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
- If a named agent is not available, use `explorer` for read-only codebase
  research, `worker` for implementation or file-producing work, and `default`
  for orchestration or judgment. Give the fallback agent the absolute path to
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
  Fable, Opus, Sonnet, or Haiku. Do not pass an explicit model or reasoning
  effort unless the user requested one. Codex custom agents inherit the
  parent/session settings by default.
- Preserve maker-versus-checker independence by using distinct agent turns,
  not by assuming a particular vendor model hierarchy.

### Invocation vocabulary

- `/release:<name>` in the source is a workflow label retained for
  compatibility. In Codex Desktop the user selects the `release` plugin or its
  `release:<name>` skill from the composer.
- `claude` CLI launch examples map to `codex` in this generated edition.

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

## Pre-discussion assumptions probe (release-assumptions-analyzer)

**Immediately after stack detection, before the D-XX questioning loop**, spawn `release-assumptions-analyzer`:

```
Agent({
  subagent_type: "release-assumptions-analyzer",
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

Spawns `release-django-discuss-orchestrator` for 10 dimensions:
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

- v0.7.0 wires `release-assumptions-analyzer` BEFORE D-XX questioning. It produces `{NN}-ASSUMPTIONS.md` with DP-XX prompts; the orchestrator surfaces those DP-XX items first as "Hidden assumption — confirm or override:" questions, then proceeds to standard dimension questions. Skipped (file already read) if ASSUMPTIONS.md already exists.
