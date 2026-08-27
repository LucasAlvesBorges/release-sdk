---
name: loop
description: >
  Explicit bounded build→gate→check→fix loop. It is never implied by execute or quick. Uses cached
  gate evidence, delta-only fixer prompts, complexity-based iteration limits and a default spend
  ceiling. Phase mode delegates to execute --loop; freeform mode owns one isolated worktree.
---

# /release:loop — explicit autonomous correction

## Usage

```text
/release:loop 03
/release:loop "bounded goal"
/release:loop 03 --max-iters 3 --budget-usd 5
/release:loop 03 --no-land
```

## Defaults

Source economy, gate, loop, model and merge libs.

- C0/C1: one correction iteration.
- C2: two correction iterations.
- C3/C4: three correction iterations.
- Spend ceiling: `--budget-usd`, else `RELEASE_LOOP_BUDGET_USD`, else USD 5. A missing meter is
  reported; the iteration cap still applies.

Never default to six iterations or maximum effort.

## Phase mode

Invoke `/release:execute {NN} --loop` with the same budget/max/no-land flags. Do not duplicate the
phase engine here.

## Freeform mode

1. Reject feature/architecture scope and C3/C4 work without a SPEC.
2. Create one isolated `loop/<label>` worktree, or work in place inside a release session.
3. Build once inline for C0/C1 or with one `release:tdd-executor` for C2.
4. Run `run_gate_cached "$LWT" full`.
5. On RED, pass only the failing command, short relevant excerpt and evidence path to
   `release:code-fixer`. Do not resend the transcript or successful gate output.
6. On GREEN, run `release:loop-goal-verifier` once. It reuses the cached gate and checks only the
   requested behavior. On gaps, send only the gap IDs/evidence to the fixer.
7. Re-run the cached gate/checker until PASS or `loop_guard`/budget stops.
8. GREEN+PASS → land unless `--no-land`; otherwise retain the worktree and report the exact blocker.

Each round must change the git tree or stop as no-progress. A checker is a separate turn but uses the
worker tier for C0-C2 and the orchestrator tier only for C3/C4.
