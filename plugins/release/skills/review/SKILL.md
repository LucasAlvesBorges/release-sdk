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

### Step 0 — AGENTS.md gate

Before any Write/Edit/apply_patch, the target project MUST have a root
`AGENTS.md`. `release-agents-md-guard.js` enforces this at the hook level and
will block the write — do not try to route around it. If it blocks:
`.codex/config.toml`'s `[agents_md] mode` is `strict` (default: stop, tell the
user `AGENTS_MD_REQUIRED`) or `bootstrap` (spawn `release-agents-md-builder`
read-only, let it draft and save `AGENTS.md`, then stop and tell the user to
re-run the original task). Never fabricate the file yourself outside that
role, and never inline the full `AGENTS.md` content into a subagent prompt —
let Codex discover it normally from `cwd`.

### Step 1 — score complexity, then decide whether to spawn anything

Self-score the task C0–C4 using `complexity-rubric.md` before touching
anything else, apply the risk floors, then use `routing-policy.md`'s fleet
table for the level. Default is **no subagents** (`spawn = false`). Spawn one
only when ALL of:

```text
bounded_subtask
AND explicit_success_criteria
AND (independent OR noisy_output OR specialist_required OR broad_read_avoided)
AND estimated_context_avoided > spawn_overhead
```

Never spawn for C0. Never spawn just to "use multiagent." Never spawn a
subtask that immediately depends on another subtask's result and can't run in
parallel. Group reads over the same files instead of one agent per file.

**Read vs write:** read-only agents may run in parallel freely. Writers never
share a file set — one writer per path set, sequential when there's a
dependency, parallel only with disjoint scopes or isolated worktrees (declare
`allowed_paths`/`forbidden_paths` up front either way).

### Invoking a subagent

```text
Role: {role}
Single objective: {subtask_objective}

Allowed scope:
{allowed_paths}

Do not access:
{forbidden_paths}

Minimal context:
{task_specific_context}

Completion criteria:
{success_criteria}

Rules:
- Follow the AGENTS.md chain applicable to cwd.
- Do not expand scope on your own — return needs_scope_expansion instead.
- Do not restate the prompt back.
- Do not return full logs.
- Stop as soon as the criteria are met.
- Return only JSON matching SubagentResultV1.
```

Pass only this delta — never the full parent transcript, never the full
`AGENTS.md`, never whole files already in the workspace, never full logs.

### Handoff

Only when the task continues in another thread/session — see
`handoff-template.md` (60 lines / ~500 tokens max). Not a substitute for the
normal end-of-task summary.

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
- If the exact named agent is not available, prefer this plugin's own generic
  roster before Codex's bare defaults: `release-explorer-fast` /
  `release-explorer-deep` for read-only research, `release-worker` /
  `release-worker-lite` / `release-worker-complex` for implementation,
  `release-reviewer` / `release-security-reviewer` for judgment-heavy review,
  `release-planner` for orchestration. Only fall back to Codex's bare
  `explorer` / `worker` / `default` if none of those are installed either —
  and in that case give the fallback agent the absolute path to
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
  Fable, Opus, Sonnet, or Haiku, and ignore `CLAUDE_EFFORT`. Those do not
  apply in Codex.
- Every `release-<name>` custom agent already carries its own
  `model`/`reasoning_effort` per `routing-policy.md` — spawn it as-is. Only
  request a higher reasoning effort than the agent's default when the C0–C4
  fleet table for this task's level calls for it (`complexity-rubric.md`);
  never request a lower one.
- Preserve maker-versus-checker independence by using distinct agent turns —
  a checker runs as its own spawn, never as a self-review by the maker.

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
