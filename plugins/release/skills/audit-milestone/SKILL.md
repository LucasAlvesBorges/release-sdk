---
name: audit-milestone
description: >
  Standalone, non-destructive milestone audit. Runs the milestone-auditor agent against
  the current (or a specified) milestone and writes a timestamped MILESTONE-AUDIT-{name}-{date}.md
  to `.release-planning/`. Reports requirement coverage (COVERED / PARTIAL / GAP), UAT closure,
  and verify verdicts per phase. Does NOT move phase directories, does NOT update STATE.md,
  does NOT commit (unless --commit).
  Use when: mid-milestone health check, pre-flight before /release:complete-milestone, or
  ad-hoc audit anytime to surface drift between SPEC, UAT, REQs, and shipped code.
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

# /release:audit-milestone — Non-Destructive Milestone Health Check

Runs the same `release-milestone-auditor` agent that gates `/release:complete-milestone`, but
read-only. Output goes to a timestamped file under `.release-planning/` (not under
`milestones/{name}/`), so re-running it leaves a trail without touching the canonical archive
location.

Safe to run anytime: mid-milestone, just before completion, or weeks after archive (audits a
past milestone by name).

## Usage

```
/release:audit-milestone                         # current milestone (from PROJECT.md)
/release:audit-milestone --milestone v1.0        # explicit milestone (current or archived)
/release:audit-milestone --hot-list              # print only uncovered REQs + open UATs (no full file)
/release:audit-milestone --commit                # commit the timestamped audit file
/release:audit-milestone --milestone v1.0 --hot-list   # combine
```

`--hot-list` skips writing a full audit file and prints just the high-signal rows to stdout.
Useful for daily standup checks.

---

## Pre-checks

| # | Probe | Failure message |
|---|---|---|
| 1 | `.release-planning/PROJECT.md` exists | `"PROJECT.md not found — run /release:init first."` |
| 2 | Resolved milestone has ≥1 phase | `"Milestone {name} has no phases — nothing to audit."` |

That's it. No worktree-clean check (read-only). No stage check (auditing mid-milestone is the
whole point).

---

## Resolution rules

1. `--milestone` flag → use it as-is. Must match either an active milestone in ROADMAP.md OR
   an archived directory at `.release-planning/milestones/{name}/`.
2. No flag → read `**Milestone:**` from PROJECT.md.
3. Neither resolvable → abort with `"No milestone to audit. Pass --milestone or set one in PROJECT.md."`.

For archived milestones, the auditor reads from `.release-planning/milestones/{name}/phases/`
instead of `.release-planning/phases/`. Same agent, different scan root.

---

## Execution flow

### Step 1 — Resolve and announce

```
milestone = resolve(--milestone, PROJECT.md)
phases    = enumerate phases_in_milestone(milestone)
scan_root = .release-planning/phases/  (active)  OR
            .release-planning/milestones/{name}/phases/  (archived)

print:
  → Auditing milestone {name} ({len(phases)} phases) — scan root: {scan_root}
```

### Step 2 — Spawn the auditor

Dispatch `release-milestone-auditor` with:

```
milestone:        {name}
scan_root:        {resolved above}
roadmap_path:     .release-planning/ROADMAP.md
project_path:     .release-planning/PROJECT.md
requirements_path: .release-planning/REQUIREMENTS.md
mode:             audit              # NOT "complete" — auditor knows not to expect 100% closure
```

Mode `audit` tells the auditor to:
- Not treat OPEN UATs or PARTIAL coverage as fatal — just report them.
- Annotate each row with phase stage (`spec`, `discussed`, `planned`, `executing`, `verified`,
  `shipped`) so the user can tell drift from work-in-flight.

### Step 3 — Write output (or print hot-list)

#### Default mode (full audit file)

```
.release-planning/MILESTONE-AUDIT-{name}-{YYYY-MM-DD}.md
```

Re-running on the same day overwrites the file (idempotent within a day). Cross-day runs leave
each timestamped audit in place.

#### `--hot-list` mode

Skip the file write. Print only:

```
→ Milestone {name} — hot list ({YYYY-MM-DD HH:MM:SSZ})

  Uncovered REQs:
    REQ-04 — invoice export PDF a11y      (target phase: 03, stage=executing)
    REQ-09 — admin audit log retention    (target phase: 06, stage=spec)

  Open UAT items:
    U-02 (phase 03) — bulk import resumes on error
    U-05 (phase 04) — search filters preserve across navigation
    U-08 (phase 04) — keyboard nav on combobox

  Verify FAIL phases:
    (none)

  Verdict: WORK_IN_PROGRESS (3 phases still executing / 6 shipped)
```

Hot-list is stdout-only — no file, no commit, no STATE entry.

### Step 4 — Optional commit

If `--commit` was passed (and not in hot-list mode), commit the audit file:

```
chore(audit): milestone {name} health check ({YYYY-MM-DD})

Verdict: {PASS | WORK_IN_PROGRESS | DRIFT}
Coverage: {COVERED}/{TOTAL} REQs, {CLOSED}/{TOTAL} UATs
```

Without `--commit`, the file is left untracked. The user can `git add` + commit manually or
discard it.

---

## Output

#### Default mode

```
.release-planning/MILESTONE-AUDIT-{name}-{YYYY-MM-DD}.md
```

Same template as `/release:complete-milestone` step 1, but with mode `audit` reflected in
frontmatter:

```yaml
---
audited_at: {iso}
milestone: {name}
mode: audit
phase_count: {N}
phases_shipped: {N}
phases_in_progress: {N}
req_total: {N}
req_covered: {N}
req_partial: {N}
req_gap: {N}
uat_total: {N}
uat_closed: {N}
uat_open: {N}
verify_pass: {N}
verify_fail: {N}
verify_pending: {N}
verdict: PASS | WORK_IN_PROGRESS | DRIFT
---
```

Verdicts in audit mode:
- `PASS` — every REQ COVERED, every UAT CLOSED, every verify PASS. Same as the completion gate.
- `WORK_IN_PROGRESS` — gaps exist but they map to phases still pre-shipped (stage ≠ shipped).
  Healthy mid-milestone state.
- `DRIFT` — gaps exist on shipped phases (REQ marked GAP/PARTIAL but the phase is `shipped`).
  This is a coverage hole; the phase shipped without closing what it claimed to deliver. Fix
  is `/release:plan {NN} --gaps` or amend SPEC.

#### `--hot-list` mode

stdout only (see Step 3).

---

## Example

```
/release:audit-milestone

→ Resolved milestone: v1.1 (6 phases — 3 shipped, 3 in-flight)
→ Scanning .release-planning/phases/

→ Spawning release-milestone-auditor (mode=audit)...
  · 6 phase dirs scanned
  · 22 requirements: 14 COVERED, 5 PARTIAL, 3 GAP
  · 28 UAT items: 19 CLOSED, 9 OPEN
  · 3 verify verdicts: 3 PASS, 0 FAIL, 3 PENDING (phases not yet verified)

→ Verdict: WORK_IN_PROGRESS
  · All 3 GAP REQs map to phases currently in stage `executing` (06) or `spec` (07)
  · No DRIFT detected (shipped phases all 100% covered)

→ Wrote .release-planning/MILESTONE-AUDIT-v1.1-2026-05-25.md
   (not committed — pass --commit to track)

Next: address GAP rows via /release:spec 07 / /release:plan 06, then re-run.
```

Hot-list variant:

```
/release:audit-milestone --hot-list

→ Milestone v1.1 — hot list (2026-05-25 09:14:02Z)

  Uncovered REQs:
    REQ-12 — admin role-based dashboard widgets   (phase 07, stage=spec)
    REQ-13 — audit log retention policy           (phase 07, stage=spec)
    REQ-15 — bulk-action confirmation modal       (phase 06, stage=executing)

  Open UAT items:
    U-04 (phase 05) — empty-state copy review
    U-06 (phase 06) — combobox keyboard nav
    ... (7 more)

  Verify FAIL phases:
    (none)

  Verdict: WORK_IN_PROGRESS
```

---

## Constraints

- **Read-only by default.** No phase dir moves, no STATE.md updates, no commits unless
  `--commit` is passed.
- **Safe to run anytime.** No phase-stage pre-checks; mid-milestone audits are first-class.
- **Same auditor as `/release:complete-milestone`.** Single source of truth for milestone
  coverage logic; differences are output path + mode flag.
- **Hot-list is stdout-only.** It never writes a file, even if `--commit` is also passed
  (`--commit` is ignored in hot-list mode with a warning).
- **Audits archived milestones too.** Pass `--milestone v0.9` to audit a milestone that's
  already under `.release-planning/milestones/`. Useful for retrospective drift checks.
- **Never touches `.planning/`.** GSD-owned.
- **Idempotent within a day.** Same milestone, same date → file overwrites. Across days →
  each timestamped audit persists for trend tracking.

---

## Notes

- GSD analog: `/gsd:audit-milestone`. Different filesystem; identical intent.
- This skill pairs well with `/release:audit-uat` (cross-phase UAT triage) and
  `/release:validate-phase` (Nyquist sampling per phase). Run sequence for a thorough
  pre-completion sweep:

  ```
  /release:audit-uat                         # surface UATs across all phases
  for nn in 01 02 03 ...; do
    /release:validate-phase --audit-only $nn # Nyquist per phase
  done
  /release:audit-milestone                   # roll up into a milestone-level matrix
  ```

- For very large milestones (>20 phases), the auditor may take 1-2 minutes. The skill prints
  progress (`scanning phase NN…`) so it's not silently hanging.

*The mirror without the move. Safe to run anytime; tells you what's left.*
