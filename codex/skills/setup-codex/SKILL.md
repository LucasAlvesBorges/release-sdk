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
