---
name: setup-codex
description: Install or verify release-sdk custom subagents for Codex Desktop without modifying any Claude Code files or configuration. Use after installing or updating the release plugin, or when a release-* subagent is unavailable.
---

# Setup release-sdk subagents for Codex

Resolve `RELEASE_PLUGIN_ROOT` as the directory two levels above this
`SKILL.md`, then run:

```bash
python3 "$RELEASE_PLUGIN_ROOT/bin/install-codex-agents.py" \
  --plugin-root "$RELEASE_PLUGIN_ROOT" \
  --install
```
Rules:

- The installer may write only `release-*.toml` files under
  `${CODEX_HOME:-$HOME/.codex}/agents/`.
- It must not read, edit, or remove anything under `~/.claude`, `.claude/`, or
  `.claude-plugin/`.
- It preserves unrelated Codex custom agents.
- After a successful install, tell the user to start a new Codex task. Custom
  agent definitions are loaded at task startup.

To verify without changing anything:

```bash
python3 "$RELEASE_PLUGIN_ROOT/bin/install-codex-agents.py" \
  --plugin-root "$RELEASE_PLUGIN_ROOT" \
  --check
```

## Project `.codex/config.toml`

After installing agents, check whether the current project (the one this
Codex task's `cwd` belongs to, not `RELEASE_PLUGIN_ROOT`) already has a
`.codex/config.toml`. If it does not, offer to copy
`$RELEASE_PLUGIN_ROOT/templates/codex-config.toml` to `<project-root>/.codex/config.toml`.

Rules:

- Never overwrite an existing `.codex/config.toml` — only create it when
  absent. If one already exists, just report that and leave it alone.
- This file sets the token-economy defaults (AGENTS.md gate mode, spawn
  defaults, per-role output budgets) that `release-*` custom agents and the
  `release-agents-md-guard.js` hook read. Without it, the guard defaults to
  `[agents_md].mode = "strict"`.
- Creating this file is a normal project write — it still goes through the
  AGENTS.md gate like any other write. If the project has no root
  `AGENTS.md` yet, that blocks first; resolve it before this step.
