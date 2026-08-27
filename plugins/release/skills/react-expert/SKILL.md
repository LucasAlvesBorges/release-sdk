---
name: react-expert
description: Opt-in React web specialist for difficult state, rendering, security, testing, and architecture decisions. Routine React work stays in the active release workflow.
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

# React expert

Use this skill only when explicitly requested or when a React-specific decision remains unresolved. Do not stack it automatically on top of `execute`, `quick`, `review`, or `loop` merely because the repository uses React.

## Default rules

- Keep server state in the established query/cache layer; keep ephemeral UI state local. Add global state only when ownership genuinely spans distant surfaces.
- Validate external data at boundaries. Model loading, error, empty, success, and stale states deliberately.
- Prefer small components organized around product behavior, not abstraction for its own sake. Reuse the repository's primitives before adding dependencies.
- Keep authentication material out of browser-readable storage when the backend can use secure `httpOnly` cookies. Treat rendered HTML, URLs, and third-party content as untrusted.
- Preserve semantic HTML, keyboard navigation, focus behavior, labels, contrast, reduced motion, and useful error announcements.
- Optimize measured bottlenecks. Avoid blanket memoization; stabilize identities only when it prevents demonstrated work.
- Test user-visible behavior and critical boundaries. Avoid tests coupled to component internals.
- Use the repository's focused checks first, then its cached/full gate. Do not duplicate the active release workflow.

## Read only what the task needs

- Component/API boundaries and composition: `references/patterns.md`
- Local, URL, server, and global state: `references/state.md`
- XSS, auth, validation, third-party content: `references/security.md`
- Rendering, bundles, lists, profiling: `references/performance.md`
- Testing Library, integration and browser tests: `references/testing.md`

## Output

Return the smallest decision, patch, or finding set that resolves the question. Reviews include severity and exact `file:line`; implementation reports the behavior protected and verification performed.
