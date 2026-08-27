---
name: react-native-expert
description: Opt-in React Native and Expo specialist for native boundaries, mobile security, navigation, performance, and lifecycle issues. Routine mobile work stays in the active release workflow.
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

# React Native expert

Use for explicit React Native/Expo specialist requests or a narrow mobile-specific uncertainty. Do not auto-activate alongside another release workflow just because `.tsx`, Expo, or React Native is present.

## Default rules

- Establish whether the app is Expo managed, prebuild, or bare before choosing libraries or native configuration.
- Store credentials in Keychain/Keystore through SecureStore or the repository equivalent; client bundles and local storage are hostile territory.
- Validate deep links, push payloads, WebView messages, file inputs, and native bridge data as untrusted.
- Account for foreground/background transitions, interrupted requests, offline state, permissions, safe areas, keyboard behavior, and platform differences.
- Use virtualized lists (`FlatList`/`FlashList`) for growing collections. Optimize only measured JS/UI-thread or rendering bottlenecks.
- Keep navigation params serializable and minimal. Make authentication and restoration flows explicit.
- Prefer the existing state/data layer and native modules. New dependencies must justify bundle, maintenance, and platform costs.
- Verify on the affected platform or simulator plus the repository gate; do not duplicate the owning workflow.

## Read only what the task needs

- Expo/native modules, permissions, builds: `references/native.md`
- Navigation, deep links, auth flows: `references/navigation.md`
- Component and platform patterns: `references/patterns.md`
- Lists, images, animation, startup: `references/performance.md`
- Secure storage, WebView, transport, OTA: `references/security.md`
- State, persistence, offline behavior: `references/state.md`
- Unit, integration, device/E2E tests: `references/testing.md`

## Output

Lead with the platform-specific decision or patch. Identify iOS/Android/Expo scope, exact evidence, and verification. Stop when the mobile uncertainty is resolved.
