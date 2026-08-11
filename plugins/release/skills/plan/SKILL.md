---
name: plan
description: >
  Context-aware phase planner. Reads ROADMAP.md + CONTEXT.md to detect if phase is backend (Django),
  frontend (React), or fullstack — then routes to the appropriate planner pipeline.
  Django → feature-planner. React → feature-planner. Fullstack → both in parallel.
  Use when: phase has been discussed (CONTEXT.md exists), ready to plan.
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

# /release:plan — Context-Aware Phase Planner

Detects phase type (backend / frontend / fullstack) and routes to the correct planning pipeline.

## Usage

```
/release:plan 01                     # auto-detect and plan phase 01
/release:plan 01 --backend           # force Django pipeline
/release:plan 01 --frontend          # force React pipeline
/release:plan 01 --fullstack         # worktree-isolated parallel (backend + frontend)
/release:plan 01 --gaps              # plan gap-closure after /release:verify
/release:plan 01 --revise            # revise after plan-checker BLOCK
/release:plan 01 --no-worktree       # disable worktree isolation (sequential, main tree)
```

> Previously: `--gsd-context` flag. Removed in v0.4.0 — use `/release:import` once to convert GSD planning files; all skills then assume release-sdk native format.

## Context detection logic

1. Read `.release-planning/ROADMAP.md` → extract phase goal text and tags.
2. If `.release-planning/phases/{NN}-{slug}/{NN}-CONTEXT.md` exists → read D-XX decisions for stack signals.
3. Classify:

| Signal keywords | Classification |
|---|---|
| component, UI, React, page, form, screen, modal, table, dashboard (frontend) | `frontend` |
| API, endpoint, model, serializer, migration, Celery, task, queryset, Django (backend) | `backend` |
| Both sets present | `fullstack` |
| Neither clear | ask user (AskUserQuestion) |

4. Apply `--backend` / `--frontend` / `--fullstack` flags to override.

## Workflow by classification

### backend
1. Load LOCK context: read `.release-planning/RELEASE-LOCKS.md` if exists (GSD import), else `.release-planning/PROJECT.md`. Both may coexist — RELEASE-LOCKS.md takes precedence for LOCK-XX values.
2. Load ROADMAP phase entry, CONTEXT.md.
3. Spawn `release-feature-researcher` → `{NN}-RESEARCH.md`.
4. Spawn `release-pattern-mapper` → `{NN}-PATTERNS.md`.
5. Spawn `release-feature-planner` → `{NN}-PLAN.md`.
6. Spawn `release-plan-checker` (`Agent({subagent_type: "release-plan-checker", stack: "django", phase: "{NN}", slug: "{slug}", phase_dir: ".release-planning/phases/{NN}-{slug}"})`) → `{NN}-PLAN-CHECK.md` (PASS/WARN/BLOCK).
7. If BLOCK: report blockers, suggest `--revise`. If WARN: log to PLAN-CHECK.md but proceed. If PASS: continue.
8. Commit artifacts.

### frontend
1. Load LOCK context: read `.release-planning/RELEASE-LOCKS.md` if exists, else `.release-planning/PROJECT.md`.
2. Load ROADMAP phase entry, CONTEXT.md.
2. Spawn `release-feature-researcher` → `{NN}-RESEARCH.md`.
3. Spawn `release-pattern-mapper` → `{NN}-PATTERNS.md`.
4. Spawn `release-feature-planner` → `{NN}-PLAN.md`.
5. Spawn `release-plan-checker` (`Agent({subagent_type: "release-plan-checker", stack: "react", phase: "{NN}", slug: "{slug}", phase_dir: ".release-planning/phases/{NN}-{slug}"})`) → `{NN}-PLAN-CHECK.md` (PASS/WARN/BLOCK). If BLOCK: report + suggest `--revise`; if WARN: proceed; if PASS: continue.
6. Verify plan manually: RC1-RC7 present, security matrix present, TDD ordering correct.
7. Commit artifacts.

### fullstack (worktree-isolated parallel planning)

Fullstack planning runs backend + frontend pipelines **in parallel** using `git worktree` to prevent agent collision on shared paths (PROJECT.md, ROADMAP.md reads, .release-planning/ writes).

#### Setup phase

