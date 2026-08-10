---
name: verify-work
description: >
  Conversational UAT walkthrough for a completed phase. Reads UAT.md (or extracts from
  PLAN.md / SPEC.md), surfaces stack-aware verification steps (curl for Django, browser
  walk for React, end-to-end for fullstack), asks user PASS/FAIL/BLOCKED per item via
  AskUserQuestion, writes results back to UAT.md with timestamps and a Next Step verdict.
  Use when: phase is built and you want a human-in-the-loop acceptance pass before /release:ship.
  Distinct from /release:verify which is goal-backward STATIC analysis (no user prompts).
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

# /release:verify-work — Conversational UAT Walkthrough

Human-in-the-loop acceptance testing. For each UAT item, the conductor surfaces concrete
stack-aware verification steps, asks the user yes/no, and records the outcome.

## Relationship to /release:verify

| Skill | Mode | Source of truth | Output |
|---|---|---|---|
| `/release:verify` | Goal-backward, STATIC (no user) | `must_haves.truths` in PLAN.md + code grep | `{NN}-VERIFICATION.md` |
| `/release:verify-work` | Conversational, INTERACTIVE (asks user) | UAT.md / PLAN.md SPEC.md UAT criteria | `{NN}-UAT.md` (updated in place) |

Run `/release:verify` first to confirm code matches the plan, then `/release:verify-work` to
confirm the human can actually use what was built. Both gates should be PASS before `/release:ship`.

## Usage

```
/release:verify-work                  # auto-detect active phase from STATE.md or git branch
/release:verify-work 01               # explicit phase number
/release:verify-work 01 --backend     # only Django UAT items
/release:verify-work 01 --frontend    # only React UAT items
/release:verify-work 01 --resume      # continue a partially-completed UAT (skip PASSed items)
/release:verify-work 01 --reset       # start over, wipe prior statuses to PENDING
```

## Phase Detection

1. If `{NN}` argument provided → use it.
2. Else read `.release-planning/STATE.md` cursor.active_phase.
3. Else parse current git branch — look for `phase/{NN}-{slug}` or `{NN}-{slug}`.
4. Else abort: ask user to specify phase number.

Resolves to `.release-planning/phases/{NN}-{slug}/`.

## UAT Source Resolution

The conductor finds UAT items in this priority order:

1. `{phase_dir}/{NN}-UAT.md` — if exists, parse the UAT Items table directly.
2. `{phase_dir}/{NN}-PLAN.md` — extract `must_haves.truths` and `success_criteria` as UAT seeds.
3. `{phase_dir}/{NN}-SPEC.md` — extract acceptance criteria / user-observable behaviors.
4. `.release-planning/ROADMAP.md` phase entry `success_criteria`.

If no UAT.md exists yet, conductor creates it from the template at
`templates/UAT.md` (in this plugin) populated with derived items.

## Stack Classification

Each UAT item is tagged `backend`, `frontend`, or `fullstack`. Detection rule:

- Mentions endpoint / API / model / migration / serializer / Celery → `backend`
- Mentions component / page / button / form / browser / UI / a11y → `frontend`
- Mentions login flow / end-to-end / data round-trip / API + render → `fullstack`
- Else: ask the user during walkthrough.

`--backend` filters to backend+fullstack; `--frontend` filters to frontend+fullstack.

## Stack-Aware Verification Steps

The conductor (release-uat-conductor agent) surfaces these scripts per item:

### Backend items (Django / DRF)

For each backend UAT item, render concrete steps:

```bash
# Auth (cookie-based — LOCK-03 / LOCK-09)
curl -c cookies.txt -b cookies.txt -X POST http://localhost:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"username": "...", "password": "..."}'

# Hit endpoint under test
curl -b cookies.txt -H "X-CSRFToken: $(grep csrftoken cookies.txt | awk '{print $7}')" \
  http://localhost:8000/api/{resource}/

# Or via manage.py shell
python backend/manage.py shell -c "from apps.{app}.models import {Model}; print({Model}.objects.filter(empresa_id={X}).count())"

# DB sanity
python backend/manage.py dbshell -c "SELECT COUNT(*) FROM {table};"
```

Conductor adapts host/port from `.env` if present.

### Frontend items (React TSX)

For each frontend UAT item, render a browser interaction script:

