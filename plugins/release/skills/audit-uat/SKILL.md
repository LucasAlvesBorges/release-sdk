---
name: audit-uat
description: >
  Cross-phase audit of all outstanding UAT and verification items. Scans every phase's UAT.md for
  PENDING/FAIL items, cross-references STATE.md, produces .release-planning/AUDIT-UAT.md with a
  hot-list of items to address before milestone ship.
  Use when: preparing to close a milestone or starting a UAT-focused work session.
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

# /release:audit-uat — Cross-Phase UAT Audit

Read-only sweep across every phase's `{NN}-UAT.md`. Collects PENDING / FAIL items,
cross-references `STATE.md` to confirm phase stage, ranks items by ship risk, and writes a
single `.release-planning/AUDIT-UAT.md` with a hot-list you can work through before closing
the milestone.

## When to use

- Closing a milestone — want one report showing every loose UAT thread.
- Starting a focused UAT session — need a queue of items, prioritized.
- Onboarding someone to acceptance testing — give them the hot-list, not 20 separate UAT.md files.
- Triggered from `/release:audit-milestone` (sibling skill) as a sub-check.

## When NOT to use

- Single-phase UAT walkthrough — use `/release:verify-work {NN}` (interactive, per-phase).
- Static goal-backward verify — use `/release:verify {NN}` (truths, not UAT).
- Quality debt sweep — use `/release:audit-fix` (auditor findings, not UAT).

## Usage

```
/release:audit-uat                        # scan every phase at stage executing+
/release:audit-uat --milestone v1.0       # only phases under that milestone
/release:audit-uat --include-pass         # include PASS rows in tables (default: hide)
/release:audit-uat --stack backend        # filter UAT items tagged backend
/release:audit-uat --stack frontend       # filter UAT items tagged frontend
/release:audit-uat --stack fullstack      # filter UAT items tagged fullstack
```

## Pre-checks (hard requirements)

1. `.release-planning/` exists — abort with guidance otherwise.
2. At least one `.release-planning/phases/{NN}-*/` directory exists — abort if none.
3. `.release-planning/STATE.md` exists — recommended but not required. If absent, stage
   info is left as `unknown` in the output.

This skill is read-only — no working-tree cleanliness check needed.

## Scope resolution

| Flag | Scope |
|---|---|
| (none) | Every phase whose STATE.md stage is `executing`, `verified`, `verified-uat-pending`, or `shipped`. |
| `--milestone v1.0` | Phases listed under that milestone in `ROADMAP.md`. |
| `--stack backend` | Filter UAT items tagged `backend` or `fullstack`. |
| `--stack frontend` | Filter UAT items tagged `frontend` or `fullstack`. |
| `--stack fullstack` | Only `fullstack`-tagged items. |

Phases at stage `spec`, `discuss`, `planning` are excluded by default (UAT items not yet
expected). Override by passing the phase number explicitly is not supported — keep this
skill cross-phase only; single-phase work goes through `/release:verify-work`.

## Execution

1. **Discover phases.** Glob `.release-planning/phases/*/`. For each, read frontmatter of
   `{NN}-SPEC.md` (or `{NN}-PLAN.md` if SPEC absent) to get phase slug + milestone.
2. **Filter by stage / milestone.** Read STATE.md, build `{phase → stage}` map. Apply
   scope filter from above.
3. **Find UAT files.** Glob `.release-planning/phases/*/{NN}-UAT.md` within scope. Phases
   in scope without a UAT.md → flag as `MISSING_UAT` (counted separately from items).
4. **Parse each UAT.md.** Each file is the format written by `/release:verify-work`:
   ```
   | ID | Item | Stack | Steps | Status | Notes | Verified At |
   ```
   Extract every row.
5. **Cross-reference STATE.md.** For each item, attach the phase's current stage. A FAIL
   item on a phase at stage `shipped` is a higher hot-list priority than the same item on
   a phase at stage `executing` (the ship gate already passed; this is regression risk).
6. **Compute counts.** Per phase and overall: PASS / FAIL / BLOCKED / PENDING / SKIP.
7. **Build hot-list.** Order items by:
   - FAIL on `shipped` phase (escaped to prod-ish) → highest
   - FAIL on `verified-uat-pending` (blocks ship) → high
   - BLOCKED on any stage (env / dep problem) → medium
   - PENDING on `verified-uat-pending` (just unstarted) → medium
   - PENDING on `executing` (too early — informational) → low
8. **Detect stale UAT.** Any UAT.md whose `generated_at` mtime is older than the latest
   commit on its phase branch → flag `stale: true`. The UAT walk was done against an
   earlier code state; results may be stale.
9. **Write report.** Single file:
   ```
   .release-planning/AUDIT-UAT.md
   ```
   Overwritten on each run (not appended — this is a snapshot, not a log). The previous
   version is recoverable via git history.

## Output format

