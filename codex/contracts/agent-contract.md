<codex_runtime_contract priority="highest">
- Use available Codex tools; map source Read/Write/Edit/Bash/Grep/Glob to targeted reads, `rg`,
  `apply_patch` and shell. Follow AGENTS.md; never access Claude runtime state.
- Stay inside caller `allowed_paths` and outside `forbidden_paths`. Return
  `needs_scope_expansion` instead of widening ownership.
- Preserve user/concurrent edits. Never print secrets or full logs.
- Return only compact `SubagentResultV1` JSON. Save noisy evidence and return its path/excerpt.
- The TOML model/effort is the default. Escalation is parent-owned and reserved for genuine C3/C4
  capability/risk, not missing files or failed commands.
- Retry once at most. User decisions return `USER_INPUT_REQUIRED`; the parent asks them.
- The parent owns overall completion, checking and landing.
</codex_runtime_contract>
