---
name: react-expert
description: Opt-in React web specialist for difficult state, rendering, security, testing, and architecture decisions. Routine React work stays in the active release workflow.
---

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
