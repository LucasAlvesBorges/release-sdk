---
name: autonomous
description: >
  Run a bounded window of remaining roadmap phases serially using the compact spec, plan and
  single-pass execute pipeline. Resume-safe, aborts on first failure, never ships. Looping and
  conversational UAT are explicit flags rather than hidden per-phase costs.
---

# /release:autonomous — bounded milestone runner

## Usage

```text
/release:autonomous
/release:autonomous --from 03 --until 07
/release:autonomous --dry-run
/release:autonomous --loop
/release:autonomous --uat
```

## Preflight

Require `.release-planning/ROADMAP.md`, a clean main worktree and no half-finished phase worktree
outside the requested resume point. Resolve unshipped phases in the inclusive window. Print one
compact table showing which of SPEC/PLAN/EXECUTE will run and ask for one confirmation. `--dry-run`
stops there.

## Per phase

Run skills serially; do not spawn a separate orchestration fleet.

1. If `{NN}-SPEC.md` is absent, invoke `release:spec` to establish scope and acceptance.
2. If `{NN}-PLAN.md` is absent or deterministic `release-plan-lint.js` fails, invoke `release:plan`.
   Its decision preflight resolves remaining gray areas before spawning the planner. Abort if a
   required user decision cannot be settled; never accept a partial PLAN as a resume gate.
3. Invoke `release:execute {NN}`. Add `--loop` only when the user supplied it. Execute owns focused
   tests, the final gate, risk-based checking, worktree isolation and landing.
4. If `--uat`, invoke `release:verify-work`; otherwise do not add a second verification pipeline.
5. Append one small checkpoint to `.release-planning/autonomous-run.md`: phase, timestamps, actions,
   commits, gate/checker result, land state and next phase.

Abort on the first blocked/RED/GAPS/held state and preserve its branch/worktree. Print the evidence
path and exact resume command. Never revert user work, continue best-effort, auto-ship, push, merge a
held result, touch `.planning/`, or run phases in parallel.

On success, print one row per phase and suggest `/release:ship`; never invoke it. Existing compact
artifacts are resume gates, so rerunning `--from NN` must not repeat completed spec or plan work.
