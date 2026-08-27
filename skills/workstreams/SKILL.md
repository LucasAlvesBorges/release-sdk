---
name: workstreams
description: Deprecated compatibility alias for parallel work. Routes users to worktree-native release:session commands.
---

# `/release:workstreams` (deprecated)

Do not create or mutate legacy `ws-*` branches, active-workstream pointers, or `.release-planning/workstreams/` state.

- `list`, `status`, `progress` → `/release:session list`
- `create <name>`, `resume <name>`, `switch <name>` → `/release:session start <name>` (or open the existing session path)
- `complete <name>` → `/release:session finish <name>`
- `remove <name>` → `/release:session abort <name>` after destructive confirmation, or `cleanup` when already merged

Explain the mapping once and execute through `release:session`. Existing legacy files remain read-only for migration context.
