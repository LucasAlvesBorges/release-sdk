---
name: validate-phase
description: >
  Retroactively audit and fill Nyquist validation gaps for a completed phase. Every requirement
  in SPEC + every UAT item must be covered by >=2 tests (Nyquist-style sampling). Audit-only mode
  reports gaps; full mode dispatches /release:add-tests to fill them.
  Use when: phase shipped but coverage suspect; before declaring milestone complete.
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

# /release:validate-phase — Nyquist Sampling Audit

Borrowed from the Nyquist-Shannon sampling theorem: a signal cannot be reconstructed from a
single sample. Applied to coverage: a requirement covered by exactly one test is *aliased* —
the test may be asserting an artifact, a coincidence, or a tautology. Two independent
assertions per requirement is the minimum bar.

This skill audits a completed phase against that bar and, in default mode, dispatches
`/release:add-tests` to fill gaps until every requirement has >=2 covering tests.

## Relationship to /release:verify and /release:verify-work

| Skill | Mode | Question answered |
|---|---|---|
| `/release:verify` | Goal-backward STATIC code audit | "Does shipped code match PLAN.md truths?" |
| `/release:verify-work` | Conversational UAT walkthrough | "Did the human confirm each UAT item works?" |
| `/release:validate-phase` | Test coverage SAMPLING audit | "Is every requirement covered by >=2 tests?" |

`/release:verify` + `/release:verify-work` are run-once gates per phase. `/release:validate-phase`
is a *recurring* gate — runnable any time after `verified` or `shipped`, including weeks later
during milestone close-out audits.

## Usage

```
/release:validate-phase {NN}                # audit + auto-generate gap-fill tests
/release:validate-phase --audit-only {NN}   # audit only; print report; do not generate
/release:validate-phase {NN} --backend      # restrict gap-fill to backend items
/release:validate-phase {NN} --frontend     # restrict gap-fill to frontend items
```

## Pre-checks

Abort with actionable message on any failure:

1. `.release-planning/` directory exists at repo root.
2. Phase dir `.release-planning/phases/{NN}-{slug}/` exists.
3. Phase stage in `.release-planning/STATE.md` is `verified` OR `shipped`.
   - Reject `discussing`, `planning`, `executing` — too early; tests not stable.
4. `{NN}-SPEC.md` AND `{NN}-UAT.md` both exist in the phase dir.
   - If only one is present, abort with: "Need both SPEC and UAT to compute Nyquist coverage."

## Stack detection

Same precedence as other release-* skills:

1. `--backend` / `--frontend` flag → forced stack for gap-fill (audit always scans both).
2. Read `{NN}-PLAN.md` frontmatter `stack:` field.
3. Read `.release-planning/PROJECT.md` `stack:` field.
4. `fullstack` with no flag → audit both, ask user before gap-fill dispatch.

## Execution

```
1. Spawn release-nyquist-auditor with:
     stack: django | react | fullstack
     phase_number: NN
     phase_dir: .release-planning/phases/{NN}-{slug}/
2. Auditor reads SPEC.md + UAT.md + VERIFICATION.md (if present), enumerates requirements,
   globs test files, counts references per requirement.
3. Auditor writes {phase_dir}/{NN}-NYQUIST-AUDIT.md with verdict:
     SUFFICIENT (all requirements have >=2 tests)
     THIN       (>=1 requirement has exactly 1 test)
     MISSING    (>=1 requirement has 0 tests)
4. If --audit-only:
     - Print summary table inline.
     - Stop. Do not dispatch.
5. Else (default):
     - Read NYQUIST-AUDIT.md gap list.
     - For each THIN/MISSING row, build a gap descriptor (requirement id + recommended test).
     - Dispatch /release:add-tests {NN} --gap-fill via the Skill tool, passing the gap list as
       extra context so add-tests prioritises uncovered requirements first.
     - When /release:add-tests returns, re-spawn release-nyquist-auditor to recompute coverage.
6. Commit the NYQUIST-AUDIT.md artifact:
     test({stack}): nyquist gap-fill for phase {NN}
   Stack token resolves to `django`, `ui`, or `fullstack` depending on detection.
```

The skill never modifies tests itself — all writes go through the `release-nyquist-auditor`
agent (for the audit report) and `/release:add-tests` (for new tests). This keeps the test-write
discipline (one path, surfaces failing tests as `TEST-GAP.md`) intact.

## Requirement extraction