```markdown
---
audited_at: 2026-05-25T15:30:00Z
milestone: v1.0
phase_count: 4
phases_in_scope: [01, 02, 03, 04]
phases_missing_uat: [02]
total_items: 27
pass: 18
fail: 3
blocked: 2
pending: 4
skip: 0
verdict: GAPS_BEFORE_SHIP
---

# UAT Audit — Milestone v1.0

## Summary
- Phases in scope: 4 (01, 02, 03, 04)
- Total UAT items: 27 (PASS: 18, FAIL: 3, BLOCKED: 2, PENDING: 4, SKIP: 0)
- Phases without UAT.md: 1 (02 — flagged as MISSING_UAT)
- Stale UAT runs: 1 (03 — last walk was 4 commits behind HEAD)

## Hot List (act on these before shipping milestone)

| Rank | Phase | Item | Status | Stage | Why hot | Action |
|---|---|---|---|---|---|---|
| 1 | 04 | U-02 toast never fires on import | FAIL | shipped | Regression escaped ship gate | `/release:debug` then `/release:plan 04 --gaps` |
| 2 | 01 | U-05 retrieve missing tenant scope | FAIL | verified-uat-pending | Blocks milestone ship | `/release:plan 01 --gaps` |
| 3 | 03 | U-03 CSV → DB → list e2e | BLOCKED | verified-uat-pending | Celery worker down locally | Resolve env, `/release:verify-work 03 --resume` |
| 4 | 02 | (MISSING_UAT) | — | verified | UAT never run | `/release:verify-work 02` |
| 5 | 03 | (stale UAT) | — | verified-uat-pending | Walk predates 4 commits | `/release:verify-work 03 --reset` |

## Per-Phase Breakdown

### Phase 01-invoices-crud (stage: verified-uat-pending)
| ID | Item | Stack | Status | Verified At |
|---|---|---|---|---|
| U-01 | Bulk import via CSV | backend | PASS | 2026-05-24T11:00Z |
| U-02 | Import UI shows progress | frontend | PASS | 2026-05-24T11:05Z |
| U-03 | Tenant isolation on list | backend | PASS | 2026-05-24T11:10Z |
| U-04 | Tenant isolation on retrieve | backend | FAIL | 2026-05-24T11:15Z |
| U-05 | Cross-tenant attempt → 404 | backend | FAIL | 2026-05-24T11:18Z |
| U-06 | a11y keyboard walk | frontend | PASS | 2026-05-24T11:20Z |

### Phase 02-invoices-list (stage: verified)
MISSING_UAT — no `02-UAT.md` found. Run `/release:verify-work 02`.

### Phase 03-veiculos-import (stage: verified-uat-pending, stale: true)
| ID | Item | Stack | Status | Verified At |
|---|---|---|---|---|
| U-01 | CSV upload endpoint | backend | PASS | 2026-05-22T09:00Z |
| U-02 | Progress toast | frontend | PASS | 2026-05-22T09:10Z |
| U-03 | End-to-end | fullstack | BLOCKED | 2026-05-22T09:15Z |
| U-04 | Error rows surface | fullstack | PENDING | — |

Stale: 4 commits landed on `feat/03-veiculos-import` after this walk. Re-run with `--reset`.

### Phase 04-veiculos-list (stage: shipped)
| ID | Item | Stack | Status | Verified At |
|---|---|---|---|---|
| U-01 | List render | frontend | PASS | 2026-05-25T08:00Z |
| U-02 | Import toast | frontend | FAIL | 2026-05-25T08:05Z |
| ... | ... | ... | ... | ... |

## Verdicts

| Verdict | Meaning |
|---|---|
| READY_FOR_MILESTONE | 0 FAIL, 0 BLOCKED, 0 PENDING, 0 MISSING_UAT, 0 stale |
| GAPS_BEFORE_SHIP | Any FAIL or any PENDING on `verified-uat-pending` phase |
| ENV_BLOCKED | All non-PASS are BLOCKED (no code gaps, just env) |
| COVERAGE_GAP | Any MISSING_UAT or stale on shipped/verified phases |
| MIXED | Combination — see hot list |

## Recommended next steps
1. Top of hot-list: U-02 on phase 04 (regression — escaped ship gate).
2. Resolve env block on phase 03 (Celery), then `/release:verify-work 03 --resume`.
3. Run `/release:verify-work 02` to close MISSING_UAT gap.
4. Re-run `/release:audit-uat` after fixes; expect verdict to flip toward READY_FOR_MILESTONE.
```

## Constraints

- Read-only on every UAT.md and SPEC/PLAN/SUMMARY. This skill never marks an item PASS or
  FAIL — only `/release:verify-work` does that.
- Single output file: `.release-planning/AUDIT-UAT.md`. Overwritten on each run (snapshot,
  not log). Git history preserves prior runs.
- Never `git commit`. Audit is advisory; user decides when to commit the snapshot.
- `--milestone` filter matches `ROADMAP.md` milestone heading — case-sensitive.
- Phases without `{NN}-UAT.md` are counted as `MISSING_UAT`, not zero items. Do not silently
  skip — that hides coverage gaps.
- `.planning/` is untouched — this plugin owns `.release-planning/` only.

## Example

```
/release:audit-uat --milestone v1.0

→ Scope: milestone v1.0 → phases 01, 02, 03, 04
→ Stage filter: executing+ → 4/4 phases included
→ Globbing UAT.md files: 3 found (02 missing)
→ Parsing 3 UAT.md (27 items total)
→ Cross-referencing STATE.md stages
→ Building hot list: 5 items
→ Stale detection: 1 phase (03 — 4 commits behind walk)

→ Writing .release-planning/AUDIT-UAT.md
→ Verdict: GAPS_BEFORE_SHIP (3 FAIL, 2 BLOCKED, 4 PENDING, 1 MISSING_UAT, 1 stale)

Next:
  1. Address top hot-list item: U-02 on phase 04 (regression)
  2. Re-run /release:audit-uat after each fix to track delta
```
