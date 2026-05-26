---
name: resume-work
description: >
  Restore context from a previously paused session captured under .release-planning/sessions/.
  Reads HANDOFF.md + cursor.yaml + git-state.txt, detects drift between pause and now
  (cursor moved, files now committed, branch changed), prints the briefing, and suggests
  the next /release:* command — but never auto-executes it. Multi-session aware: lists all
  paused sessions in reverse-chronological order and lets the user pick.
  Use when: returning from /clear, picking up someone else's handoff, or recovering after EOD.
---

# /release:resume-work — Session Restore from Handoff

The inverse of `/release:pause-work`. Reads a session directory, compares it against the
current worktree + cursor, surfaces any drift, prints the handoff, and points at the next
command. Restore is read-only — no commits, no checkouts, no auto-execution.

## Usage

```
/release:resume-work                       # interactive — pick from session list
/release:resume-work 2026-05-25-14h32      # explicit session ID
/release:resume-work --latest              # silent pick of newest session
/release:resume-work --list                # print sessions table, no restore
/release:resume-work --clear-after         # after restore, rm -rf the session dir
```

`--list` is the only flag that does not restore — it only prints. `--clear-after` is
opt-in cleanup for keeping `sessions/` lean after a session is truly done.

---

## Pre-checks (hard gates)

| # | Probe | Failure message |
|---|---|---|
| 1 | `test -d .release-planning/sessions` AND `ls .release-planning/sessions/` non-empty | `"No paused sessions. Use /release:status to see current cursor."` |
| 2 | If session ID passed: `test -d .release-planning/sessions/{ID}` | `"Session {ID} not found. Available: {list 5 most recent}"` |
| 3 | Session dir must contain `HANDOFF.md` + `cursor.yaml` (the load-bearing pair) | `"Session {ID} is corrupted — missing HANDOFF.md or cursor.yaml."` |

---

## Execution flow

### Step 1 — Resolve session ID

```
sessions = ls .release-planning/sessions/ | sort -r   # newest first lexically
```

Decision tree:

- `--latest` → pick `sessions[0]`, no prompt.
- explicit ID → use it, fail per pre-check #2 if absent.
- `--list` → print table (see Step 1b), exit.
- otherwise (interactive) → `AskUserQuestion` with sessions[0..9] as options
  (most recent 10), each labeled with timestamp + first line of its `HANDOFF.md`
  pause reason.

### Step 1b — `--list` table format

```
→ Paused sessions (most recent first)

  ID                      phase  stage     reason
  ──────────────────────  ─────  ────────  ──────────────────────────────────────
  2026-05-25-14h32        04     execute   tenant filter regression on bulk archive
  2026-05-24-18h05        04     execute   EOD — finished serializer, views next
  2026-05-23-11h47        03     verify    waiting on staging env for UAT-04
  2026-05-22-09h12        03     plan      blocked on LOCK-02 ambiguity

  4 sessions total. Restore with: /release:resume-work {ID}
```

Exit after printing — `--list` does not restore.

### Step 2 — Read session artifacts

```
HANDOFF.md     → full briefing text
cursor.yaml    → paused cursor frontmatter
git-state.txt  → paused git snapshot
open-files.txt → paused modified/untracked list
context.md     → paused author's narrative
```

If any file other than the load-bearing pair (HANDOFF.md + cursor.yaml) is missing, log
a warning but continue — they're informational only.

### Step 3 — Cursor drift detection

Parse `cursor.yaml` (paused) and `.release-planning/STATE.md` frontmatter (current).
Compare the cursor block field-by-field:

```
active_phase
active_stage
active_plan
last_completed_task
last_completed_commit
```

| Drift case | Action |
|---|---|
| All fields match | Print `"✓ Cursor unchanged — resume in place."` and continue. |
| Any field differs | Print drift table (paused → current), then `AskUserQuestion`: `"Cursor moved since pause. Continue restore anyway? [yes / abort]"`. Abort = exit 0, no further side effects. |

Drift detection is **informational** — never refuses on its own, only warns and asks.
This handles the common case where another session shipped a phase while this one was
paused.

### Step 4 — Git drift detection

Capture current state:

```bash
git status --short
git log --oneline -5
git rev-parse --abbrev-ref HEAD
```

Compare against `git-state.txt`. Report:

- **Branch changed?** `paused on feat/04-bulk-archive → now on main` → warn (handoff likely stale)
- **Files now committed that were modified at pause?** List them as `"resolved since pause"`.
- **Files now-modified that weren't at pause?** List as `"new changes since pause"`.
- **Stash list grew?** Note new stash entries.

Print as a compact diff table. Never abort on git drift — it's expected after a long
pause.

### Step 5 — Print HANDOFF.md

Dump the full contents of `HANDOFF.md` to stdout. Verbatim, no transformation. This IS
the briefing — the resuming session reads it like a hand-written note from past-you.

Format with a header divider so it's visually separated from the drift report:

```
─── HANDOFF.md ────────────────────────────────────────────────────────────────
{full file contents}
───────────────────────────────────────────────────────────────────────────────
```

### Step 6 — Suggested next action

Based on the paused cursor's `active_stage`, print exactly one suggested command. **Do
not execute it.** The user reads, decides, runs.