The auditor enumerates requirements from three sources, deduplicated by normalised slug:

| Source | Extraction rule |
|---|---|
| `{NN}-SPEC.md` | Each row in `## Requirements` table; each bullet under `## Acceptance Criteria`. |
| `{NN}-UAT.md` | Each row in `## UAT Items` (U-XX). |
| `{NN}-VERIFICATION.md` (if present) | Each truth row from PLAN.md `must_haves.truths`. |

UAT items contribute *user-observable* requirements; SPEC contributes *system* requirements;
VERIFICATION contributes *behavioural* truths. The union is the Nyquist denominator.

## Coverage counting heuristics

For each requirement R, the auditor counts a test as "covering R" when any of the following
match the test file or function body:

1. **Name match** — requirement slug or U-XX id appears in `def test_*` / `it(...)` / `describe(...)`.
2. **Comment match** — requirement slug or U-XX id appears in a comment within the test body.
3. **Fixture match** — fixture / factory name referenced in the requirement appears in the test
   body, scoped to a fixture whose name maps to the requirement (e.g. `bulk_import_csv` fixture
   for a `bulk_import` requirement).
4. **Endpoint / symbol match** — endpoint URL, view class name, model name, component name, or
   route literal extracted from the requirement description appears in the test body.

Coincidental matches are accepted by design — the Nyquist principle is satisfied if *any* two
independent tests assert anything about the same surface; over-counting is preferable to
under-counting because the human sees the test-file list per requirement and can challenge it.

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-NYQUIST-AUDIT.md
```

Frontmatter:

```yaml
---
audited_at: {iso}
phase: {NN}
stack: django | react | fullstack
mode: full | audit-only
requirement_count: {N}
sufficient: {N}       # >=2 tests
thin: {N}             # exactly 1 test
missing: {N}          # 0 tests
verdict: SUFFICIENT | THIN | MISSING
gap_fill_dispatched: true | false
---
```

Body sections:

- `## Coverage Matrix` — one row per requirement: `| Req | Source | Tests count | Status | Test files |`
- `## Gap-Fill Recommendations` — one block per THIN/MISSING requirement: required test type
  (smoke / RTL / MSW / a11y / security / race / memray) + skeleton hint.
- `## Dispatched Tests` (full mode only) — populated by re-audit after add-tests returns; lists
  newly created test files and their target requirements.
- `## Verdict` — overall + per-stack roll-up.

## Anti-patterns

- Running on a phase still in `executing` stage → tests not stable; audit churns. Blocked at pre-check.
- Editing `{NN}-NYQUIST-AUDIT.md` by hand to mark SUFFICIENT → defeats sampling; re-run skill.
- Treating one high-quality integration test as equivalent to two unit tests → Nyquist insists
  on >=2 *independent* tests; one rich test still leaves the requirement aliased.
- Using `--audit-only` repeatedly without ever gap-filling → audit becomes wallpaper.

## What this skill does NOT do

- Does NOT modify implementation files; all writes are tests via `/release:add-tests`.
- Does NOT delete/rewrite existing tests; only adds.
- Does NOT advance STATE.md cursor — validation is post-shipping, no phase state change.
- Does NOT enforce coverage % thresholds — Nyquist is per-requirement, not per-line.
- Does NOT replace `/release:verify` or `/release:verify-work` — third gate, runs after both.
- Does NOT commit anything in `--audit-only` mode.

## Workflow integration

```
/release:execute 01 && /release:verify 01 && /release:verify-work 01
/release:validate-phase 01           # third gate — Nyquist
/release:ship 01

# Milestone audit (audit-only sweep):
for phase in 01 02 03 04 05; do /release:validate-phase --audit-only $phase; done
```

## Example

```
/release:validate-phase 03
-> Phase 03-bulk-import (stack=fullstack, stage=shipped)
-> Auditor: 14 requirements; 9 sufficient, 3 thin, 2 missing -> verdict MISSING
-> Dispatching /release:add-tests 03 --gap-fill with 5 target requirements...
-> 5 new test files committed.
-> Re-audit: 14/14 SUFFICIENT.
-> Commit: test(fullstack): nyquist gap-fill for phase 03
```


---

## Stack dispatch

This skill spawns the merged `release-nyquist-auditor` agent. Stack is inferred from
`.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack
phases, per-phase stack is read from the phase frontmatter. The auditor applies matching
stack-specific test-discovery rules (pytest globs for django; vitest + RTL globs for react).
