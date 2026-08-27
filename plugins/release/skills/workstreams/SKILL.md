---
name: workstreams
description: Deprecated compatibility alias for parallel work. Routes users to worktree-native release:session commands.
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

# `/release:workstreams` (deprecated)

Do not create or mutate legacy `ws-*` branches, active-workstream pointers, or `.release-planning/workstreams/` state.

- `list`, `status`, `progress` → `/release:session list`
- `create <name>`, `resume <name>`, `switch <name>` → `/release:session start <name>` (or open the existing session path)
- `complete <name>` → `/release:session finish <name>`
- `remove <name>` → `/release:session abort <name>` after destructive confirmation, or `cleanup` when already merged

Explain the mapping once and execute through `release:session`. Existing legacy files remain read-only for migration context.
