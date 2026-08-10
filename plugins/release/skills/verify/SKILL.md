---
name: verify
description: >
  Context-aware goal-backward verification. Detects which stacks were implemented in a phase,
  spawns phase-verifier and/or phase-verifier, produces VERIFICATION.md.
  Use when: execute complete, before marking phase done.
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

# /release:verify — Context-Aware Phase Verification

Detects phase type and runs the appropriate verification(s).

## Usage

```
/release:verify 01                   # auto-detect, verify
/release:verify 01 --backend         # Django verification only
/release:verify 01 --frontend        # React verification only
```

## Detection

Reads SUMMARY.md(s) from execute phase:
- `{NN}-SUMMARY.md` with `stack: django` → backend verify
- `{NN}-SUMMARY.md` with `stack: react-tsx` → frontend verify
- Both exist → fullstack verify

## Backend verification (release-phase-verifier)

Goal-backward analysis:
1. Every PLAN.md truth (must_haves.truths) observable in code?
2. Every D-XX decision implemented and grep-provable?
3. All pytest tests pass?
4. `makemigrations --check` clean?
5. `ruff check` clean?
6. Q6: no `.delay()` in production code?
7. 9-category security tests present and passing?

## Frontend verification

Goal-backward analysis:
1. Every D-XX (frontend) decision implemented?
2. All Vitest tests pass?
3. `tsc --noEmit` clean?
4. RC1-RC7 evidence in SUMMARY.md?
5. 9-category React security tests present and passing?
6. No localStorage auth token usage (grep)?
7. CSRF header sent in API calls (test evidence)?

## Integration verification (fullstack)

Additional checks:
- API endpoint from PLAN-BACKEND matches fetch URL in PLAN-FRONTEND
- Serializer field names match Zod schema fields
- Auth strategy consistent end-to-end

## Cross-phase integration check (release-integration-checker)

**Final optional step**, after per-phase VERIFICATION.md is written.

Gate:
```
verified_or_shipped_count = count of phases in current milestone (from ROADMAP.md) at stage ∈ {verified, shipped}
if verified_or_shipped_count >= 2:
    spawn release-integration-checker
else:
    echo "Integration check skipped (only $verified_or_shipped_count phases at verified+, need 2)."
```

Spawn invocation:
```
Agent({
  subagent_type: "release-integration-checker",
  phases: [<NNs of all verified/shipped phases in current milestone>],
  stack: "{django|react|fullstack}",   # auto-detect from PROJECT.md stack: field
  milestone: "{label}"                  # from ROADMAP.md current milestone
})
```

Output: `.release-planning/INTEGRATION-CHECK.md` (milestone-scoped, NOT inside a single phase directory — it spans phases).

**Non-gating:** failures detected by the integration checker DO NOT change the per-phase verify verdict — this step is informational only. Print findings table to stdout so the user sees seam issues, but `{NN}-VERIFICATION.md` verdict stands as written by `release-phase-verifier`.

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-VERIFICATION.md

---
verdict: PASS | GAPS_FOUND
backend_verdict: PASS | GAPS_FOUND | N/A
frontend_verdict: PASS | GAPS_FOUND | N/A
---

## Backend Verification
[table: truth → code evidence → PASS/FAIL]

## Frontend Verification
[table: decision → code evidence → PASS/FAIL]

## Gaps Found (if any)
D-03: NOT IMPLEMENTED — ...
RC2: isError state missing in InvoiceList

## Next Steps
PASS → /release:review 01 (optional), mark phase done
GAPS_FOUND → /release:plan 01 --gaps → /release:execute 01 --gaps
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.

## Notes / Constraints

- v0.7.0 wires `release-integration-checker` as an OPTIONAL final step: spawns only when ≥2 phases in the current milestone are at stage `verified` or `shipped`. Writes milestone-scoped `.release-planning/INTEGRATION-CHECK.md` (not per-phase). Informational — does NOT change the per-phase verify verdict.
