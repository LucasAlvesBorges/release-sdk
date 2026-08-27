---
name: verify
description: Goal-backward phase verification that reuses the shared gate cache. Cross-phase integration is explicit with --integration.
---

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
5. For C0-C2 with clear evidence, verify inline. Spawn one `release:phase-verifier` only for `--strict`, C3/C4 risk, or genuinely missing/stale acceptance evidence. Pass paths, changed files, and gate output/cache key—not copied documents or logs.
6. Write `{phase}-VERIFICATION.md` with `PASS`, `WARN`, or `GAPS_FOUND`, concise evidence per criterion, and next action. Never mark complete with gaps.

`--integration` is the only trigger for `release:integration-checker`. It checks seams across the explicitly relevant verified/shipped phases and writes `.release-planning/INTEGRATION-CHECK.md`. It is informational and does not rewrite a phase verdict. Phase count alone never triggers it.

## Stop conditions

- `PASS`: all acceptance conditions and locks have code/test evidence and the cached/current gate is GREEN.
- `WARN`: delivery is proven but a non-blocking risk remains.
- `GAPS_FOUND`: missing behavior/evidence, violated lock, RED/unresolved gate, or stale working tree.

Do not run separate backend and frontend verifiers. A fullstack phase is one acceptance surface; inspect only the changed seams.
