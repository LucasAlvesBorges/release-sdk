---
name: map-codebase
description: >
  Analyze the codebase with parallel mapper agents (tech, arch, quality, concerns) to produce
  structured analysis documents under `.release-planning/codebase/`. Stack-aware (django/react/fullstack).
  Use when: starting research on a phase, onboarding to a new repo, refreshing context after major refactors.
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

# /release:map-codebase — Parallel Codebase Mapper

Spawns parallel `release-codebase-mapper` agents — one per focus area — to produce structured
analysis documents under `.release-planning/codebase/`. Stack-aware: detects django, react, or
fullstack and adapts probes accordingly.

## Usage

```
/release:map-codebase                      # run all 4 focus areas in parallel
/release:map-codebase --focus tech         # only the tech-stack focus
/release:map-codebase --focus arch         # only the architecture focus
/release:map-codebase --focus quality      # only the code-quality focus
/release:map-codebase --focus concerns     # only the security/perf concerns focus
/release:map-codebase --refresh            # rewrite even if files already exist
```

## Pre-checks

Before spawning agents:

1. **`.release-planning/` exists.**
   ```bash
   test -d .release-planning || { echo "Run /release:init first"; exit 1; }
   ```

2. **Repo has source code.** Glob for code roots; if none → abort.
   ```bash
   has_source=$(find . -maxdepth 3 \( -name "*.py" -o -name "*.tsx" -o -name "*.ts" \) \
     -not -path "./node_modules/*" -not -path "./.venv/*" 2>/dev/null | head -1)
   [ -z "$has_source" ] && { echo "No source code detected; nothing to map"; exit 1; }
   ```

3. **Existing outputs without `--refresh`.** If a target file already exists and `--refresh`
   was not passed, skip that focus and report `(cached)` in the summary.

## Stack detection

The skill resolves stack in this order:

1. `.release-planning/PROJECT.md` — read `stack:` field from frontmatter
2. Fallback by globbing:
   - `manage.py` present → `django`
   - `package.json` + any `*.tsx` → `react`
   - Both present → `fullstack`
3. Pass detected stack to every spawned agent

## Execution

For each requested focus (default: all 4), spawn one `release-codebase-mapper` agent in
parallel. Each agent writes to a distinct output path so the spawns never race:

| Focus      | Output path                                       |
|------------|---------------------------------------------------|
| `tech`     | `.release-planning/codebase/STACK.md`             |
| `arch`     | `.release-planning/codebase/ARCHITECTURE.md`      |
| `quality`  | `.release-planning/codebase/QUALITY.md`           |
| `concerns` | `.release-planning/codebase/CONCERNS.md`          |

Spawn pattern (parallel — issue all Task tool calls in one assistant turn):

```
Task → release-codebase-mapper { focus: tech,     stack: <detected>, output_path: .release-planning/codebase/STACK.md }
Task → release-codebase-mapper { focus: arch,     stack: <detected>, output_path: .release-planning/codebase/ARCHITECTURE.md }
Task → release-codebase-mapper { focus: quality,  stack: <detected>, output_path: .release-planning/codebase/QUALITY.md }
Task → release-codebase-mapper { focus: concerns, stack: <detected>, output_path: .release-planning/codebase/CONCERNS.md }
```

`--focus X` collapses the spawn set to a single agent.

## Post-execution

After all agents return, the skill:

1. **One-line summary per output file** — read the file's frontmatter and print a digest line
   (focus, stack, top finding count).
2. **Commit** with all generated files staged:
   ```bash
   mkdir -p .release-planning/codebase
   git add .release-planning/codebase/
   git commit -m "chore(codebase): map {focus areas} into .release-planning/codebase/"
   ```
   Where `{focus areas}` is the comma-joined list of focuses actually written this run
   (e.g. `tech,arch,quality,concerns` or just `tech` for `--focus tech`).

If `--refresh` was not passed and every requested focus was cached, the skill prints
`(all outputs cached; pass --refresh to rewrite)` and skips the commit.

## Example output

```
/release:map-codebase

→ Pre-checks
   .release-planning/ ✓
   source detected: python + tsx ✓
   stack: fullstack (from PROJECT.md)

→ Spawning 4 mappers in parallel...
   [tech]     release-codebase-mapper → STACK.md
   [arch]     release-codebase-mapper → ARCHITECTURE.md
   [quality]  release-codebase-mapper → QUALITY.md
   [concerns] release-codebase-mapper → CONCERNS.md

→ All mappers returned (4/4 ok)
   STACK.md         — 5 languages, 12 frameworks, vitest+pytest
   ARCHITECTURE.md  — 4 django apps, 3 react features, REST API, Celery
   QUALITY.md       — ruff configured, tsc strict, 14 TODO, 2 long files (>500 LOC)
   CONCERNS.md      — auth: JWT cookie ✓, 3 N+1 risks, CORS open in dev

→ Commit
   chore(codebase): map tech,arch,quality,concerns into .release-planning/codebase/

→ Next: read .release-planning/codebase/*.md or run /release:discuss
```

## When to use

- **Starting a phase** — run before `/release:discuss` so the orchestrator has architecture
  context to reason against.
- **Onboarding** — first thing to run on an unfamiliar repo; produces a 4-doc snapshot.
- **Post-refactor refresh** — pass `--refresh` after a structural rewrite so subsequent
  research agents read the current shape.
- **Targeted re-map** — `--focus concerns` after a security audit, `--focus quality` after a
  lint/types overhaul.

## Output

```
.release-planning/codebase/
  STACK.md          # tech focus
  ARCHITECTURE.md   # arch focus
  QUALITY.md        # quality focus
  CONCERNS.md       # concerns focus
```

Each document is read-only relative to source — the mapper never edits code. Every claim in
the documents cites `file:line` so downstream agents (`release-feature-researcher`,
`release-pattern-mapper`, `release-feature-planner`) can jump to evidence.

---

## Stack dispatch

This skill spawns the merged `release-codebase-mapper` agent. Stack is inferred from
`.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`) and passed
to every spawned mapper. Each agent applies stack-specific probes and writes a single
document for its assigned focus.
