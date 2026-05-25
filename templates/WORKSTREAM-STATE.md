<!--
# WORKSTREAM-STATE.md
# Per-workstream cursor. Lives at .planning/workstreams/<name>/STATE.md.
# Mirrors the top-level STATE.md model but scoped to a single parallel feature track.
# Read by /release:workstreams and by stack skills when a workstream is active.
# Updated by workflow agents — rarely edited manually.
-->

---
name: null                        # workstream name, e.g., "payments"
stack: null                       # "backend" | "frontend" | "fullstack"
created_at: null                  # ISO8601 timestamp
branch: null                      # e.g., "ws-payments"
owner: null                       # author / responsible engineer (free text)
status: idle                      # "idle" | "in-progress" | "blocked" | "complete"
cursor:
  active_phase: null              # phase number, e.g., "01" or null when between phases
  active_stage: null              # "discuss" | "plan" | "execute" | "verify" | null
  active_plan: null               # plan slug if in execute, e.g., "01-02-serializers"
  last_completed_task: null       # task ID, e.g., "T03"
last_commit:
  sha: null                       # short sha of last commit on this workstream's branch
  subject: null                   # commit subject line
  at: null                        # ISO8601 timestamp
blockers: []                      # list of {phase, task, reason, raised_at}
updated_at: null
---

# Workstream State

## Workstream Name

{name from frontmatter}

## Stack

{stack from frontmatter — backend | frontend | fullstack}

Drives which release skills apply:
- `backend` → django-* skills (django-plan, django-execute, django-review, django-security)
- `frontend` → react-* skills (react-plan, react-execute, react-review)
- `fullstack` → release-* orchestrators (release-plan, release-execute, release-verify)

## Created At

{ISO8601 timestamp}

## Branch

{ws-<name>} (cut from `main` at create time)

All commits for this workstream MUST land on this branch. Verified by
`/release:workstreams status` against `git rev-parse --abbrev-ref HEAD`.

## Active Phase

{phase number — workstream-local, NOT global. e.g., "02 — refund-flow"}

Phases are scoped to this workstream's `ROADMAP.md`. The active-phase pointer
here is independent of the top-level `.planning/STATE.md`.

## Status

{idle | in-progress | blocked | complete}

| Status | Meaning |
|---|---|
| `idle` | Workstream scaffolded but no phase started yet |
| `in-progress` | At least one phase has begun, none currently blocked |
| `blocked` | A blocker is open (see Blockers section); `complete` will be refused |
| `complete` | All phases marked complete; ready for `/release:workstreams complete` |

## Last Commit

```
{sha}  {subject}
at {timestamp}
```

Latest commit on `ws-<name>`. Auto-refreshed by `/release:workstreams status`.

## Owner

{free text — typically the engineer running the workstream; may be empty}

Used for handoff routing and `list` rendering. Does not affect access control.

## Handoff Notes

{Free-form notes left for the next session. Updated by `/release:pause-work`-style
flows, or manually before logging off. Examples:}

- T04 blocked: gateway sandbox credentials pending from finance team.
- Tests through T03 are green. Do NOT touch FraudCheck module — refactor pending.
- Open question for review: should refund webhook be idempotent at DB layer or app layer?

When empty:

> No handoff notes. Workstream picks up from cursor only.

## Phase Index

Workstream-scoped phase manifest. Mirror of `ROADMAP.md` but with live status.

| # | Phase | Stack | Status | Active Stage | Started | Completed |
|---|---|---|---|---|---|---|
| 01 | {slug} | {stack} | {planned\|in-progress\|complete\|blocked} | {discuss\|plan\|execute\|verify\|—} | {date or —} | {date or —} |
| 02 | {slug} | {stack} | ... | ... | ... | ... |

Example:

| # | Phase | Stack | Status | Active Stage | Started | Completed |
|---|---|---|---|---|---|---|
| 01 | refund-models | backend | complete | — | 2026-05-22 | 2026-05-23 |
| 02 | refund-flow | fullstack | in-progress | execute | 2026-05-24 | — |
| 03 | refund-webhook | backend | planned | — | — | — |

## Blockers

{Empty when none. Each blocker: phase, task ID, reason, raised_at timestamp.}

Example:

- **Phase 02 / T04** — Gateway sandbox credentials missing.
  Raised: 2026-05-24 17:10. Owner: @finance-team.

## Recent History

{Last 5 stage/status transitions on this workstream, newest first.}

- 2026-05-24 17:10 — Phase 02 → blocked (T04 awaiting creds)
- 2026-05-24 14:32 — Phase 02 → execute (plan 02-01 started)
- 2026-05-24 11:18 — Phase 02 → plan complete (PLAN.md committed)
- 2026-05-23 16:00 — Phase 01 → complete
- 2026-05-22 09:30 — Workstream `payments` created from `main`

## Next Actions

{Suggested next steps based on cursor + workstream roadmap. Auto-rendered by
`/release:workstreams status` and `resume`.}

- "Resolve blocker on Phase 02 / T04, then resume with: `/release:execute 02 --resume`"
- OR: "All phases complete — run `/release:workstreams complete <name>` to merge & archive."
- OR: "Continue execute: `/release:execute 02 --frontend`"
