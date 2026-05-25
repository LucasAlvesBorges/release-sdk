---
description: >
  Capture a session handoff snapshot before /clear, end-of-day, or any forced context reset.
  Writes a timestamped session directory under .release-planning/sessions/{YYYY-MM-DD-HHhMM}/
  with HANDOFF.md, cursor snapshot, git state, open files, and a free-text context note.
  Never commits, never stashes, never mutates the worktree — pause is purely additive metadata.
  Use when: pausing mid-phase, dropping context, or handing work off to another teammate / session.
allowed_tools: Read, Write, Bash, Grep, Glob, AskUserQuestion
---

# /release:pause-work — Session Handoff Snapshot

Freezes "where I am right now" into a timestamped session directory so the next session
(or the next human) can pick up exactly where this one stopped. Multi-pause friendly: every
invocation creates a new directory, nothing is ever overwritten.

## Usage

```
/release:pause-work                                      # interactive — asks why + what's next
/release:pause-work "stuck on tenant filter regression"  # inline note, skips the prompt
/release:pause-work --no-prompt                          # autocapture only (for hooks)
/release:pause-work --report                             # also print HANDOFF.md to stdout
```

The inline-note form short-circuits the AskUserQuestion prompt. `--no-prompt` is for
hook-triggered use (e.g., stop hooks); it captures git state + cursor and writes a stub
`context.md` saying `"autocaptured — no user note"`.

---

## Pre-checks (hard gates)

| # | Probe | Failure message |
|---|---|---|
| 1 | `test -d .release-planning` | `".release-planning/ not found — nothing to pause. Run /release:init first."` |
| 2 | Capture `git status --short` + `git diff --stat` + `git log --oneline -5` BEFORE any write | (no failure — just must run first so the snapshot reflects pre-pause state) |

Pre-check #2 is ordering, not a gate: any state-capture command must run before the
session directory exists, so the snapshot can never accidentally include the snapshot's
own metadata.

---

## Execution flow

### Step 1 — Generate session ID

```bash
SESSION_ID=$(date '+%Y-%m-%d-%Hh%M')
```

Local timezone. Sortable lexically. Example: `2026-05-25-14h32`.

If `.release-planning/sessions/{SESSION_ID}/` already exists (called twice within the
same minute), append `-2`, `-3`, ... until a free slot is found. **Exception:** if a
prior call created the dir within the last 60s AND no inline note was passed AND
`--no-prompt` is not set, treat this as an idempotent continuation: skip directory
creation, only refresh `context.md` with the new user note. This prevents accidental
double-pauses (e.g., hook fires then user manually re-invokes).

### Step 2 — Capture pre-pause state

Run in a single bash invocation and stash output in memory: `git status --short`,
`git diff --stat`, `git log --oneline -5`, `git stash list`, `git ls-files -m`, and
`git ls-files --others --exclude-standard`.

### Step 3 — Create session directory

```bash
mkdir -p .release-planning/sessions/${SESSION_ID}
```

### Step 4 — Write `cursor.yaml`

Copy the frontmatter block from `.release-planning/STATE.md` verbatim. This is the
load-bearing artifact — restore drift detection in `/release:resume-work` compares
against it byte-for-byte.

```yaml
# Snapshot of STATE.md cursor at pause time.
# Do not edit by hand. Compared against live STATE.md on resume.
---
cursor:
  active_phase: "04"
  active_stage: "execute"
  active_plan: "04-02-views"
  last_completed_task: "T03"
  last_completed_commit: "a1b2c3"
blockers: []
updated_at: 2026-05-25T14:32:11-03:00
---
```

### Step 5 — Write `git-state.txt`

Concatenate the four git outputs from Step 2 with `## git status --short`, `## git diff
--stat`, `## git log --oneline -5`, `## git stash list` section headers. Empty sections
render as `(empty)`.

### Step 6 — Write `open-files.txt`

Two sections: `## modified (git ls-files -m)` listing modified-tracked files, and
`## untracked (git ls-files --others --exclude-standard)` listing untracked-not-ignored
files. Empty sections render as `(none)`.

### Step 7 — Write `context.md`

If inline note was passed → write it as the `## Why pausing` block, leave the rest as
TODO stubs.

If no inline note AND `--no-prompt` is not set → use `AskUserQuestion` with four prompts:

1. **Why pausing now?** (free text)
2. **Last attempted — PASS / FAIL / in-progress?** (one-line summary)
3. **First step when resuming?** (concrete next command or file to touch)
4. **Open questions or pending decisions?** (free text — can be empty)

If `--no-prompt` → write a minimal stub with `_Autocaptured — no user note._` and each
section set to `(not specified)`.

Otherwise, format the answers:

```markdown
# Pause context

## Why pausing
Stuck on tenant filter regression on bulk archive — UAT-02 fails when empresa_id is
inherited via M2M relation.

## Last attempted
FAIL — added `queryset.filter(empresa=user.empresa)` in `BulkArchiveView`, broke 3 other
tests because they share the queryset via mixin.

## First step on resume
Move the empresa filter into `TenantQuerySet.for_user()` instead of inlining it in the
view. Re-run `pytest apps/invoices/tests/test_views.py::TestBulkArchive`.

## Open questions
- Should the mixin enforce `for_user()` at compile time (raise on bare `.objects`)?
- LOCK-02 doesn't currently mandate that — worth re-discussing at next /release:discuss.
```

