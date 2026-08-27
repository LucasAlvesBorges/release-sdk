---
name: verify
description: Goal-backward phase verification that reuses the shared gate cache. Cross-phase integration is explicit with --integration.
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

# `/release:verify`

Verify delivered acceptance conditions without replaying tests already proven by the shared gate.

## Usage

```text
/release:verify [phase]
/release:verify [phase] --strict
/release:verify [phase] --integration
```

## Flow

1. Resolve the phase from the argument or current ROADMAP/STATE and read, once, its SPEC, PLAN, compact SUMMARY, locks, and existing VERIFICATION.
2. Source `bin/release-gate-lib.sh` and run `run_gate_cached "$repo" full`. A matching committed tree returns the prior GREEN evidence. Never invoke pytest, Vitest, lint, typecheck, migrations, or build separately when that evidence already covers them.
3. If the gate is RED or unresolved, write `GAPS_FOUND` with the gate evidence; do not launch broad duplicate suites. A dirty tree cannot reuse committed-tree evidence and must be reported explicitly.
4. Check each acceptance criterion goal-backward: wired implementation plus focused deterministic evidence. Check only risk surfaces triggered by the diff (for example tenancy/auth, migration preservation, concurrency, external input, or API/UI contract).
5. For C0-C2 with clear evidence, verify inline. Spawn one `release-phase-verifier` only for `--strict`, C3/C4 risk, or genuinely missing/stale acceptance evidence. Pass paths, changed files, and gate output/cache key—not copied documents or logs.
6. Write `{phase}-VERIFICATION.md` with `PASS`, `WARN`, or `GAPS_FOUND`, concise evidence per criterion, and next action. Never mark complete with gaps.

`--integration` is the only trigger for `release-integration-checker`. It checks seams across the explicitly relevant verified/shipped phases and writes `.release-planning/INTEGRATION-CHECK.md`. It is informational and does not rewrite a phase verdict. Phase count alone never triggers it.

## Stop conditions

- `PASS`: all acceptance conditions and locks have code/test evidence and the cached/current gate is GREEN.
- `WARN`: delivery is proven but a non-blocking risk remains.
- `GAPS_FOUND`: missing behavior/evidence, violated lock, RED/unresolved gate, or stale working tree.

Do not run separate backend and frontend verifiers. A fullstack phase is one acceptance surface; inspect only the changed seams.
