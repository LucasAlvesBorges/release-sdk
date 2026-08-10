---
name: init
description: >
  Initialize a new project with release-sdk. Asks stack questions (Django / React TSX / fullstack),
  captures vision + architecture decisions, locks LOCK-01..LOCK-12 for full-stack projects.
  Produces PROJECT.md, ROADMAP.md, STATE.md, REQUIREMENTS.md.
  Use when: starting a new project from scratch.
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

# /release:init — Full-Stack Project Initialization

Captures project vision and architecture. Locks decisions as LOCK-XX in PROJECT.md.

> Importing from an existing GSD project? Use `/release:import` first to mass-port `.release-planning/` artifacts, then run `/release:init` to fill any remaining gaps.

## Usage

```
/release:init                        # interactive — asks all questions
/release:init --backend-only         # Django-only project (same as /django:init)
/release:init --frontend-only        # React-only project
```

> Previously: `--gsd-context` flag. Removed in v0.4.0 — use `/release:import` once to convert GSD planning files; all skills then assume release-sdk native format.

---

## Questions asked

#### 1. Project identity
- Project name, domain, target users
- Team size (solo, small team)

#### 2. Stack selection
- Backend: Django + DRF? (versions, Python version)
- Frontend: React + TSX? (Vite or Next.js, React Router version)
- Database: PostgreSQL? Redis?

#### 3. Backend architecture (if Django)
- Multi-tenancy? (empresa_id isolation, django-rls)
- Auth model: JWT httpOnly cookie / session / token header
- Celery + Redis? Worker strategy?
- API style: DRF ViewSet / APIView / mixed
- OpenAPI docs: drf-spectacular?

#### 4. Frontend architecture (if React)
- State management: Zustand + TanStack Query (default)
- Routing: React Router v6 / TanStack Router / Next.js App Router
- Form library: react-hook-form + zod (default)
- Component library: shadcn/ui / MUI / custom / none
- Test framework: Vitest + RTL (default)

#### 5. Full-stack integration (if both)
- API convention: REST / GraphQL
- Response format: snake_case (Django) + camelCase transform (Axios interceptor)?
- Auth cookie strategy: same-domain or CORS?
- CSRF strategy: Cookie-to-header (csrftoken → X-CSRFToken)

#### 6. Forbidden patterns (project-level LOCK)
- Backend: `fields = '__all__'`? Direct `.delay()`?
- Frontend: `localStorage` for auth tokens? `any` TypeScript?
- Both: Unreviewed raw SQL? Hardcoded secrets?

## Locks produced

| LOCK | Domain | Example |
|---|---|---|
| LOCK-01 | Backend stack | Django 5.2 + DRF 3.16 + Python 3.12 |
| LOCK-02 | Multi-tenancy | empresa_id via django-rls, TenantModel required |
| LOCK-03 | Auth model | JWT httpOnly cookie + X-CSRFToken header |
| LOCK-04 | Celery | .delay_on_commit() mandatory; .delay() = BLOCKER |
| LOCK-05 | ORM | select_related/prefetch required; N+1 = BLOCKER |
| LOCK-06 | Mass assignment | fields = '__all__' forbidden = BLOCKER |
| LOCK-07 | Frontend stack | React 18 + Vite + TypeScript strict |
| LOCK-08 | State management | Zustand (client) + TanStack Query (server) |
| LOCK-09 | Frontend auth | httpOnly cookie only; localStorage tokens = BLOCKER |
| LOCK-10 | Type safety | no `any`; Zod for API responses = BLOCKER if missing |
| LOCK-11 | Tests | Vitest + RTL; MSW for API mocks |
| LOCK-12 | API contract | snake_case backend, camelCase frontend via interceptor |

## Output

```
.release-planning/
  PROJECT.md       # vision + LOCK-01..LOCK-12
  ROADMAP.md       # empty phases template
  REQUIREMENTS.md  # REQ-XX
  STATE.md         # cursor

AGENTS.md          # root — delimited release-sdk block injected (created if missing)
```

## AGENTS.md injection (always last step)

After `.release-planning/` writes succeed, inject a delimited block into the repo-root
`AGENTS.md` so every future Codex session knows release-sdk is installed and where
the artifacts live.

Behavior:

1. If `AGENTS.md` does NOT exist → create with a minimal header + the release-sdk block.
2. If `AGENTS.md` exists AND contains `<!-- release-sdk:start -->` → replace only the
   delimited block; preserve everything else byte-for-byte.
3. If `AGENTS.md` exists AND no delimited block → append the block at the end (two blank
   lines before it).

Block content (rendered with project name + stack from PROJECT.md):

```markdown
<!-- release-sdk:start -->
## release-sdk framework

This project uses **release-sdk** ({stack}). Planning artifacts live at
`.release-planning/`.

- LOCK-XX rules: `.release-planning/RELEASE-LOCKS.md`
- Active phase cursor: `.release-planning/STATE.md`
- Phase artifacts: `.release-planning/phases/{NN}-{slug}/`

Entry point: **`/release:auto <freeform intent>`** — routes to the right `/release:*`
skill (status / spec / discuss / plan / execute / review / verify / ui-phase / ai-phase /
secure-phase / debug / fast / quick / ship / import / workstreams / checklist).

GSD coexistence: if `.planning/` is also present, it belongs to upstream GSD and is
read-only from release-sdk's side. `/release:import` is the bridge.
<!-- release-sdk:end -->
```

Idempotent. Re-running `/release:init` updates the block in place without disturbing the
rest of `AGENTS.md`.

## Example

```
/release:init

→ What is the project? "Invoice management SaaS for logistics companies"
→ Backend: Django 5.2 + DRF
→ Frontend: React 18 + Vite + TSX
→ Multi-tenant: YES (empresa_id)
→ Auth: JWT httpOnly cookie
→ State: Zustand + TanStack Query
→ Forbidden: fields='__all__', localStorage tokens, any type

→ Writing PROJECT.md (LOCK-01 to LOCK-12)...
→ Writing ROADMAP.md (template)...
→ Writing STATE.md...
→ Writing REQUIREMENTS.md...
→ Injecting release-sdk block into AGENTS.md (created — no existing file)...

→ Done. Next: /release:roadmap  (decompose milestone into phases)
```
