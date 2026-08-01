---
name: fast
description: >
  Execute a trivial task inline — no subagents, no phase machinery, no state tracking.
  For one-shot edits where the work is faster than the overhead of planning it.
  Atomic commit at the end. Survives no context, but the task is small enough that it
  doesn't need to.
  Use when: rename a symbol, fix a typo, tweak a log line, change a single config value,
  or any task with a single-file feel and < 30 LOC of change.
---

## Codex runtime contract (generated; overrides incompatible source directives)

This skill is the Codex edition of release-sdk. The source workflow below is
kept for behavioral parity, but this contract has precedence whenever the
source mentions Claude Code primitives.

### Isolation

- Never create, edit, delete, or inspect runtime state under `~/.claude`,
  `.claude/`, `.claude-plugin/`, `.claude-plugin-cache/`, or `CLAUDE.md`.
- Release planning artifacts remain under `.release-planning/`. Durable Codex
  project guidance belongs in `AGENTS.md` only when the workflow explicitly
  needs to add it.
- Resolve `RELEASE_PLUGIN_ROOT` as the directory two levels above this
  `SKILL.md`. Resolve `RELEASE_PLUGIN_DATA` from `PLUGIN_DATA` when supplied;
  otherwise use `${CODEX_HOME:-$HOME/.codex}/release-sdk`.

### Tools

- Treat `Read`, `Write`, `Edit`, `Bash`, `Grep`, and `Glob` in the source as
  conceptual operations. Use the Codex tools currently available: targeted
  file reads, `apply_patch` for edits, `exec_command` for commands, and `rg`
  or `rg --files` for search.
- A source reference to `AskUserQuestion` means: use the structured user-input
  tool when it is available to the parent agent. A subagent must instead
  return `USER_INPUT_REQUIRED` with the exact question and 2-3 choices so the
  parent can ask it. If no structured input tool is available, ask one concise
  question in the parent task.
- A source reference to a `Skill` tool means to run the installed
  `release:<skill-name>` skill. If there is no callable skill tool, delegate to
  a `default` subagent with a task that explicitly names that installed skill,
  pass the original arguments unchanged, wait for it, and surface its result.

### Subagents

- Source agent names `release:<name>` are mapped in this generated edition to
  Codex custom agents named `release-<name>`.
- Spawn agents only through Codex collaboration tools. Do not emulate a
  subagent with a shell command and do not use a nonexistent `Task` or `Agent`
  tool.
- Prefer the named `release-<name>` agent when it is available. These agents
  are installed by the `release:setup-codex` skill and become available in a
  new task.
- If a named agent is not available, use `explorer` for read-only codebase
  research, `worker` for implementation or file-producing work, and `default`
  for orchestration or judgment. Give the fallback agent the absolute path to
  `agents/release-<name>.toml` under `RELEASE_PLUGIN_ROOT` and require it to
  read and follow the `developer_instructions` before working.
- For write tasks, assign explicit file ownership and tell every worker that
  other agents may be editing the repository; it must preserve and integrate
  others' changes. Parallelize only independent scopes and respect the current
  session's concurrency limit.
- Wait for required agents, collect their final results, and keep completion
  judgment in the parent/orchestrator. A worker never declares the overall
  workflow complete.

### Models and reasoning

- Ignore source instructions that pin or derive Claude model tiers such as
  Fable, Opus, Sonnet, or Haiku. Do not pass an explicit model or reasoning
  effort unless the user requested one. Codex custom agents inherit the
  parent/session settings by default.
- Preserve maker-versus-checker independence by using distinct agent turns,
  not by assuming a particular vendor model hierarchy.

### Invocation vocabulary

- `/release:<name>` in the source is a workflow label retained for
  compatibility. In Codex Desktop the user selects the `release` plugin or its
  `release:<name>` skill from the composer.
- `claude` CLI launch examples map to `codex` in this generated edition.

# /release:fast — Trivial Task, Inline

No planning. No agents. No state. Just do it and commit.

## Usage

```
/release:fast rename `EmpresaSerializer.user_email` to `owner_email`
/release:fast bump Django version in requirements.txt to 5.2.1
/release:fast remove debug print in views/invoice.py
/release:fast add CORS_ALLOWED_ORIGINS = [...] to settings.py
```

The arg is the task description. Treat it as a direct instruction.

## When to use this vs other skills

- **`/release:fast`** — single symbol or single file, no design decision needed
- **`/release:quick`** — multi-file but still bounded; needs atomic commit + light state
- **`/release:spec` → `/release:plan` → `/release:execute`** — anything with design ambiguity

If unsure, default to `/release:quick` (safer envelope).

## Execution flow

### Step 1 — Pre-checks

1. Worktree must be clean (`git status --short` empty). If dirty → abort with:
   > "Worktree has uncommitted changes. Stash or commit first."
2. Task scope check: if the request implies > 5 files OR > 30 LOC OR adds a new module,
   abort with:
   > "Task scope exceeds /release:fast envelope. Use /release:quick or /release:spec."

### Step 2 — Do the work

Use `Read` + `Edit` + `Grep` directly. No subagents. No `.release-planning/` writes.

### Step 3 — Validate

Run the obvious validation for the stack:
- Python edit → `python -m py_compile <file>` (or `ruff check <file>` if available)
- TypeScript edit → `tsc --noEmit <file>` is too heavy; skip (delegate to CI)
- JSON/YAML edit → parse to confirm valid

If validation fails → revert the edit, report failure to user, do NOT commit.

### Step 4 — Atomic commit

```bash
git add <touched files>
git commit -m "{type}({scope}): {one-line summary}

{optional body — only if the why isn't obvious}

Co-Authored-By: Codex <noreply@openai.com>"
```

Commit type by intent:
- `fix:` — bug fix
- `chore:` — config / deps / lint
- `refactor:` — rename, restructure
- `docs:` — README / comments only

NEVER push automatically. The user pushes when ready.

## Constraints

- **No subagents.** This skill is intentionally synchronous and small.
- **No state writes.** `.release-planning/STATE.md` is untouched.
- **Clean worktree required.** No mixing with uncommitted work.
- **Validate before commit.** No commit on broken syntax.
- **No push.** User owns the push decision.

## Example

```
/release:fast remove unused `import json` from apps/invoice/views.py

→ Worktree clean ✓
→ Scope: 1 file, 1 line removal ✓
→ Editing apps/invoice/views.py…
→ py_compile passes
→ Committing: chore(invoice): drop unused json import
```

---

_Inline. No overhead. Built for tasks that cost more to plan than to do._