```
1. Open http://localhost:5173/{route}
2. Login as {role} (use cookie set by backend)
3. Click "{button label}"
4. Observe: {expected visible outcome}
5. DevTools → Network: confirm {METHOD} {endpoint} → 200 (cookie sent, no Authorization header)
6. DevTools → Application → Local Storage: confirm NO auth/token keys (LOCK-09 check)
7. Keyboard walk: Tab through interactive elements, confirm visible focus ring, Enter triggers action
```

### Fullstack items

End-to-end flow combining the above:

```
1. (Backend) Seed: `python backend/manage.py loaddata {fixture}`
2. (Frontend) Open browser, login
3. Trigger action in UI
4. (Backend) Verify DB row created with correct tenant scope: `SELECT empresa_id FROM ... WHERE id = ...`
5. (Frontend) Reload page; observe persisted state
6. Confirm Network panel shows snake_case → camelCase via Axios interceptor (LOCK-12)
```

## Conductor Loop (high level)

```
agent: release-uat-conductor
  for each UAT item:
    1. Render stack-aware steps inline
    2. AskUserQuestion: "Item U-XX result?"
       options: [PASS, FAIL, BLOCKED, SKIP]
       free-text follow-up: "Notes?"
    3. Update UAT.md row in place (Status, Notes, Verified At = now)
    4. Commit nothing — verify-work does not commit
  After loop:
    Compute summary: pass / fail / blocked / skipped counts
    Decide Next Step:
      - All PASS → "Ready to ship: /release:ship {NN}"
      - Any FAIL → "Fix gaps: /release:plan {NN} --gaps then /release:execute {NN} --gaps"
      - Any BLOCKED → "Resolve blockers (env, fixtures, deps); re-run /release:verify-work {NN} --resume"
    Write Summary + Next Step sections of UAT.md.
```

## Status Values

| Status | Meaning |
|---|---|
| PENDING | Not yet walked |
| PASS | User confirmed item works as specified |
| FAIL | User saw broken/missing behavior; details in Notes |
| BLOCKED | Cannot verify right now (env down, missing fixture, dep on another item) |
| SKIP | User chose to skip (out of scope this round) |

`--resume` skips PASS items; re-asks PENDING / FAIL / BLOCKED / SKIP.
`--reset` rewrites all items back to PENDING (asks for confirmation first).

## Output

Updates `{phase_dir}/{NN}-UAT.md` in place (creates if missing using `templates/UAT.md`).

```markdown
---
phase: {NN}
generated_at: {iso}
stack: backend | frontend | fullstack
items_total: {N}
items_pass: {N}
items_fail: {N}
items_blocked: {N}
items_skip: {N}
items_pending: {N}
verdict: READY_TO_SHIP | GAPS_FOUND | BLOCKED
---

# Phase {NN} — UAT

## UAT Items

| ID | Item | Stack | Steps | Status | Notes | Verified At |
|----|------|-------|-------|--------|-------|-------------|
| U-01 | "User can bulk-import veiculos via CSV" | backend | curl POST /api/veiculos/import/ ... | PASS | 200 rows imported | 2026-05-25T14:30Z |
| U-02 | "Import UI shows progress + final count" | frontend | open /veiculos/import → upload → observe toast | FAIL | toast never fires; console shows TypeError | 2026-05-25T14:34Z |
| U-03 | "End-to-end: CSV → DB → list render" | fullstack | (combined) | BLOCKED | local Celery worker not running | 2026-05-25T14:38Z |

## Summary
- PASS: 1
- FAIL: 1
- BLOCKED: 1
- SKIP: 0
- PENDING: 0

## Next Step
GAPS_FOUND → /release:plan {NN} --gaps then /release:execute {NN} --gaps --frontend
```

## What this skill does NOT do

- Does NOT commit anything (UAT runs are user-driven and re-runnable; commit via `/release:ship`).
- Does NOT spawn `release-phase-verifier` or `release-phase-verifier` (those are `/release:verify`).
- Does NOT modify ROADMAP.md or STATE.md (only `/release:verify` advances cursor on PASS).
- Does NOT replace automated tests — UAT is the human gate, tests are the machine gate.

## Anti-patterns

- Skipping straight to /release:ship without `/release:verify-work` → demos break in prod.
- Marking FAIL items PASS to "unblock the ship" → defeats the purpose; use BLOCKED + Notes.
- Editing UAT.md by hand after a run → re-run with `--resume` instead so timestamps stay honest.


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
