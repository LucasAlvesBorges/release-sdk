---
name: autonomous
description: >
  Run all remaining phases autonomously: for each phase in ROADMAP.md not yet shipped,
  runs /release:spec → /release:discuss → /release:plan → /release:execute → /release:verify-work
  in sequence. Aborts on first verify failure. Never auto-ships. Designed for stable, well-spec'd
  milestones where the user trusts the per-phase machinery to be correct without supervision.
  Use when: roadmap is locked, ambiguity is low, and you want to walk away while it runs.
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

# /release:autonomous — Unattended Phase Loop

Drives the full per-phase machinery (spec → discuss → plan → execute → verify-work) across
every remaining phase in `ROADMAP.md`. One command, no babysitting. Aborts loudly the
moment something refuses to PASS.

## Usage

```
/release:autonomous                      # all remaining phases from active cursor → end
/release:autonomous --from 03            # start at phase 03 (skip earlier, even if unshipped)
/release:autonomous --until 07           # stop after phase 07 finishes
/release:autonomous --from 03 --until 07 # bounded window
/release:autonomous --dry-run            # print the plan; do not invoke any skill
/release:autonomous --skip-verify        # skip /release:verify-work step (NOT recommended)
```

`--from` and `--until` are inclusive. `--dry-run` only prints the proposed sequence.

---

## Pre-checks (hard gates)

All must pass before the first phase runs. Any failure → abort with the listed message and
do nothing.

| # | Probe | Failure message |
|---|---|---|
| 1 | `test -d .release-planning` | `".release-planning/ not found — run /release:init first."` |
| 2 | `git status --short` is empty | `"Worktree dirty. Commit, stash, or revert before /release:autonomous."` |
| 3 | `.release-planning/ROADMAP.md` exists AND has ≥1 phase not marked `shipped` | `"No unshipped phases in ROADMAP.md — nothing to run."` |
| 4 | Active phase cursor in `STATE.md` is at stage `verified` or `shipped` (no half-finished phase) | `"Phase {NN} is at {stage}. Finish it or pause first."` |

After pre-checks pass, build the phase list:

```
phases_to_run = [NN for NN in ROADMAP if stage != "shipped"
                 AND (--from is null OR NN >= --from)
                 AND (--until is null OR NN <= --until)]
```

If the list is empty after filtering, abort with `"No phases in window."`.

---

## Execution flow

### Step 0 — Plan announce (always)

Print the resolved window + per-phase action plan, then ask the user to confirm via
`AskUserQuestion` UNLESS `--dry-run` (which just prints and exits):

```
→ /release:autonomous — resolved plan
  window: phases 03 → 07 (5 phases)
  skip-verify: false
  per-phase steps: spec → discuss → plan → execute → verify-work

  03  spec=skip   discuss=skip   plan=run   execute=run   verify=run
  04  spec=run    discuss=run    plan=run   execute=run   verify=run
  05  spec=run    discuss=run    plan=run   execute=run   verify=run
  06  spec=run    discuss=run    plan=run   execute=run   verify=run
  07  spec=run    discuss=run    plan=run   execute=run   verify=run

  Proceed?  [yes / abort]
```

The "skip" decisions come from existing artifacts (see Step 1 sub-checks). `--dry-run`
exits here with the table printed.

### Step 1 — Per-phase loop

For each `NN` in `phases_to_run`, in ROADMAP order, run the substeps below. Each substep
checks an artifact-gate first; if the gate is met, the substep is skipped (already done).

```
For NN in phases_to_run:

  1. SPEC
     gate: {NN}-SPEC.md exists AND ambiguity_score: LOW
     if not gated → Skill("release-spec", args=str(NN))
     if SPEC still HIGH after run → ABORT (rule: never auto-plan a HIGH-ambiguity phase)

  2. DISCUSS
     gate: {NN}-CONTEXT.md exists AND status: discussed
     if not gated → Skill("release-discuss", args=str(NN))

  3. PLAN
     gate: {NN}-PLAN.md exists AND ready_for_execute: true
     if not gated → Skill("release-plan", args=str(NN))

  4. EXECUTE
     always → Skill("release-execute", args=str(NN))
     execute is responsible for branch-per-phase, atomic commits, SUMMARY.md.

  5. VERIFY-WORK
     if --skip-verify → log "verify skipped (--skip-verify)" and continue
     else → Skill("release-verify-work", args=str(NN))
     if verify verdict != PASS → ABORT (Step 3 — Abort handling)

  6. CHECKPOINT
     append progress to .release-planning/autonomous-run.md
     advance cursor in STATE.md to next NN (or mark "autonomous-complete" if last)
```

### Step 2 — Checkpoint protocol

After each phase completes (regardless of PASS or ABORT), append to
`.release-planning/autonomous-run.md`:

```markdown
## Phase {NN} — {slug}
- started:     2026-05-25T11:34:02-03:00
- finished:    2026-05-25T12:08:51-03:00
- duration:    34m 49s
- commits:     a1b2c3, d4e5f6, g7h8i9, j0k1l2
- spec:        skip (cached)
- discuss:     run
- plan:        run
- execute:     run
- verify-work: PASS
- summary:     .release-planning/phases/{NN}-{slug}/{NN}-SUMMARY.md
```

This file is the resume contract. If the user `/clear`s between phases, they can read it
and continue manually by invoking `/release:autonomous --from {next_NN}`.

