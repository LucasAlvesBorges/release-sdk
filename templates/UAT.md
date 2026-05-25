<!--
# UAT.md — Phase {NN}: {phase-slug}
#
# Produced (and updated in place) by release-uat-conductor, spawned via /release:verify-work.
# Seeded from PLAN.md must_haves.truths + SPEC.md acceptance criteria + ROADMAP success_criteria.
#
# This file is the HUMAN gate for the phase — distinct from the machine gate written to
# {NN}-VERIFICATION.md by /release:verify. Both should be green before /release:ship.
-->

---
phase: {NN}
slug: {phase-slug}
generated_at: {YYYY-MM-DDTHH:MM:SSZ}      # set once on first creation
last_run_at: null                          # updated each time /release:verify-work runs
stack: backend | frontend | fullstack     # dominant stack for the phase
items_total: 0
items_pass: 0
items_fail: 0
items_blocked: 0
items_skip: 0
items_pending: 0
verdict: PENDING                           # PENDING | READY_TO_SHIP | GAPS_FOUND | BLOCKED | INCOMPLETE
---

# Phase {NN} — User Acceptance Testing

**Phase:** {NN} — {phase-slug}
**Generated:** {generated_at}
**Last run:** {last_run_at}
**Stack:** {backend | frontend | fullstack}

## How to use this file

1. Run `/release:verify-work {NN}` — release-uat-conductor walks you through each item.
2. For each item, the conductor surfaces concrete verification steps (curl for backend,
   browser walk for frontend, end-to-end for fullstack) and asks PASS / FAIL / BLOCKED / SKIP.
3. Your answers + free-text notes are written back here with timestamps.
4. The Summary + Next Step sections at the bottom drive what happens next.

Do NOT hand-edit the items table. Re-run with `--resume` (skip PASS) or `--reset` (start over) instead.

## UAT Items

| ID | Item | Stack | Steps | Status | Notes | Verified At |
|----|------|-------|-------|--------|-------|-------------|
| U-01 | {observable outcome from PLAN.md must_haves.truths} | backend \| frontend \| fullstack | {one-line script summary; conductor expands at runtime} | PENDING | — | — |
| U-02 | {next truth or success criterion} | backend \| frontend \| fullstack | {one-line script summary} | PENDING | — | — |
| U-03 | {next} | ... | ... | PENDING | — | — |

### Status values

| Status | Meaning |
|---|---|
| PENDING | Not yet walked |
| PASS | User confirmed the item works as specified |
| FAIL | User saw broken or missing behavior (see Notes) |
| BLOCKED | Cannot verify right now (env, fixture, dep on another item) |
| SKIP | User chose to skip this round |

## Summary

- Total items: {N}
- PASS: {N}
- FAIL: {N}
- BLOCKED: {N}
- SKIP: {N}
- PENDING: {N}

## Next Step

{One of the following, chosen by the conductor based on Summary:}

- **READY_TO_SHIP** — all items PASS. Run `/release:ship {NN}`.
- **GAPS_FOUND** — at least one FAIL. Run `/release:plan {NN} --gaps`, then `/release:execute {NN} --gaps` (add `--backend` or `--frontend` to scope). Re-run `/release:verify-work {NN} --resume` after fixes.
- **BLOCKED** — at least one BLOCKED (and no FAILs). Resolve environment / fixture / dependency blockers, then re-run `/release:verify-work {NN} --resume`.
- **INCOMPLETE** — items still PENDING (walk was aborted). Re-run `/release:verify-work {NN} --resume` to finish.

## Notes for the next run

- Failures and blockers are listed above with free-text notes captured during the walkthrough.
- These notes feed `/release:plan {NN} --gaps` — they are the bug report.
- Do not mark FAIL items as PASS to "unblock the ship" — use the gap loop instead.

---
_Driven by release-uat-conductor (release-sdk). Distinct from {NN}-VERIFICATION.md (machine gate)._