### Step 8 — Write `HANDOFF.md`

The single document the resuming session reads first. Assemble from all preceding
artifacts:

```markdown
# Handoff — 2026-05-25 14h32

Session paused mid-phase. This file is the briefing for whoever picks the work back up.

## Cursor at pause
- Phase:  04 (invoice-bulk-archive) — stage execute, plan 04-02-views
- Last task:  T03 (commit a1b2c3)

## Why pausing
Stuck on tenant filter regression on bulk archive — UAT-02 fails when empresa_id is
inherited via M2M relation.

## What was last attempted
FAIL — added `queryset.filter(empresa=user.empresa)` in `BulkArchiveView`, broke 3 other
tests because they share the queryset via mixin.

## First step on resume
Move the empresa filter into `TenantQuerySet.for_user()` instead of inlining it in the
view. Re-run `pytest apps/invoices/tests/test_views.py::TestBulkArchive`.

## Open questions
- Should the mixin enforce `for_user()` at compile time? LOCK-02 doesn't mandate it today.

## Worktree at pause (DIRTY)
- 2 files modified, 1 untracked on `feat/04-invoice-bulk-archive`.
- See `git-state.txt` + `open-files.txt` for full lists.

## Resume command
`/release:resume-work 2026-05-25-14h32`

## How to read this handoff
1. `cursor.yaml` — STATE.md frontmatter at pause time (used for drift detection).
2. `git-state.txt` — full git snapshot (status / diff / log / stash).
3. `open-files.txt` — what was uncommitted at pause.
4. `context.md` — narrative from the paused author.
```

### Step 9 — Update STATE.md history

Append a single line to the `## Recent History` section of `.release-planning/STATE.md`:

```
- 2026-05-25 14:32 — Phase 04 paused (session 2026-05-25-14h32)
```

**Do NOT change the cursor frontmatter.** The cursor IS the resume point — touching it
would defeat the purpose. The history line is the only mutation to STATE.md.

### Step 10 — Print resume hint

```
→ Paused. Session: .release-planning/sessions/2026-05-25-14h32/
  Resume:  /release:resume-work 2026-05-25-14h32
  Or:      /release:resume-work --latest
```

If `--report` was passed, also dump the full `HANDOFF.md` contents to stdout afterwards
so the user can copy-paste it into a Slack / Linear / email handoff message.

---

## Constraints

- **No commits, no stashes, no checkouts.** Worktree is read-only from this skill's side.
- **Never overwrite a session dir.** Timestamp collision → append `-2`, `-3`, ...
- **Within-minute idempotency.** Re-invoking inside 60s without a new inline note refreshes
  `context.md` only; never duplicates the snapshot.
- **Read-only on `.planning/`.** That's GSD-owned. Only `.release-planning/` is touched.
- **Never advance the cursor.** Pause does NOT mark the phase as anything-completed. The
  next `/release:resume-work` reads the cursor verbatim and continues from there.
- **`AskUserQuestion` is mandatory in interactive mode.** Don't infer the pause reason from
  context — the value of a handoff is in the human-authored note.

---

## Example

```
/release:pause-work "tenant filter regression on bulk archive"

→ Capturing pre-pause state...
  · git status --short  (2 modified, 1 untracked)
  · git diff --stat     (58 insertions, 2 deletions)
  · git log -5          (last commit a1b2c3)
  · cursor.yaml         (phase 04, stage execute, plan 04-02)

→ Session dir: .release-planning/sessions/2026-05-25-14h32/
  · cursor.yaml      ✓
  · git-state.txt    ✓
  · open-files.txt   ✓
  · context.md       ✓ (inline note)
  · HANDOFF.md       ✓

→ STATE.md history updated (cursor unchanged).

→ Paused. Resume: /release:resume-work 2026-05-25-14h32
```

---

## Notes

- **GSD analog:** `/gsd:pause-work` uses a single-slot pattern (one handoff file,
  overwritten on each pause). release-sdk diverges intentionally: multi-session history
  is preserved under `sessions/{ID}/` so a long-running phase can accumulate several
  pauses without losing earlier context. The trade-off is a `sessions/` directory that
  needs occasional pruning — see `/release:resume-work --clear-after`.
- **Hook integration:** `--no-prompt` mode is designed for stop-hook auto-pause. A
  recommended hook fires `/release:pause-work --no-prompt` on Claude Code session end so
  the user never loses context to an unexpected `/clear`.
- **Not a substitute for commits.** If the worktree has finished work, commit it first —
  pause is for in-flight / broken / mid-edit state, not for storing completed work.
- **Stack-agnostic.** Pause captures git + cursor regardless of Django / React /
  fullstack. The dispatched `/release:*` workflow skills handle stack-specific resume
  logic; pause is just the snapshot.

*Freezes the moment. No mutations, no surprises, no lost context. The save-point your
mid-phase deserves before `/clear` eats it.*
