# AGENTS.md

## Repo map

- `skills/`, `agents/`, `hooks/`, `bin/`, and `templates/` are the canonical release-sdk sources used by the Claude Code distribution.
- `codex/` contains the Codex compatibility builder, contracts, runtime adapters, and compatibility tests.
- `plugins/release/` is deterministic generated Codex plugin output; `.agents/plugins/marketplace.json` points to it.
- `.claude-plugin/` and `.claude-plugin-cache/` belong to Claude packaging/runtime state. Project behavior and release history are summarized in `README.md` and `CHANGELOG.md`.

## Install, build, lint, typecheck, and test

- Install from the supported marketplaces with the commands documented under `README.md` → `Instalação`; this repository has no separate dependency-install command or package manifest.
- Build the Codex distribution: `python3 codex/build_plugin.py`.
- Run the Codex compatibility suite: `python3 codex/test_compat.py`.
- Run all shell contract suites: `for test_file in bin/test-*.sh; do bash "$test_file" || exit; done`.
- No standalone lint or typecheck command is configured. Do not invent one; use the compatibility and contract suites as the repository gates.

## Focused tests

- Token tracker: `bash bin/test-token-worker.sh`.
- Edit guard: `bash bin/test-edit-guard.sh`.
- Gate, execution environment, and planning libraries: `bash bin/test-gate-lib.sh`, `bash bin/test-execenv-lib.sh`, or `bash bin/test-planning-sync-lib.sh`.
- Plan linter: `bash bin/test-plan-lint.sh`.
- Session merge engine: `bash bin/test-session-merge.sh`.
- Codex token collector only: `python3 -m unittest codex.test_compat.CodexCompatibilityTests.test_token_collector_advances_by_byte_offset`.
- Prefer the smallest relevant test first, then `python3 codex/test_compat.py`; run all shell suites when shared `bin/` behavior changes.

## Forbidden and low-priority directories

- Never edit `.git/`, `.claude-plugin-cache/`, user runtime state, token/event stores, or secrets.
- Do not hand-edit `plugins/release/`; change canonical root sources or `codex/` transforms, then regenerate with `python3 codex/build_plugin.py`.
- Treat generated artifacts, caches, `CHANGELOG.md`, translated README mirrors, and broad documentation rewrites as low priority unless the task explicitly requires them.
- Preserve unrelated and concurrent working-tree changes. Never clean, reset, or rewrite them.

## Architectural conventions

- Keep Claude Code and Codex distributions isolated: Codex generation may read canonical Claude sources but must not mutate Claude configuration or runtime state.
- Root source files are the source of truth; generated Codex output must remain deterministic and must pass the source-read-only digest checks in `codex/test_compat.py`.
- Runtime-specific path, agent-name, model, hook, and environment transformations belong in `codex/build_plugin.py` or `codex/runtime/`, not as drift inside generated files.
- Shell libraries under `bin/` are tested by scripts that source the real implementation. Preserve their stdout contracts, Bash/Zsh compatibility where covered, and fail-safe behavior.
- Keep changes narrow and compatibility-safe across both runtimes unless the request explicitly targets only one distribution.

## Security and dependency rules

- Never print, commit, or copy credentials, prompts, message content, transcript content, or token-tracker event data. Telemetry changes must remain metadata-only.
- Do not read or write `~/.claude` from Codex code, or Codex state from Claude hooks. Respect `${CODEX_HOME:-$HOME/.codex}` and plugin-scoped data boundaries already encoded in the builders.
- Add no dependency without an explicit requirement and a demonstrated need. Prefer the existing Python standard library, Node built-ins, and shell tooling.
- Preserve safe defaults: scoped writes, idempotent installers, non-destructive git behavior, atomic/locked mutations, and conservative handling of malformed external input.

## Scope expansion policy

- Work only in paths required by the request. Read adjacent code to understand contracts, but do not opportunistically refactor it.
- If completion requires a new dependency, public contract change, destructive migration, user-runtime mutation, or unrelated module edit, stop and request scope expansion with the exact path and reason.
- Generated-file updates produced by the documented builder are in scope only when their canonical source changed and the task requires a synchronized Codex distribution.

## Subagent usage policy

- C0/C1 work stays inline. Use subagents only for concrete independent work where delegation is explicitly allowed by the active workflow.
- For C2, use at most two active subagents and one writer at a time. Higher-risk work follows `codex/contracts/routing-policy.md`; keep write ownership disjoint.
- Every subagent must receive explicit allowed paths, forbidden paths, acceptance checks, and notice that concurrent edits must be preserved.
- Subagents return compact `SubagentResultV1`; the parent owns integration, verification, and completion.

## Completion criteria

- The requested behavior exists in canonical sources and, when applicable, regenerated Codex output matches it.
- The narrowest relevant test passes; broader compatibility/contract suites run in proportion to the affected shared surface.
- No unrelated files, runtime state, secrets, or concurrent user edits were changed.
- The final report names changed files, commands run and results, plus any residual risk or unrun gate.

## Maximum response format

- Keep the final response to at most eight concise bullets or equivalent short lines: outcome first, changed files, verification, and residual risk/next action.
- Do not paste raw logs, stack traces, exhaustive diffs, secrets, or transcript contents. Link files and summarize only decisive evidence.
- When acting as a release-sdk Codex subagent, return only valid compact `SubagentResultV1` JSON as required by `codex/contracts/result-schema.json`.
