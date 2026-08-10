---
name: debug
description: >
  Systematic debugging with persistent session state across context resets. Reads bug
  report (stack trace, repro steps, expected vs actual), spawns the `debugger`
  agent under a checkpoint protocol stored at `.release-planning/debug/{session_id}/`.
  Stack-aware: dispatches `stack: django|react|fullstack` to the agent based on the
  active phase or file signals in the repro.
  Use when: a bug is reported, a test fails unexpectedly, or behavior diverges from
  spec. Survives `/clear` and context compaction.
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

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation. Specifically: `gsd-debugger` → `release-debugger`.

---

# /release:debug — Persistent Bug Investigation

Scientific method, persisted to disk. Survives context resets.

## Usage

```
/release:debug "invoice export crashes with MemoryError on PDFs >10MB"
/release:debug --resume {session_id}     # continue prior session
/release:debug --list                    # show open debug sessions
/release:debug --close {session_id}      # close a resolved session
```

Empty arg → list open sessions and prompt user to pick one (or open a new one).

## Pre-checks

1. `.release-planning/` exists. Else abort: "Run `/release:init` first."
2. If `--resume {id}` set, `.release-planning/debug/{id}/SESSION.md` must exist.
3. If new session, generate `session_id = debug-{NN}-{slug-from-prompt}` where NN is the
   next free ordinal under `.release-planning/debug/`.

## Session layout

```
.release-planning/debug/{session_id}/
  SESSION.md          # checkpoint state — survives /clear
  HYPOTHESES.md       # ranked hypotheses + evidence log
  REPRO.md            # minimal reproduction (commands + expected/actual)
  FIX.md              # final fix + verification (written on close)
```

## Execution flow

### Step 1 — Stack detection

Detect stack from:
- Active phase in `.release-planning/STATE.md` (`stack: django|react|fullstack`)
- File extensions cited in the bug report (`.py` → django, `.tsx` → react)
- If neither signals → `AskUserQuestion`: "Stack for this debug?" → django / react / fullstack

### Step 2 — Spawn `release-debugger`

**Resolve the worker tier first** (see /release:auto → "Model-Tier Orchestration (LOCKED)"). The debugger
IS the worker — it runs its own inner loop (hypothesize → test → rule out → fix). You are the orchestrator;
self-identify — if your session model is Opus (not Fable): `export RELEASE_MODEL_PROFILE=opus-sonnet`:
```bash
find_lib(){ local p="${RELEASE_PLUGIN_ROOT:+$RELEASE_PLUGIN_ROOT/bin/$1}"; [ -n "$p" ]&&[ -f "$p" ]&&{ printf %s "$p"; return; }; find "${CODEX_HOME:-$HOME/.codex}" -name "$1" -path '*/bin/*' 2>/dev/null|head -1; }
MODEL_LIB="$(find_lib release-model-lib.sh)"; [ -f "$MODEL_LIB" ] && . "$MODEL_LIB"
WORKER_MODEL="$( [ -f "$MODEL_LIB" ] && release_worker_model || echo sonnet )"   # debugger maker tier (opus | sonnet)
```

```
Agent({
  subagent_type: "release-debugger",
  model: "{WORKER_MODEL}",     # worker tier — one rung below the orchestrator. NEVER omit.
  description: "Debug session {session_id}",
  prompt: "Operate at maximum rigor / max effort. {bug report from user}",
  metadata: { stack, session_id, session_path: ".release-planning/debug/{session_id}/" }
})
```

Agent owns the session. It writes `SESSION.md` after every checkpoint (hypothesis test,
ruled-out branch, partial fix). The user can `/clear` and `/release:debug --resume {id}`
to come back. When it reports `RESOLVED`, YOU (orchestrator/checker tier) confirm `FIX.md`'s
verification command actually passes before committing — maker≠checker.

### Step 3 — Close protocol

When the agent reports `verdict: RESOLVED`:

- Read `FIX.md` to confirm fix + verification command pass
- Print summary to user
- Move `.release-planning/debug/{session_id}/` → `.release-planning/debug/archive/{session_id}/`
- Stage + commit fix with: `fix({stack}): {one-line summary from FIX.md} ({session_id})`

If `verdict: ABANDONED` (user gives up): leave session in place; do not commit.

## Constraints

- **Persistent state.** Every meaningful step writes to `SESSION.md`. No relying on
  context window.
- **One session per invocation.** If multiple open sessions exist and no `--resume`, ask
  via `AskUserQuestion` which to advance.
- **Never auto-merge fixes.** The commit lands locally; `/release:ship` or manual push
  handles publication.
- **Never modify `.planning/`.** Debug state is release-sdk-owned.

## Example

```
/release:debug "invoice export → MemoryError on PDFs >10MB; happens in production
for tenant=acme; works locally for same PDF"

→ Stack: django (active phase 03-invoice-pdf-export, signal: .py in trace)
→ Session: debug-01-invoice-pdf-memory
→ Spawning release-debugger…
[agent runs, writes SESSION.md after each hypothesis]
[user /clear; user runs /release:debug --resume debug-01-invoice-pdf-memory; agent picks up]
[agent isolates: ReportLab streaming buffer not flushed; verdict: RESOLVED]
→ FIX.md verified: `pytest tests/test_pdf_export.py::test_large_pdf` passes
→ Archiving session, committing: fix(django): flush ReportLab buffer on large PDFs (debug-01-invoice-pdf-memory)
```

---

_Driven by `release-debugger` agent. Stack-aware. Checkpoint-persistent._