### Step 3 — Abort handling

On first non-PASS verify OR any uncaught error from a dispatched skill:

1. Stop the loop. Do NOT continue to the next phase.
2. Write a final block to `autonomous-run.md`:

```markdown
## ABORTED at phase {NN}
- reason:   verify-work returned FAIL
- evidence: .release-planning/phases/{NN}-{slug}/{NN}-VERIFY.md
- next:     inspect, fix manually, then re-run /release:autonomous --from {NN}
```

3. Leave the worktree exactly as the failing step left it (do NOT clean, do NOT revert).
4. Print the abort block to stdout so the user sees it immediately.

### Step 4 — Final summary (only if loop completes)

When every phase in the window finishes with verify PASS, print one table:

```
→ /release:autonomous — complete

  phase  duration   commits  verdict
  ─────  ────────   ───────  ───────
  03     34m 49s    4        PASS
  04     1h 02m     6        PASS
  05     22m 11s    3        PASS
  06     58m 33s    5        PASS
  07     41m 07s    4        PASS

  Most recent verified phase: 07
  Next:  /release:ship  (manual — autonomous never auto-ships)
```

Do NOT invoke `/release:ship`. The shipping decision is always human-owned.

---

## Constraints

- **Worktree must stay clean between phases.** Each phase commits its own work via
  `/release:execute` (branch-per-phase). If `git status --short` is non-empty AFTER a
  phase claims PASS, abort with `"Phase {NN} left worktree dirty — cannot continue."`.
- **Never auto-ship.** No `/release:ship`, no `gh pr merge`, no `git push --force`.
- **Never skip phases with HIGH ambiguity.** The SPEC step is the gate. If `/release:spec`
  produces a HIGH score, the loop aborts so the human can clarify.
- **Abort loudly on first verify failure.** No "best effort" continuation. No silent skips.
- **One skill at a time.** Dispatch is sequential — never spawn two `Skill` calls in
  parallel. The per-phase loop is intentionally serial.
- **`/release:auto` is NOT a fallback.** Every step is dispatched by explicit skill name.
  If a substep name is wrong, that's a bug in this skill, not a routing problem.
- **This skill orchestrates only.** It does not edit code, run tests, or commit. All real
  work happens inside the dispatched `/release:*` skills.
- **Never touch `.planning/`.** That's GSD-owned. release-sdk lives in `.release-planning/`.
- **Idempotent restart.** Re-running with `--from {NN}` after an abort must resume cleanly
  using the artifact gates — no duplicate spec/discuss/plan work.

---

## Example

```
/release:autonomous --from 03 --until 05

→ Pre-checks
  ✓ .release-planning/ exists
  ✓ worktree clean
  ✓ ROADMAP has unshipped phases
  ✓ cursor at 02 = shipped

→ Resolved window: phases 03 → 05 (3 phases)
  03  spec=skip   discuss=skip   plan=run   execute=run   verify=run
  04  spec=run    discuss=run    plan=run   execute=run   verify=run
  05  spec=run    discuss=run    plan=run   execute=run   verify=run

  Proceed?  [yes]

→ Phase 03 (invoice-pdf-export)
  · spec   skipped (03-SPEC.md ambiguity_score: LOW)
  · discuss skipped (03-CONTEXT.md status: discussed)
  · plan   ✓ ready_for_execute: true
  · execute ✓ 4 commits on feat/03-invoice-pdf-export
  · verify ✓ PASS (RC1-RC7 evidence + UAT-01..04 green)
  · checkpoint written
  · cursor → 04

→ Phase 04 (invoice-archive-endpoint)
  · spec   ✓ ambiguity_score: LOW
  · discuss ✓
  · plan   ✓
  · execute ✓ 6 commits on feat/04-invoice-archive-endpoint
  · verify ✗ FAIL — UAT-02 regression on bulk archive

→ ABORTED at phase 04
  reason:   verify-work returned FAIL
  evidence: .release-planning/phases/04-invoice-archive-endpoint/04-VERIFY.md
  next:     inspect, fix manually, then /release:autonomous --from 04

→ Worktree left as-is for inspection.
```

---

## Notes

- GSD analog: this mirrors `gsd-autonomous` but is namespaced to `/release:*` and uses
  release-sdk's artifact gates (`{NN}-SPEC.md`, `{NN}-CONTEXT.md`, `{NN}-PLAN.md`).
- The `--skip-verify` flag exists for emergencies (e.g., verify tooling is broken). It is
  NOT a recommended steady-state mode — the whole point of autonomous is trusting the
  verify gate.
- Future work: a `--parallel-phases N` flag that runs disjoint phases (different stacks
  or different app modules) in worktree-isolated parallel branches. Today, serial only.

## Stack dispatch

This skill is stack-agnostic — it never spawns stack-specific agents directly. The
dispatched `/release:*` skills handle their own stack routing via `.release-planning/PROJECT.md`
`stack:` field and per-phase frontmatter. For fullstack phases, the per-phase loop runs
`/release:execute` once; that skill itself prompts for `--backend` vs `--frontend` if both
plans exist (see `execute` SKILL.md).

*Drives the full release-sdk machinery unattended. One PASS gate per phase, one ABORT gate
per failure, zero auto-ship. The orchestrator your roadmap deserves once the LOCKs hold.*
