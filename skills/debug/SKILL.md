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

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation. Specifically: `gsd-debugger` → `release:debugger`.

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

### Step 2 — Spawn `release:debugger`

**Resolve the worker tier first** (see /release:auto → "Model-Tier Orchestration (LOCKED)"). The debugger
IS the worker — it runs its own inner loop (hypothesize → test → rule out → fix). You are the orchestrator;
self-identify — if your session model is Opus (not Fable): `export RELEASE_MODEL_PROFILE=opus-sonnet`:
```bash
find_lib(){ local p="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/$1}"; [ -n "$p" ]&&[ -f "$p" ]&&{ printf %s "$p"; return; }; find "$HOME/.claude" -name "$1" -path '*/bin/*' 2>/dev/null|head -1; }
MODEL_LIB="$(find_lib release-model-lib.sh)"; [ -f "$MODEL_LIB" ] && . "$MODEL_LIB"
WORKER_MODEL="$( [ -f "$MODEL_LIB" ] && release_worker_model || echo sonnet )"   # debugger maker tier (opus | sonnet)
```

```
Agent({
  subagent_type: "release:debugger",
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
→ Spawning release:debugger…
[agent runs, writes SESSION.md after each hypothesis]
[user /clear; user runs /release:debug --resume debug-01-invoice-pdf-memory; agent picks up]
[agent isolates: ReportLab streaming buffer not flushed; verdict: RESOLVED]
→ FIX.md verified: `pytest tests/test_pdf_export.py::test_large_pdf` passes
→ Archiving session, committing: fix(django): flush ReportLab buffer on large PDFs (debug-01-invoice-pdf-memory)
```

---

_Driven by `release:debugger` agent. Stack-aware. Checkpoint-persistent._
