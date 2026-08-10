# Model routing reference (Codex token-economy policy)

Referenced by `agent-contract.md` and `skill-contract.md`. Load only when a
skill needs to pick or escalate a model/reasoning tier — not injected inline
everywhere.

## Tiers

| Tier | Model | Use |
|---|---|---|
| Luna | `gpt-5.6-luna` | Clear, narrow, repetitive, high-volume, or mechanical work |
| Terra | `gpt-5.6-terra` | Everyday implementation, moderate investigation, common review |
| Frontier | `gpt-5.6` | Complex planning, ambiguous reasoning, architecture, security-critical, high-stakes decisions |

## Reasoning effort

| Effort | Use |
|---|---|
| `low` | Direct, mechanical work |
| `medium` | Balanced default |
| `high` | Complex logic, edge cases, review, security |
| `xhigh` | Exceptional/critical problems only, when the model supports it — reserve for the single central architectural decision, never apply to every agent in a fleet |

## Generic role catalog (`release-<role>` in this plugin)

| Role | Default model | Default effort | Sandbox | Output budget |
|---|---|---|---|---:|
| `agents-md-builder` | Terra | medium | read-only (except `AGENTS.md`) | 1200 tok |
| `explorer-fast` | Luna | low | read-only | 700 tok |
| `explorer-deep` | Terra | medium | read-only | 1200 tok |
| `planner` | Frontier | high | read-only | 1500 tok |
| `worker-lite` | Luna | low | workspace-write | 700 tok |
| `worker` | Terra | medium | workspace-write | 1200 tok |
| `worker-complex` | Frontier | high | workspace-write | 1500 tok |
| `tester` | Luna | low | workspace-write | 700 tok |
| `reviewer` | Terra | high | read-only | 1200 tok |
| `security-reviewer` | Frontier | high | read-only | 1500 tok |
| `docs-researcher` | Luna | medium | read-only | 700 tok |
| `handoff-writer` | Luna | low | read-only | 500 tok |

The values baked into each `release-*.toml` are the **default floor** for
that role, not a hard ceiling — a spawning skill may request a higher
reasoning effort for a specific call when the complexity level demands it
(see `complexity-rubric.md`). Never lower a floor at spawn time.

## Complexity → fleet shape (condensed from the policy §8)

- **C0 (trivial):** no subagents. Do it inline at Luna/low.
- **C1 (simple):** 0–1 children. `worker-lite` (Luna/low) is the default;
  escalate to `worker` (Terra/medium) only for non-mechanical logic.
- **C2 (moderate):** up to 2 active subagents, 1 writer at a time.
  `explorer-fast` only if files aren't already known → `worker` (Terra/medium)
  → `tester` (Luna/low) only if test output would be noisy → `reviewer`
  (Terra/medium-high) only for public contracts or sizeable diffs. No
  separate `planner` when the plan fits in ≤5 steps.
- **C3 (complex):** up to 4 subagents/phase, concurrency ≤3 (read-only
  preferred). `explorer-deep` (Terra, up to 2 independent scopes) → `planner`
  (Frontier/high, never implements) → `worker` (Terra) → `tester` (Terra) if
  validation is complex → `reviewer` (Terra/high) → `security-reviewer`
  (Frontier/high) only with a real security trigger.
- **C4 (critical):** up to 6 subagents/phase, concurrency ≤4, almost all
  read-only. Frontier/xhigh reserved for the single central architectural
  decision only. Parallel writers require isolated worktrees with an explicit
  merge plan. No destructive change ships without described
  validation+rollback.

## Risk floors (override the computed score)

Auth, authorization, payments, crypto, secrets, privacy → minimum **C3**.
Destructive migration, production incident, data loss, cross-service
transaction → minimum **C4**. A purely mechanical change does not climb a
level just because the repo is large, as long as scope is provably bounded.
