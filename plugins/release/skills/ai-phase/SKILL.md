---
name: ai-phase
description: Adaptive AI/LLM design contract. Handles ordinary provider integrations inline and delegates comparison/research only when the decision warrants it.
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

# `/release:ai-phase`

Produce `{phase}-AI-SPEC.md` before planning an AI feature, with cost proportional to uncertainty.

## Usage

```text
/release:ai-phase [phase]
/release:ai-phase [phase] --provider openai
/release:ai-phase [phase] --compare
/release:ai-phase [phase] --research
/release:ai-phase [phase] --revise
```

## Flow

1. Resolve the phase and read its SPEC/CONTEXT plus PROJECT, locks, and any existing AI-SPEC. Probe only the likely integration paths and dependency manifests for incumbent patterns.
2. Reuse locked decisions. If a planning-blocking choice remains, ask one batch of at most three decision-changing questions (provider/hosting, latency/cost/data constraints, output/evaluation). Do not interview for details inferable from the repository.
3. Score complexity C0-C4. For C1/C2 and an established provider/SDK, write the contract inline. An explicit `--provider` is a decision and therefore skips framework selection.
4. Spawn `release-framework-selector` only with `--compare`, or when a C3/C4 design has a genuine unresolved framework/orchestration choice. Pass constraints and use case, not full source documents.
5. Spawn `release-ai-researcher` only with `--research`, for an unknown/niche provider integration, or a C3/C4 design whose repository integration/evaluation risk cannot be resolved locally. It appends delta findings; it does not rewrite settled decisions.
6. Write a compact AI-SPEC containing:
   - goal, provider/model/SDK and why;
   - request, prompt/tool and structured-output contracts;
   - sync/async/streaming boundary, timeout/retry/idempotency;
   - data handling, injection/authorization and cost guardrails;
   - evaluation cases, pass metrics and deterministic mocks;
   - observability (latency, tokens/cost, errors) and rollout/fallback;
   - unresolved blockers only.

Prefer the existing direct SDK for simple calls. Add orchestration frameworks only when durable graph/state, complex retrieval, or multi-agent behavior demonstrates the need. Never expose provider secrets to the client. Planning may proceed when the contract has no unresolved implementation-changing decision; exhaustive research is not a prerequisite.
