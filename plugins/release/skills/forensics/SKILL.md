---
name: forensics
description: >
  Post-mortem investigation for failed release-sdk workflows. Diagnoses what went wrong when a
  phase didn't complete, verify failed, autonomous run aborted. Produces timeline + 5-whys root
  cause + recovery plan in .release-planning/forensics/.
  Use when: something broke and you need a structured explanation before retrying.
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

# /release:forensics — Post-Mortem Failure Investigation

Read-only forensic pass over `.release-planning/` artifacts, STATE.md history, and git log
to explain why a phase, verify, or autonomous run aborted. Produces a timeline, 5-whys per
root cause, and a recovery plan you can act on before retrying.

## When to use

- A phase stopped mid-execute and you don't know which task / agent failed.
- `/release:verify` came back BLOCK and the SUMMARY doesn't explain why.
- An autonomous run aborted between phases — no human in the loop saw the failure.
- A reviewer flagged drift between PLAN.md and shipped code and you need the audit trail.

## What this skill does NOT do

- Does NOT modify any source file, artifact, commit, or branch.
- Does NOT re-run the failed workflow (use the recovery plan output for that).
- Does NOT replace `/release:debug` (that's interactive root-cause; this is offline reconstruction).
- Does NOT touch `.planning/` (this plugin lives in `.release-planning/`).

## Usage

```
/release:forensics                              # diagnose the most recent failure in STATE.md
/release:forensics 01                           # investigate phase 01 specifically
/release:forensics --since a1b2c3d              # investigate everything since that git SHA
/release:forensics 01 --since a1b2c3d           # combine — scope to phase AND time window
```

## Pre-checks (hard requirements)

1. `.release-planning/STATE.md` exists — abort with guidance if missing (no workflow to diagnose).
2. Current working dir is inside a git repo — abort otherwise (no commit history to walk).
3. If `{NN}` given: `.release-planning/phases/{NN}-*/` exists — abort if not.

No checks are made for clean working tree. Forensics is read-only; dirty trees are fine.

## Scope resolution

| Flag | Scope |
|---|---|
| (none) | Most recent FAIL / BLOCK / ABORT entry in STATE.md; pull its phase from the line. |
| `{NN}` | All phase `{NN}-*/` artifacts + STATE.md lines mentioning phase `{NN}`. |
| `--since {sha}` | Every phase touched by commits between `{sha}..HEAD` + STATE.md lines newer than `{sha}` timestamp. |
| `{NN} --since {sha}` | Intersection — phase `{NN}` events newer than `{sha}`. |

## Execution

1. **Load STATE.md history.** Read last 50 lines (or full file if shorter). Extract every
   `phase: NN`, `verdict: BLOCK|FAIL|ABORT`, `stage:`, and `timestamp:` field.

2. **Load phase artifacts in scope.** For each `{NN}-*/` directory:
   ```
   {NN}-SPEC.md         {NN}-PLAN.md            {NN}-PLAN-BACKEND.md
   {NN}-PLAN-FRONTEND.md {NN}-SUMMARY.md        {NN}-VERIFICATION.md
   {NN}-UAT.md          {NN}-SECURITY.md        {NN}-REVIEW.md
   {NN}-NYQUIST-AUDIT.md {NN}-EVAL-REVIEW.md    {NN}-UI-AUDIT.md
   ```
   Skip files that don't exist. Note their last-modified mtime for the timeline.

3. **Walk git history.** Within scope window, run:
   ```bash
   git log --pretty='format:%h|%ai|%s' --name-only {since}..HEAD
   ```
   Group commits by phase (parse `feat(NN):` / `test(NN):` / `refactor(NN):` prefix or
   commits on branch `feat/{NN}-{slug}`). Note: each task in PLAN.md should produce ≥1
   commit — flag any task with zero commits as a `gap` event.

4. **Identify failure surface.** Cross-reference STATE.md verdicts against artifacts:
   - `VERIFICATION.md verdict: BLOCK` → goal-backward verify failed; pull failing truths.
   - `REVIEW.md` HIGH/CRITICAL findings → reviewer caught regression.
   - `SECURITY.md` MISSING status → retroactive security audit blocked.
   - `UAT.md` items FAIL/BLOCKED → human gate failed.
   - `NYQUIST-AUDIT.md` gaps → validation coverage missing.
   - SUMMARY.md absent for a phase at stage `executing` → executor crashed mid-task.

5. **Cross-reference reviewer / auditor reports.** For each non-PASS verdict, extract the
   `evidence:` (file:line) and `remediation:` blocks verbatim — these become 5-whys seeds.

6. **Build timeline.** Sort events (STATE.md lines + commit timestamps + artifact mtimes)
   chronologically. Each row: `iso_timestamp | source | event`.

7. **5-whys per root cause.** For every distinct failure surface from step 4, write a
   5-whys chain. Stop when you hit either: an environmental cause (missing fixture, dep
   not installed), a process cause (skipped pre-check, plan never updated), or a code
   cause (specific commit introduced regression — name it).

8. **Recovery plan.** Map each root cause to a concrete next action. Prefer existing
   skills: `/release:plan {NN} --gaps`, `/release:execute {NN} --resume`,
   `/release:verify {NN}`, `/release:debug`, `/release:secure-phase {NN}`, etc. Order
   actions by dependency (fix the thing that's blocking the next thing first).

9. **Write report.** Single file:
   ```
   .release-planning/forensics/{ISO_timestamp}-report.md
   ```
   `ISO_timestamp` is `YYYY-MM-DDTHH-MM-SS` (filesystem-safe — no colons). Create the
   `forensics/` directory if it does not exist.

## Output format

```markdown
---
investigated_at: 2026-05-25T14:30:12Z
phases_in_scope: [01, 02]
since_sha: a1b2c3d
root_causes_count: 3
verdict_summary:
  fail: 1
  block: 2
  abort: 0
---

# Forensics Report — 2026-05-25T14:30:12Z

## Scope
- Phases: 01-invoices-crud, 02-invoices-list
- Time window: a1b2c3d..HEAD
- Triggered by: most recent STATE.md FAIL entry

## Timeline
| When | Source | Event |
|---|---|---|
| 2026-05-24T09:12Z | STATE.md | phase 01 stage: planning → executing |
| 2026-05-24T09:18Z | git | commit a1b2c3 test(invoices): add failing tests for create |
| 2026-05-24T09:45Z | git | commit d4e5f6 feat(invoices): implement InvoiceCreate viewset |
| 2026-05-24T10:02Z | 01-VERIFICATION.md | verdict: BLOCK (1 truth unmet) |
| 2026-05-24T10:03Z | STATE.md | phase 01 stage: executing → blocked |
| 2026-05-24T10:15Z | git | commit g7h8i9 feat(invoices): tenant scope filter (partial) |
| 2026-05-24T10:30Z | 01-REVIEW.md | HIGH finding: tenant filter only on list, not retrieve |

## Failure Surfaces
1. **VERIFICATION BLOCK** — `01-VERIFICATION.md` truth T-03 unmet
   - Evidence: `backend/apps/invoices/views.py:42` — list filtered, retrieve unfiltered.
2. **REVIEW HIGH** — `01-REVIEW.md` finding #2
   - Evidence: same file:line as above (correlated, not independent).

## Root Causes (5-whys)

### RC-1: Tenant scope filter missing on retrieve
- Why did verify fail? Truth T-03 (every endpoint scopes by empresa) was unmet.
- Why was it unmet? `retrieve()` was inherited from `ModelViewSet` without override.
- Why was it not overridden? PLAN.md task T-02 only listed `list()` — `retrieve()` not enumerated.
- Why was the task incomplete? Spec phase declared "list invoices" — retrieve was scope creep added during execute without plan amendment.
- Root cause: **PLAN.md did not enumerate every endpoint touched; executor implemented opportunistically.**

## Recovery Plan
1. `/release:plan 01 --gaps` — amend plan to enumerate retrieve, add tenant scope task.
2. `/release:execute 01 --gaps` — implement the gap-closure task only.
3. `/release:verify 01` — re-run goal-backward; expect T-03 → MET.
4. `/release:secure-phase 01` — retroactive security audit to confirm no drift.
5. `/release:ship 01` once PASS.

## Gaps & Caveats
- 02-PLAN.md exists but no commits found — phase 02 never executed; not a failure, just not-started.
- `.release-planning/STATE.md` lines older than 2026-05-23 not loaded (last-50-lines cap).
```

## Constraints

- Read-only on git, source, and `.release-planning/` (except writing the new report file).
- Never `git checkout`, `git reset`, `git revert`, or any mutating git command. `git log` /
  `git show` / `git diff` only.
- Never re-spawn auditor / reviewer agents — quote their existing reports verbatim.
- Single output file per invocation. Multiple runs accumulate in `forensics/` directory.
- If STATE.md is corrupt or unreadable, abort with a message pointing at `/release:status`.

## Example

```
/release:forensics

→ Loading STATE.md (last 50 lines)...
→ Most recent FAIL: phase 01, verdict BLOCK at 2026-05-24T10:03Z
→ Scope: phase 01-invoices-crud
→ Loading artifacts: PLAN.md, SUMMARY.md, VERIFICATION.md, REVIEW.md
→ Walking git log: 4 commits in phase window
→ Identifying failure surfaces: 2 (VERIFICATION BLOCK, REVIEW HIGH — correlated)
→ Building timeline: 7 events
→ Running 5-whys: 1 root cause (PLAN.md scope gap)
→ Drafting recovery plan: 5 steps

→ .release-planning/forensics/2026-05-25T14-30-12-report.md written

Next: review the recovery plan; start with /release:plan 01 --gaps
```
