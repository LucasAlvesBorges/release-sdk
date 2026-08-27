---
name: autonomous
description: >
  Run a bounded window of remaining roadmap phases serially using the compact spec, plan and
  single-pass execute pipeline. Resume-safe, aborts on first failure, never ships. Looping and
  conversational UAT are explicit flags rather than hidden per-phase costs.
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

1. If `{NN}-SPEC.md` is absent or `status` is not `ready`, invoke `release:spec`. Abort if HIGH open
   questions remain. Do not invoke `discuss` separately; spec owns decisions.
2. If `{NN}-PLAN.md` is absent or deterministic `release-plan-lint.js` fails, invoke `release:plan`.
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
