---
name: loop
description: >
  Explicit bounded build→gate→check→fix loop. It is never implied by execute or quick. Uses cached
  gate evidence, delta-only fixer prompts, complexity-based iteration limits and a default spend
  ceiling. Phase mode delegates to execute --loop; freeform mode uses the development checkout.
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

Before building, consume the same stable project dev runner as `execute`/`quick`; export and pass
its prefix to every maker/fixer and gate invocation. Reject managed or phase-local EXEC-ENV before
any worker. Never provision or tear down containers/databases.

1. Reject feature/architecture scope and C3/C4 work without a SPEC.
2. Work in the current dev checkout. Outside a release session require a clean tree and create an
   in-place `loop/<label>` branch; never create a sibling worktree.
3. Build once inline for C0/C1 or with one `release:tdd-executor` for C2.
4. Run `run_gate_cached "$ROOT" full`.
5. On RED, pass only the failing command, short relevant excerpt and evidence path to
   `release:code-fixer`. Do not resend the transcript or successful gate output.
6. On GREEN, run `release:loop-goal-verifier` once. It reuses the cached gate and checks only the
   requested behavior. On gaps, send only the gap IDs/evidence to the fixer.
7. Re-run the cached gate/checker until PASS or `loop_guard`/budget stops.
8. GREEN+PASS → land unless `--no-land`; otherwise retain the branch/evidence and report the exact
   blocker. The existing dev environment remains untouched.

Each round must change the git tree or stop as no-progress. A checker is a separate turn but uses the
worker tier for C0-C2 and the orchestrator tier only for C3/C4.

## Common implementation quality — mandatory

Maker and fixer rounds leave touched code cleaner without opportunistic rewrites: meaningful names,
cohesive single-purpose functions, guard clauses, named boolean predicates and no newly duplicated
knowledge. Replace narration comments with self-explanatory code while retaining rationale/safety
comments. Prefer zero to two arguments when natural and group only a cohesive concept. Split classes
or introduce value/domain objects only at a proven responsibility/invariant seam; replace stable
long conditionals with dispatch or polymorphism only when simpler. Refactoring starts from green
tests and advances in reversible baby steps with a focused test after each logical step. Every step
must preserve public signatures and observable behavior.
