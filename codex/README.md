# Codex compatibility layer

This directory builds the Codex-native release-sdk plugin without changing the
Claude Code package at the repository root.

## Build

```bash
python3 codex/build_plugin.py
```

The generated plugin lives at `plugins/release/`, and the repo marketplace at
`.agents/plugins/marketplace.json` points to it.

## Verify

```bash
python3 codex/test_compat.py
python3 /Users/lucas/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py plugins/release
```

## Subagents

After installing the plugin, run the `release:setup-codex` skill. It installs
only `release-*.toml` into `${CODEX_HOME:-$HOME/.codex}/agents/`. Start a new
Codex task afterward so the custom roles are loaded.

The installer never reads or writes Claude Code configuration or state.
