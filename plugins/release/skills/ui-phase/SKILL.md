---
name: ui-phase
description: Adaptive frontend design contract. Reuses established design-system patterns inline and delegates research/checking only for novel or high-risk UI.
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

# `/release:ui-phase`

Produce `{phase}-UI-SPEC.md` for a frontend/fullstack phase. Refuse backend-only phases.

## Usage

```text
/release:ui-phase [phase]
/release:ui-phase [phase] --research
/release:ui-phase [phase] --strict
/release:ui-phase [phase] --revise
```

## Flow

1. Resolve the phase and read SPEC/CONTEXT, locks, any prior UI-SPEC, relevant routes/components, and dependency/style manifests. Detect the existing design system, routing, forms, client/server state, and test conventions from those files only.
2. Reuse locked and incumbent patterns. Ask at most one batch of three questions only for choices that change interaction, content hierarchy, responsive behavior, or accessibility.
3. For C1/C2 work within an established system, write UI-SPEC inline. Include only affected routes/components; data contracts; loading/empty/error/success states; key interaction and validation; keyboard/focus/semantic behavior; responsive behavior; state ownership; and targeted tests.
4. Spawn `release-react-ui-researcher` only with `--research`, or for C3/C4 novel surfaces with unresolved design-system/interaction decisions. Pass paths and open decisions, not all planning documents.
5. Run deterministic checks inline: every affected async surface has states, interactive control has semantics/focus behavior, external data has a typed boundary, and route/state ownership is explicit.
6. Spawn `release-react-ui-checker` only with `--strict` or on C3/C4 after the inline checks. It audits triggered dimensions, not a universal matrix. Fix blocking omissions once and stop.

The planner consumes UI-SPEC directly. Do not create research/check artifacts for ordinary forms, tables, modals, or pages already covered by repository patterns.