```bash
PHASE_DIR=".release-planning/phases/{NN}-{slug}"
ROOT=$(git rev-parse --show-toplevel)
WT_BASE="$ROOT/../release-worktrees"

mkdir -p "$WT_BASE"

# Worktree per pipeline (detached HEAD — no branch needed, planning is .planning-only)
git worktree add --detach "$WT_BASE/{NN}-{slug}-backend"
git worktree add --detach "$WT_BASE/{NN}-{slug}-frontend"
```

#### Parallel planning (single Agent call with two invocations)

Spawn both pipelines in one message — independent worktrees → safe parallel:

- `release-feature-researcher`, `release-pattern-mapper`, `release-feature-planner`, `release-plan-checker` (stack=`django`, phase_dir scoped to backend worktree) execute in `$WT_BASE/{NN}-{slug}-backend`
- `release-feature-researcher`, `release-pattern-mapper`, `release-feature-planner`, `release-plan-checker` (stack=`react`, phase_dir scoped to frontend worktree) execute in `$WT_BASE/{NN}-{slug}-frontend`

Each pipeline's checker call: `Agent({subagent_type: "release-plan-checker", stack: <django|react>, phase: "{NN}", slug: "{slug}", phase_dir: ".release-planning/phases/{NN}-{slug}"})`. Verdict handling: BLOCK → abort merge, report blockers, suggest `--revise`; WARN → log + proceed; PASS → continue to merge phase.

Each pipeline writes its `{NN}-PLAN-*.md` + research artifacts under that worktree's `.release-planning/phases/{NN}-{slug}/`.

#### Merge phase

```bash
# Bring artifacts back into main working tree
cp "$WT_BASE/{NN}-{slug}-backend/.release-planning/phases/{NN}-{slug}/"*-BACKEND* \
   "$WT_BASE/{NN}-{slug}-backend/.release-planning/phases/{NN}-{slug}/"*-RESEARCH-BACKEND* \
   "$WT_BASE/{NN}-{slug}-backend/.release-planning/phases/{NN}-{slug}/"*-PATTERNS-BACKEND* \
   "$WT_BASE/{NN}-{slug}-backend/.release-planning/phases/{NN}-{slug}/"*-PLAN-CHECK* \
   "$PHASE_DIR/" 2>/dev/null || true

cp "$WT_BASE/{NN}-{slug}-frontend/.release-planning/phases/{NN}-{slug}/"*-FRONTEND* \
   "$WT_BASE/{NN}-{slug}-frontend/.release-planning/phases/{NN}-{slug}/"*-RESEARCH-FRONTEND* \
   "$WT_BASE/{NN}-{slug}-frontend/.release-planning/phases/{NN}-{slug}/"*-PATTERNS-FRONTEND* \
   "$PHASE_DIR/" 2>/dev/null || true

# Cleanup worktrees
git worktree remove --force "$WT_BASE/{NN}-{slug}-backend"
git worktree remove --force "$WT_BASE/{NN}-{slug}-frontend"
```

#### Naming convention inside worktrees

Researcher/planner agents MUST suffix outputs with `-BACKEND` / `-FRONTEND` to avoid filename collision on merge:

| Pipeline | Outputs |
|----------|---------|
| backend  | `{NN}-RESEARCH-BACKEND.md`, `{NN}-PATTERNS-BACKEND.md`, `{NN}-PLAN-BACKEND/` (dir com manifest + W*.md), `{NN}-PLAN-CHECK-BACKEND.md` |
| frontend | `{NN}-RESEARCH-FRONTEND.md`, `{NN}-PATTERNS-FRONTEND.md`, `{NN}-PLAN-FRONTEND/` (dir), `{NN}-PLAN-CHECK-FRONTEND.md` |

#### Integration check (in main tree, after merge)

1. Diff `InvoiceSerializer` fields (Django) vs `InvoiceSchema` Zod (React) — flag mismatch.
2. Diff endpoint URL in `urls.py` vs `useInvoices.ts` fetch path.
3. Diff auth header expectation (DRF `authentication_classes`) vs React fetch wrapper.

Mismatches → `{NN}-INTEGRATION-CHECK.md` with HIGH/LOW findings. HIGH blocks execute.

#### Commit

```bash
git add "$PHASE_DIR/"
git commit -m "plan({NN}): fullstack plan ({slug}) — backend + frontend"
```

#### Fallback

If `git worktree` unsupported (Windows + WSL edge cases) or `--no-worktree` flag → sequential planning in main tree.

Report: "Phase {NN} is fullstack. Use `/release:execute {NN} --backend` first, then `--frontend`."

