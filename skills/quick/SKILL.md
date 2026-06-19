---
name: quick
description: >
  Execute a bounded task with release-sdk guarantees (atomic commits, light state
  tracking) but skip the heavy phase machinery (no SPEC, no DISCUSS, no formal PLAN,
  no UI-SPEC, no AI-SPEC, no formal verification). Stack-aware via active phase or
  task content. Logs the run to `.release-planning/quick-log.md` for traceability.
  Use when: multi-file edit that's too big for `/release:fast` but doesn't need a
  formal phase (e.g., "add a new field to the Invoice model + migration + serializer
  + form", "swap library X for Y across three files").
---

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation.

---

# /release:quick — Bounded Task, Light Envelope

Between `/release:fast` (no envelope) and `/release:plan` (full envelope).

## Usage

```
/release:quick add `archived_at: DateTimeField(null=True)` to Invoice model + migration + serializer
/release:quick replace `axios` with `ky` in the three files that use it
/release:quick wire CSRF cookie passthrough in the React dev proxy
```

## Pre-checks

1. `.release-planning/` exists. Else: "Run `/release:init` first."
2. Task scope sanity: if request implies > 10 files OR mentions "new feature", "design",
   "architecture", "spec" → abort with:
   > "Task looks like a feature. Use /release:spec to start a real phase."

> **No "worktree clean" precondition (v0.17.0).** `/release:quick` isolates by default — it works in
> its own ephemeral worktree off base — so your main checkout can stay dirty. Keep running and testing
> the app while the quick works. Any number of quicks (and a running `/release:execute`) proceed in
> parallel without ever colliding. A dirty base checkout only affects *landing*: the merge-back is
> **held** (your uncommitted work is never clobbered) and you finish it later with `/release:land`.

## Execution flow

### Step 1 — Stack detection

From active phase in `.release-planning/STATE.md` if present; else from file extensions
in the task description; else ask user via `AskUserQuestion`: django / react / fullstack.

### Step 2 — Isolate (default) or commit-in-session

**Inside a `/release:session` worktree** (`.release-planning/.session` exists): do NOT nest another
worktree. Spawn the executor with `cwd: "."` and commit in place on the current `session/<label>`
branch — the session's own `finish` lands it. Skip Step 4 (no separate land).

**Otherwise (default): cut an ephemeral worktree off base.** The main checkout is never touched, so
N quicks + a phase execute all run concurrently:

```bash
MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"
# land target = the branch you're actually testing on = the main checkout's current branch
BASE="$(git -C "$MAIN_ROOT" rev-parse --abbrev-ref HEAD)"
SLUG="$(printf '%s' "<first words of task>" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | cut -c1-30)"; SLUG="${SLUG:-task}"
LABEL="q-$(date +%Y%m%d-%H%M%S)-$SLUG"
BRANCH="quick/$LABEL"
QWT="$MAIN_ROOT/../release-worktrees/quick/$LABEL"
mkdir -p "$(dirname "$QWT")"; git -C "$MAIN_ROOT" worktree prune
git -C "$MAIN_ROOT" worktree add -q -b "$BRANCH" "$QWT" "$BASE"   # branch off base tip; main checkout read-only
```

### Step 3 — Spawn TDD executor with `quick_mode: true` (in the worktree)

```
Agent({
  subagent_type: "release:tdd-executor",
  description: "Quick task: {first-30-chars-of-task}",
  prompt: "Work ENTIRELY within {QWT} (cd there first; all edits, tests, and commits happen there). {full task description}",
  metadata: {
    stack,
    quick_mode: true,
    no_plan: true,
    no_spec: true,
    write_state: false,        # quick runs do not move the phase cursor
    cwd: "{QWT}",              # ALL git ops run in the isolated worktree (in-session path: cwd ".")
    branch_already_set: true   # worktree already on quick/<label> → executor skips its own branch setup
  }
})
```

The executor: writes failing test(s) first (TDD) → implements → refactors → atomic commit per logical
unit (typically 1-3 commits). All commits land on `quick/<label>` inside `$QWT`; the main checkout
sees nothing yet.

### Step 4 — Auto-land on green (default)

If the executor reports **GREEN** (tests pass) and `--no-merge` was NOT passed, land the work back onto
base through the shared, serialized, conflict-safe engine — the SAME `land_branch` that powers
`/release:session finish` (and `/release:execute`). Lands serialize on a per-base lock, so concurrent
quicks/phases never corrupt base:

```bash
RELEASE_LIB="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/release-merge-lib.sh}"
[ -n "$RELEASE_LIB" ] && [ -f "$RELEASE_LIB" ] || RELEASE_LIB="$(find "$HOME/.claude" -name release-merge-lib.sh -path '*/bin/*' 2>/dev/null | head -1)"
[ -f "$RELEASE_LIB" ] || { echo "ABORT: release-merge-lib.sh not found (set CLAUDE_PLUGIN_ROOT)."; exit 1; }
. "$RELEASE_LIB"

RESULT="$(land_branch "$BRANCH" "$QWT" "$BASE" | tail -1)"
cd "$MAIN_ROOT"   # land may remove $QWT from under us → stand in the main checkout afterwards
case "$RESULT" in
  RESULT=merged)     echo "✓ landed on $BASE (live) — if your app runs on $BASE, hot-reload already has it." ;;
  RESULT=held-dirty) echo "⏸ $BASE has uncommitted work — quick kept on $BRANCH, NOT landed. Commit/stash, then: /release:land $LABEL" ;;
  RESULT=conflict)   echo "✗ code conflict vs $BASE. Resolve in $QWT, commit, then: /release:land $LABEL" ;;
  RESULT=refused)    echo "✗ merge refused (untracked-file collision). Clean $QWT, then: /release:land $LABEL" ;;
  RESULT=locked)     echo "⏳ another land is in progress. Retry: /release:land $LABEL" ;;
  *)                 echo "✗ land failed ($RESULT). Worktree kept at $QWT." ;;
esac
```

- **GREEN + `--no-merge`** → skip land; leave `quick/<label>` + worktree for a later `/release:land <label>`.
- **RED (tests fail)** → do NOT land. Keep `$QWT` for debugging; print its path. Base and main checkout untouched.

### Step 5 — Log to quick-log

Append to `.release-planning/quick-log.md` (create if missing):

```markdown
## {ISO timestamp} — {stack} — {first-line-of-task}

- Branch: quick/{label}
- Commits: {sha1}, {sha2}
- Files: {touched files list}
- Tests added: {test file paths}
- Land: {landed on <base> | held-dirty (run /release:land) | kept --no-merge | RED (not landed)}
```

This is the only state side-effect — STATE.md and active-phase cursor are NOT touched.

### Step 6 — Report

Print to user: commits made (sha + subject), tests added, the land outcome, and the next step
(nothing if landed; `/release:land {label}` if held/conflict; `/release:status` to confirm cursor unchanged).

## Constraints

- **Isolated by default.** Runs in its own `quick/<label>` worktree off base. N quicks + a phase
  `execute` run in parallel without collision. (Inside a session, commits in-place instead.)
- **Auto-lands on green** via the shared `land_branch` engine — serialized + conflict-safe. A dirty
  live base checkout is held, never clobbered (`/release:land` finishes it).
- **No phase cursor move.** `/release:quick` is sideways work; it doesn't advance `active_phase`/`active_stage`.
- **TDD-first via `release:tdd-executor`.** No "implement then test later" shortcut.
- **Atomic commits.** Each commit is independently revertable.
- **No push.** Landing is a local merge onto base; pushing is the user's call.
- **No SPEC, no PLAN, no UI-SPEC.** If those artifacts are needed, the task is too big — reroute to `/release:spec`.

## Example

```
/release:quick add `archived_at` to Invoice + migration + serializer + admin

→ Scope: 4 files — within envelope ✓   (main checkout may be dirty — quick isolates)
→ Stack: django (active phase 03 = django)
→ Worktree quick/q-20260619-153012-add-archived-at off dev ✓
→ Spawning release:tdd-executor (quick_mode) in the worktree…
  [RED test → field + makemigrations → serializer + admin → GREEN → commit]
→ land quick/… → dev: ✓ merged (live). App on dev hot-reloaded the new field.
→ Logged to .release-planning/quick-log.md. Cursor unchanged (still phase 03 executing).
```

(If `dev` had uncommitted edits at land time: `⏸ held — commit/stash, then /release:land q-20260619-153012-add-archived-at`.)

---

_Bounded task. Isolated worktree. Auto-lands on green via the shared serialized merge-back. Driven by `release:tdd-executor` in quick mode._
