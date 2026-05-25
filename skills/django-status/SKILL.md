---
description: >
  Show current STATE.md cursor — which phase is active, which stage (discuss/plan/execute/verify),
  blockers, recent history, suggested next action. Read-only situational awareness.
  Use when: returning to project after time away, checking "where am I", deciding what to do next.
allowed_tools: Read, Bash, Glob
---

# /django:status — Project Position Snapshot

Read-only summary of where the project is right now. Suggests next action.

## Usage

```
/django:status                  # full status
/django:status --short          # one-line cursor only
/django:status --next           # only "what to do next" hint
```

## Workflow

1. Read `.planning/STATE.md`.
2. Read `.planning/ROADMAP.md` — count phases by status.
3. Read `.planning/REQUIREMENTS.md` — count open/done REQs.
4. Read recent git log: `git log --oneline -10 -- .planning/`.
5. Detect uncommitted planning changes: `git status --porcelain .planning/`.
6. Render summary.

## Output (full)

```
═══════════════════════════════════════════════════════════
  django-sdk · Project Status · 2026-05-25 15:42
═══════════════════════════════════════════════════════════

  Active phase:    01 — veiculo-bulk-import
  Stage:           execute
  Plan:            01-02-serializers-view
  Last task:       T03 (commit a1b2c3)
  Blockers:        none

  Roadmap:         1 in-progress / 4 not-started / 0 complete (5 total)
  Requirements:    0 done / 8 open
  Last commit:     14:32 — feat(financeiro): implement bulk import view

  Recent activity:
    14:32  Phase 01 → execute (plan 01-02 started)
    14:28  Phase 01 → plan complete (PLAN.md committed: d4e5f6)
    13:55  Phase 01 → discuss complete (CONTEXT.md committed: g7h8i9)
    13:40  Phase 01 → discuss started

  Uncommitted:    .planning/STATE.md (modified)

  ─────────────────────────────────────────────────────────
  Next action:
    Continue execute:
      /django:execute 01 --resume    # resume from T04
    Or check progress:
      /django:checklist .planning/phases/01-veiculo-bulk-import/
═══════════════════════════════════════════════════════════
```

## Output (--short)

```
01 / execute / 01-02-serializers-view / T03 ✓ / no blockers
```

## Output (--next)

```
→ Continue execute: /django:execute 01 --resume
```

## What it surfaces

- **Where am I?** active_phase, active_stage, active_plan
- **What's done?** last_completed_task + commit
- **What's blocked?** blockers from STATE.md
- **What's pending?** open REQs, not-started phases
- **Recent activity:** last 5 stage transitions
- **Uncommitted:** any pending .planning/ changes
- **Suggested next:** based on cursor + roadmap
