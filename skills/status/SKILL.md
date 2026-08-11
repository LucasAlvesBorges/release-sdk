---
name: status
description: >
  Show project status: current phase, active stage, recent commits, next suggested action.
  Detects full-stack state — reports Django phase progress + React phase progress separately.
  v0.23.0: reads `.progress.json` so a build IN FLIGHT is reported live (current task, tasks
  done/total, active envs, heartbeat age) instead of inferred from git log.
  Use any time to get a quick read on where things stand.
---

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