## Output (v0.11.0 — WAVE-SPLIT)

```
.release-planning/phases/{NN}-{slug}/
  {NN}-RESEARCH.md             # researcher output
  {NN}-PATTERNS.md             # pattern-mapper output
  {NN}-PLAN/                   # ← DIR, não file (v0.11.0+)
    manifest.md                # must_haves + threat_model 9-cat + waves table
    W1-red-tests.md            # ~200-600 linhas, 3-5 tasks
    W2-{subsystem}.md
    ...
    WN-verify.md
  {NN}-PLAN-CHECK.md           # checker verdict — inclui wave-budget audit
```

**Fullstack:**
```
{NN}-PLAN-BACKEND/   manifest.md + W*.md
{NN}-PLAN-FRONTEND/  manifest.md + W*.md
{NN}-PLAN.md         (< 200 linhas orchestration apenas — refs ambos dirs + cross-stack T-XX)
{NN}-PLAN-CHECK-BACKEND.md
{NN}-PLAN-CHECK-FRONTEND.md
```

**Wave budget contract (HARD):**
- Target: 400 linhas / 3-5 tasks por wave
- Hard cap: 600 linhas — plan-checker bloqueia
- manifest.md: < 300 linhas, frontmatter + waves table
- Cada wave file: frontmatter `wave`, `depends_on`, `parallel_safe`, `files_touched`

**Complexity contract (HARD — v0.22.0):**
- Cada task declara `complexity: simple | standard | complex` (critérios em `release-feature-planner`
  → `<task_complexity>`). O label escolhe o tier do modelo que executa a task
  (`simple` = um rung abaixo do worker, piso sonnet; demais = worker tier).
- `plan-checker` **FALHA** se qualquer task estiver sem o campo ou com valor inválido, e se uma task
  `security`/`race`/`memray` for marcada `simple` — o risco define o tier.
- Manifest repete os labels por wave (`complexity: {T01: …}`) para o wave-executor rotear sem abrir
  cada slice; divergência entre manifest e corpo da task é HIGH.
- PLAN legado pré-v0.22.0 (nenhuma task com o campo): UMA finding MED, sem FAIL — tudo roda no
  worker tier, comportamento v0.21.0. Adoção parcial (algumas com, outras sem) é FAIL.

## Example

```
/release:plan 01

→ Reading ROADMAP.md Phase 01: "Add invoice list page with filter and export"
→ Signals: "invoice list page" → frontend; "export endpoint" → backend
→ Classification: FULLSTACK

→ Running backend pipeline...
  RESEARCH.md: InvoiceModel exists in financeiro app
  PATTERNS.md: analog → frota/views.py VeiculoViewSet
  PLAN-BACKEND.md: 5 tasks (T01-T05, TDD)
  PLAN-CHECK: PASS

→ Running frontend pipeline...
  RESEARCH.md: closest analog → OrderList.tsx
  PATTERNS.md: clone OrderList, adapt to Invoice types
  PLAN-FRONTEND.md: 4 tasks (T01-T04, TDD with Vitest+RTL)

→ Integration check: InvoiceSerializer fields match InvoiceSchema (Zod) ✓

→ Next: /release:execute 01 --backend  (then --frontend)
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.

## Notes / Constraints

- `release-plan-checker` (v0.7.0) é auto-spawnado after `release-feature-planner` for ALL stacks, BEFORE commit. Verdict gates: BLOCK aborts (suggests `--revise`); WARN logs to PLAN-CHECK.md and proceeds; PASS commits.
- **v0.11.0 BREAKING:** PLAN.md monolítico substituído por `{NN}-PLAN/` dir (manifest.md + N wave files). Plans monolíticos pré-v0.11 são lidos (back-compat) mas checker emite MED finding sugerindo re-rodar `/release:plan`.
- **Wave budget:** target 400 linhas / 3-5 tasks per wave; hard cap 600 linhas (BLOCKER).
- **Model dispatch:** `release-plan-checker`, `release-pattern-mapper`, `release-codebase-mapper`, `release-intel-updater`, `release-nyquist-auditor`, `release-eval-auditor`, security-retro pairs, `release-django-checklist-verifier` rodam em **Sonnet 4.6**. `release-doc-verifier` e `release-doc-classifier` rodam em **Haiku 4.5**. Planejadores e executores permanecem em Opus 4.7.
