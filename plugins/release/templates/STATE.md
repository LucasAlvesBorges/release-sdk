<!--
# STATE.md
# Single cursor pointing to current work. Read by every workflow command
# to determine "where am I and what's next".
# Updated by workflow agents — rarely edited manually.
-->

---
cursor:
  active_phase: null              # phase number, e.g., "01" or null when between phases
  active_stage: null              # "discuss" | "plan" | "execute" | "verify" | null
  active_plan: null               # plan slug if in execute, e.g., "01-01-models"
  last_completed_task: null       # task ID, e.g., "T03"
  last_completed_commit: null     # sha
blockers: []                      # list of {phase, task, reason, raised_at}
updated_at: null
---

# Project State

## Current Position

{Auto-generated narrative from cursor frontmatter.}

Example:
- "Active on Phase 01 (veiculo-bulk-import). Stage: execute. Plan: 01-02-serializers. Last task: T03 (commit a1b2c3)."
- OR: "No active phase. Next per ROADMAP: Phase 02 (estorno-flow)."

## Recent History

{Last 5 stage transitions, newest first.}

- 2026-05-25 14:32 — Phase 01 → execute (plan 01-02 started)
- 2026-05-25 14:28 — Phase 01 → plan complete (PLAN.md committed: d4e5f6)
- 2026-05-25 13:55 — Phase 01 → discuss complete (CONTEXT.md committed: g7h8i9)
- 2026-05-25 13:40 — Phase 01 → discuss started
- 2026-05-25 13:32 — Phase 01 created in ROADMAP

## Blockers

{Empty when none. Each blocker: phase, task ID, reason, surfaced_at timestamp.}

## Next Actions

{Suggested next steps based on cursor + roadmap:}

- "Continue execute: run /django:execute to resume from T04"
- OR: "Verify phase: run /django:verify 01"
- OR: "Start next: run /django:discuss 02"
