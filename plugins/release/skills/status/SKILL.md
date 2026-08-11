---
name: status
description: >
  Show project status: current phase, active stage, recent commits, next suggested action.
  Detects full-stack state — reports Django phase progress + React phase progress separately.
  v0.23.0: reads `.progress.json` so a build IN FLIGHT is reported live (current task, tasks
  done/total, active envs, heartbeat age) instead of inferred from git log.
  Use any time to get a quick read on where things stand.
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

# /release:status — Project Status

Shows cursor, recent activity, next action. Full-stack aware.

## Usage

```
/release:status                      # full status
/release:status --short              # one-liner: "Phase 02 → frontend execute-complete"
```

## What it shows

1. **Current cursor** — from STATE.md: active phase, active stage (discuss/plan/execute/verify)
2. **Build in flight (v0.23.0)** — read `.release-planning/phases/{NN}-*/.progress.json` BEFORE
   falling back to git-log archaeology. A running `/release:execute` maintains it on every dispatch,
   land and checkpoint, so this is the difference between "the phase is doing T12 of 19, 2 envs up,
   last commit 4 minutes ago" and a blind grep:

```bash
PROG_LIB="$(find_lib release-progress-lib.sh)"; [ -f "$PROG_LIB" ] && . "$PROG_LIB"
for PD in .release-planning/phases/*/; do
  [ -f "$PD/.progress.json" ] || continue
  AGE="$(progress_stale_seconds "$PD")"
  printf '🔄 phase %s — %s %s/%s tasks · in-flight %s · envs %s · updated %ss ago\n' \
    "$(progress_get "$PD" phase)" "$(progress_get "$PD" task)" \
    "$(progress_get "$PD" tasks_done)" "$(progress_get "$PD" tasks_total)" \
    "$(progress_get "$PD" in_flight)" "$(progress_get "$PD" envs_active)" "$AGE"
  [ -n "$(progress_get "$PD" note)" ] && printf '   note: %s\n' "$(progress_get "$PD" note)"
done
```

   - `updated > 1800s ago` → say **"⚠ no heartbeat for Ns — the build may be stuck"** and point at
     the worktree. The executors heartbeat every 30 min precisely so silence means something.
   - A progress file whose phase has a `SUMMARY.md` and no live worktree is **stale** — report it as
     leftover state, not as a running build (`git worktree list` disambiguates).
3. **Recent commits** — `git log --oneline -10`
4. **Quality gates status** — last REVIEW.md verdict, last SECURITY.md verdict
5. **Next suggested action** — based on current stage:

| Current stage | Suggested next |
|---|---|
| `init-complete` | `/release:roadmap` |
| `discuss-complete` | `/release:plan {NN}` |
| `plan-complete (backend)` | `/release:execute {NN} --backend` |
| `plan-complete (frontend)` | `/release:execute {NN} --frontend` |
| `execute-complete (backend)` | `/release:execute {NN} --frontend` (if fullstack) |
| `execute-complete` | `/release:verify {NN}` |
| `verify-complete (PASS)` | `/release:review {NN}` or start next phase |
| `verify-complete (GAPS_FOUND)` | `/release:plan {NN} --gaps` |

## Example output

```
/release:status

━━━ release-sdk status ━━━━━━━━━━━━━━━━━━━━━━━━━━

Project:    Invoice Management SaaS
Phase:      02 — invoice-list-page
Stack:      FULLSTACK

  Backend:  ✅ execute-complete (SUMMARY.md present)
  Frontend: 🔄 execute-in-progress (T02/4 tasks done)

Recent commits (last 5):
  a1b2c3  feat(ui): implement InvoiceList component
  d4e5f6  test(ui): add failing tests for InvoiceList
  g7h8i9  feat(financeiro): implement invoice list endpoint
  j0k1l2  test(financeiro): add 9-category security tests
  m3n4o5  refactor(financeiro): apply Q1-Q7

Quality gates:
  Last review:   .release-planning/phases/02-invoice-list/REVIEW.md — 0 BLOCKERs, 2 WARNINGs
  Last security: .release-planning/phases/02-invoice-list/02-SECURITY.md (backend) — 9/9 CLOSED

Next suggested action:
  → /release:execute 02 --frontend --resume   (continue from T03)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
