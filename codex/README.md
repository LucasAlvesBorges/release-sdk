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

## Token-economy policy

This edition implements the release-sdk Codex token-economy policy end to
end:

- **AGENTS.md gate.** `hooks/release-agents-md-guard.js` blocks
  Edit/Write/apply_patch (`exit 2`) in any target project whose root lacks an
  `AGENTS.md`, except the write that creates the file itself. Mode (`strict`
  default, or `bootstrap`) comes from that project's `.codex/config.toml`.
- **Per-agent model routing.** Every generated `release-*.toml` carries a
  pinned `model` / `reasoning_effort` / `output_token_budget` / `role_class`
  — see `contracts/routing-policy.md` for the tier table and
  `build_plugin.py`'s `AGENT_MODEL_OVERRIDES` for the per-agent assignment.
- **12 generic Codex-only roles** (`release-explorer-fast`,
  `release-worker`, `release-planner`, `release-security-reviewer`, …) built
  from `contracts/roles/*.md`, for ad-hoc work that doesn't map to one of the
  specialized `release-*` agents.
- **Structured output.** Every agent must return `SubagentResultV1`
  (`contracts/result-schema.json`) instead of a raw transcript — no logs, no
  secrets, 8-line summaries.
- **Complexity-aware spawning.** `contracts/complexity-rubric.md` (C0–C4
  self-scoring) and `contracts/routing-policy.md` (fleet shape per level) are
  referenced from every generated `SKILL.md`'s step-0/step-1 preamble.
- **`.codex/config.toml` template**, shipped at
  `templates/codex-config.toml`, holding the policy's routing/budget/context
  defaults. `release:setup-codex` offers to install it into a target project
  that doesn't already have one — it never overwrites an existing one.
