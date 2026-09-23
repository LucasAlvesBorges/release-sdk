---
name: loop
description: >
  Explicit bounded build→gate→check→fix loop. It is never implied by execute or quick. Uses cached
  gate evidence, delta-only fixer prompts, complexity-based iteration limits and a default spend
  ceiling. Phase mode delegates to execute --loop; freeform mode uses the development checkout.
---

## Codex runtime contract

This generated Codex skill preserves the source workflow with these overrides:

- Use current Codex tools: targeted reads, `rg`, `apply_patch`, and shell commands. Never look for
  Claude-only tool names or runtime state (`~/.claude`, `.claude*`, `CLAUDE.md`). Release artifacts
  stay in `.release-planning/`; project guidance comes from the applicable `AGENTS.md` chain.
- Before a write, a root `AGENTS.md` must exist. The hook returns `AGENTS_MD_REQUIRED`; in bootstrap
  mode only `release-agents-md-builder` may draft it, after which the user reruns the task.
- Score C0-C4 and apply risk floors before spawning. Default is no child. Spawn only when a bounded
  independent/specialist/noisy subtask avoids more context than it costs. C0/C1 stays inline; C2 uses
  at most one normal worker/planner; C3/C4 may use the strict fleet with disjoint ownership.
- Map source `release:<name>` agents to Codex `release-<name>` custom agents. Pass paths and task
  deltas, never the transcript, copied files, full logs, or `AGENTS.md` contents. Writers preserve
  concurrent work and own non-overlapping paths.
- Custom agents already pin their model/effort. Ignore Claude model names and `CLAUDE_EFFORT`; do not
  increase effort unless the C3/C4 risk actually requires it.
- A child returns compact `SubagentResultV1`; the parent decides completion. User input stays in the
  parent. Retry once at most, then narrow/stop instead of grinding.

`/release:<name>` is the source workflow label; in Codex select the corresponding release skill.

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
2. Work in the current dev checkout. Require a clean tree and create an
   in-place `loop/<label>` branch; never create a sibling worktree.
3. Build once inline for C0/C1 or with one `release-tdd-executor` for C2.
4. Run `run_gate_cached "$ROOT" quick` after every maker/fixer change. It runs the project quick
   profile and its diff-implied focused tests; it never substitutes a broad suite based on a step
   name or marker guess.
5. On quick RED, pass only the failing command, short relevant excerpt and evidence path to
   `release-code-fixer`. Do not resend the transcript or successful gate output.
6. On quick GREEN, run `release-loop-goal-verifier` once. It reuses the current-tree quick GREEN
   evidence and checks only the requested behavior. Its verdict is the literal `PASS` or `GAPS`; partial/"pending"
   wording is GAPS. On gaps, send only the gap IDs/evidence to the fixer. A fixer answer of
   `USER_INPUT_REQUIRED` or `needs_scope_reduction` ends the loop as a hard stop with the conflict
   printed; the goal is never narrowed to make the checker pass.
7. Only after checker PASS, run `run_gate_cached "$ROOT" full` once on that final committed tree,
   immediately before land. The full profile must contain the project's broad coverage steps; it may
   omit a focused step only when those broad steps actually cover the same runner and assertion lanes.
   On full RED, send only its failure evidence to the fixer and return to the quick gate.
8. After a checker gap or full RED, return to the quick gate. A full gate stays valid only for its
   exact committed tree; rerun quick → checker → full after every change until PASS or `loop_guard`/budget stops.
9. GREEN+PASS → land unless `--no-land`; otherwise retain the branch/evidence and report the exact
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
