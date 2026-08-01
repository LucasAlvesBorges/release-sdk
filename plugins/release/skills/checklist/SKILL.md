---
name: checklist
description: >
  Context-aware author checklist verification. Runs Q1-Q7 (Django) and/or RC1-RC7 (React)
  based on phase type. Grep-based PASS/FAIL/N-A per question. Produces CHECKLIST.md.
  Use when: after execute, before /release:verify, or as standalone quality gate.
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

# /release:checklist — Author Checklist Verification (Q1-Q7 + RC1-RC7)

Runs the correct checklist based on files in scope.

## Usage

```
/release:checklist 01                # auto-detect, run both if fullstack
/release:checklist 01 --backend      # Q1-Q7 only
/release:checklist 01 --frontend     # RC1-RC7 only
/release:checklist src/features/X/   # check specific React feature
/release:checklist backend/apps/X/   # check specific Django app
```

## Django Author Checklist (Q1-Q7)

Spawns `release-django-checklist-verifier` for:
- Q1: `select_related` on FK traversal
- Q2: `prefetch_related` on reverse-FK / M2M
- Q3: `.annotate(count=Count(...))` instead of Python-side count
- Q4: `Subquery`/`OuterRef` instead of N sub-queries
- Q5: `F()` or `select_for_update()` for numeric mutations
- Q6: `.delay_on_commit()` — never `.delay()` in production code
- Q7: `.iterator(chunk_size=...)` for large querysets

## React Author Checklist (RC1-RC7)

Spawns `release-test-auditor` + grep-based checks:
- RC1: `React.memo`, `useMemo`, `useCallback` where needed
- RC2: `isLoading`/`isError` guards in data-fetching components
- RC3: No `any` types; Zod schemas for API responses
- RC4: `aria-label` on interactive elements; semantic HTML
- RC5: Server state in TanStack Query, client state in Zustand
- RC6: No `localStorage`/`sessionStorage` for auth tokens
- RC7: Test files present and non-trivial (assert interactions)

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-CHECKLIST.md

---
phase: {NN}
backend_score: {N}/7
frontend_score: {N}/7
---

## Django Q1-Q7
| Q | Description | Verdict | Evidence |
|---|---|---|---|
| Q1 | select_related | ✅ PASS | views.py:34 |
| Q6 | delay_on_commit | ❌ FAIL | tasks.py:12 uses .delay() |

## React RC1-RC7
| RC | Description | Verdict | Evidence |
|----|---|---|---|
| RC1 | Render optimization | ✅ PASS | React.memo on InvoiceList |
| RC6 | Auth token storage | ✅ PASS | no localStorage.setItem(token) |
| RC7 | Test coverage | ⚠️ PARTIAL | InvoiceForm.tsx has no test file |

## Failures (require fix before merge)
Q6: .delay() used in tasks.py:12 — change to .delay_on_commit()
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