| Paused stage | Suggested next |
|---|---|
| `spec` | `/release:spec {NN}` |
| `discuss` | `/release:discuss {NN}` |
| `plan` | `/release:plan {NN}` |
| `execute` | `/release:execute {NN}` (resumes from last_completed_task) |
| `verify` | `/release:verify-work {NN}` |
| (null / between phases) | `/release:status` — let the user re-orient |

Print as:

```
→ Suggested next:  /release:execute 04
   (resumes from task T04 — last completed was T03 at commit a1b2c3)
```

### Step 7 — Optional cleanup (`--clear-after`)

If `--clear-after` was passed:

```bash
rm -rf .release-planning/sessions/{SESSION_ID}
```

Print `"→ Session dir removed (--clear-after)."` after the suggested-next line.

Without `--clear-after`, the session dir is left intact. Multiple resumes of the same
session ID are allowed — useful if the user resumes, gets interrupted, and resumes again.

### Step 8 — Update STATE.md history

Append one line to the `## Recent History` section of `.release-planning/STATE.md`:

```
- 2026-05-25 15:08 — Phase 04 resumed (from session 2026-05-25-14h32)
```

**Do NOT change the cursor frontmatter.** The cursor is already correct — the resume
is meta, not work.

---

## Constraints

- **Never auto-execute the suggested next command.** Print, don't dispatch. A long pause
  may mean the user's intent has shifted; surprise execution after a context gap is
  worse than an extra keystroke.
- **Never delete the session dir implicitly.** `--clear-after` is opt-in. The default
  is to accumulate history; pruning is a separate, deliberate act.
- **Drift detection is informational.** Never refuses to resume. Cursor drift prompts a
  yes/abort question; git drift is reported and ignored.
- **Read-only on `.planning/`.** GSD-owned, untouched.
- **No commits, no stashes, no checkouts.** Resume is restore + report — never mutates
  the worktree.
- **`HANDOFF.md` is the briefing.** Print it verbatim. Do not summarize. The author
  wrote it for a reason.

---

## Example

```
/release:resume-work

→ Paused sessions (most recent first)
  1. 2026-05-25-14h32  phase 04 execute  "tenant filter regression on bulk archive"
  2. 2026-05-24-18h05  phase 04 execute  "EOD — finished serializer, views next"
  3. 2026-05-23-11h47  phase 03 verify   "waiting on staging env for UAT-04"

  Pick session to restore?  [1 / 2 / 3 / abort]

> 1

→ Restoring session 2026-05-25-14h32...

→ Cursor drift check
  ✓ active_phase:        04 = 04
  ✓ active_stage:        execute = execute
  ✓ active_plan:         04-02-views = 04-02-views
  ✓ last_completed_task: T03 = T03
  ✓ Cursor unchanged — resume in place.

→ Git drift check
  branch:    feat/04-bulk-archive = feat/04-bulk-archive  ✓
  status:    2 modified, 1 untracked (was: 2 modified, 1 untracked)  ✓
  log head:  a1b2c3 (unchanged)  ✓
  → No git drift since pause.

─── HANDOFF.md ────────────────────────────────────────────────────────────────
# Handoff — 2026-05-25 14h32
## Cursor at pause: 04 / execute / 04-02-views / T03 (a1b2c3)
## Why pausing: tenant filter regression on bulk archive — UAT-02 fails.
## First step on resume: move empresa filter into TenantQuerySet.for_user().
## Resume command: /release:resume-work 2026-05-25-14h32
───────────────────────────────────────────────────────────────────────────────

→ Suggested next:  /release:execute 04
   (resumes from task T04 — last completed was T03 at commit a1b2c3)

→ STATE.md history updated.
   Session dir kept (use --clear-after to remove).
```

A drifted resume prints the changed fields (`active_phase: 04 → 05`, etc.) and prompts
`Cursor moved since pause. Continue restore anyway? [yes / abort]`.

---

## Notes

- **GSD analog:** `/gsd:resume-work` restores a single-slot handoff. release-sdk's
  `sessions/{ID}/` model means restore needs a picker step that GSD's equivalent skips.
  The trade-off is paid in interactivity for the gain of multi-pause history.
- **`--clear-after` housekeeping:** the recommended idiom is to resume without
  `--clear-after` first (in case the resume itself gets interrupted), then on a
  successful re-pause OR a successful phase completion, run a manual
  `rm -rf .release-planning/sessions/{ID}` to prune. There is intentionally no auto-prune
  — pause history is cheap to keep, and useful for post-mortems.
- **Cross-session handoff:** another teammate's pause is readable just by pulling the
  branch (or the `.release-planning/sessions/` dir). The HANDOFF.md is self-contained;
  the only environmental dependency is the worktree state, which the drift report
  surfaces explicitly.
- **Stack-agnostic.** Resume restores the cursor regardless of Django / React /
  fullstack. The suggested-next command is derived purely from the paused `active_stage`;
  the dispatched `/release:*` skill handles its own stack routing from PROJECT.md.

*Restores the moment. Drift surfaced, briefing printed, next step suggested, nothing
mutated. The pickup-where-you-left-off your pause deserves.*
