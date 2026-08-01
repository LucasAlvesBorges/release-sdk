---
name: review
description: >
  Context-aware adversarial code review. Analyzes file paths to split .py files to code-reviewer
  and .tsx/.ts files to code-reviewer. Produces a unified REVIEW.md with sections per stack.
  Use when: reviewing PR diff, auditing recently-modified files, pre-merge quality gate.
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

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation.

---

# /release:review — Adversarial Code Review (Django + React)

Routes files to the correct reviewer based on extension. Produces unified REVIEW.md.

## Usage

```
/release:review                              # review all files changed vs main
/release:review backend/apps/financeiro/     # Django-only path
/release:review src/features/Invoices/       # React-only path
/release:review --diff main..HEAD            # git diff
/release:review --depth=deep                 # deep review both stacks
/release:review --fix                        # apply fixes after review
```

> Previously: `--gsd-context` flag. Removed in v0.4.0 — use `/release:import` once to convert GSD planning files; all skills then assume release-sdk native format.

## Routing logic

0. Load LOCK constraints: read `.release-planning/RELEASE-LOCKS.md` if exists (GSD import), else `.release-planning/PROJECT.md`. Pass active LOCKs to each reviewer as forbidden-pattern context.
1. Resolve files to review (from args, git diff, or changed since last commit).
2. Split by extension:
   - `.py` → `django_files` → spawn `release-code-reviewer`
   - `.tsx`, `.ts`, `.jsx`, `.js` → `react_files` → spawn `release-code-reviewer`
   - Other → skip (lock files, migrations, .md)
3. Run reviewers in parallel if both sets present.
4. Merge findings into single REVIEW.md with `## Django Findings` and `## React Findings` sections.
5. Report combined totals: `{N} Django blockers, {M} React blockers`.

## Fullstack integration check

When BOTH Django and React files are in scope (e.g., reviewing a feature that adds API + UI):
1. Check API contract alignment: does the Django serializer field set match the Zod schema in React?
2. Check auth consistency: Django uses httpOnly cookie? React doesn't read token from localStorage?
3. Report mismatches as `## Integration Issues` section in REVIEW.md.

## Output

```
REVIEW.md (or path specified by --review-path):
  Frontmatter: totals per stack
  ## Django Findings
    ### Blockers (CR-XX)
    ### Warnings (WR-XX)
  ## React Findings
    ### Blockers (CR-XX)
    ### Warnings (WR-XX)
  ## Integration Issues (if fullstack)
```

## Example

```
/release:review --diff main..HEAD

→ Changed files:
    backend/apps/financeiro/serializers.py  → Django
    backend/apps/financeiro/views.py        → Django
    src/features/Invoices/InvoiceList.tsx   → React
    src/hooks/useInvoices.ts                → React

→ Spawning release-code-reviewer (2 files, depth=standard)...
→ Spawning release-code-reviewer (2 files, depth=standard)... [parallel]

→ Django findings: 1 BLOCKER (mass assignment in serializer), 2 WARNINGS
→ React findings: 0 BLOCKERS, 3 WARNINGS (missing memo, missing error state, key={index})

→ Integration check:
  InvoiceSerializer.fields: [id, amount, status, created_at]
  InvoiceSchema (Zod): z.object({ id, amount, status, createdAt }) ← camelCase mismatch
  ⚠️ INTEGRATION: Django serializer uses snake_case, React schema uses camelCase.
     Ensure API client transforms keys (axios + camelcase-keys) or align naming.

→ REVIEW.md written at .release-planning/review/REVIEW.md
   Total: 1 BLOCKER, 5 WARNINGS, 1 INTEGRATION ISSUE
→ Run /release:review --fix to apply auto-fixes.
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
