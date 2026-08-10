---
name: ui-review
description: >
  Retroactive 6-pillar visual audit of implemented React code for a phase. Spawns react-ui-auditor
  to score accessibility, responsive, loading/error states, i18n, type contracts, and design-system
  adherence. Produces scored UI-REVIEW.md with remediation table per dimension.
  Use when: a phase shipped but UI quality is suspect, or for regular UI debt audits.
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

# /release:ui-review — Retroactive 6-Pillar Visual Audit

Runs AFTER a phase is implemented and committed. Scores the shipped React code against six
quality pillars and produces a `{NN}-UI-REVIEW.md` scorecard with concrete remediation per
dimension. Distinct from `/release:ui-phase` (author-time design-contract) and from
`/release:verify` (truth-coverage, not quality-coverage).

## Difference vs sibling skills

| Axis | `/release:ui-phase` (author-time) | `/release:ui-review` (retroactive) | `/release:verify` (truth check) |
|---|---|---|---|
| When | Before implementation | After phase ships | After phase ships |
| Input | SPEC + CONTEXT + LOCKs | Shipped React source + UI-SPEC | PLAN must_haves + source |
| Output | `{NN}-UI-SPEC.md` (contract) | `{NN}-UI-REVIEW.md` (scored audit) | `{NN}-VERIFICATION.md` (truth verdict) |
| Modifies code | No | No (read-only audit) | No |
| Agents | release-react-ui-researcher | release-react-ui-auditor | release-phase-verifier |

## Usage

```
/release:ui-review 03                    # audit phase 03's shipped React code
/release:ui-review --all                 # audit every phase whose frontmatter has has_ui: true
/release:ui-review 03 --diff main..HEAD  # constrain evidence search to a diff range
/release:ui-review 03 --strict           # any pillar score <60 → BLOCK verdict
```

## Pre-checks

Abort cleanly (no auditor spawned, no commit) if:

1. `.release-planning/` does not exist → emit "Not a release-sdk project; run /release:init first."
2. `--all` mode: no phase has `has_ui: true` in its `{NN}-SUMMARY.md` frontmatter → emit
   "No UI-bearing phases detected. Nothing to audit."
3. Single-phase mode (`NN` given): `.release-planning/phases/{NN}-{slug}/{NN}-UI-SPEC.md`
   is missing → emit "Phase {NN} has no UI-SPEC.md — was this a backend-only phase? If it
   shipped UI, run `/release:ui-phase {NN}` first to author the contract retrospectively."
4. No React source files present anywhere under `src/` (`find src -name "*.tsx" | head -1`
   returns nothing) → emit "No React source detected; nothing to audit."

## Detection / Scope Resolution

For each phase being audited:

1. Locate `.release-planning/phases/{NN}-{slug}/`.
2. Read `{NN}-UI-SPEC.md` (the design contract) — captures intended UI-DEC-XX entries.
3. Read `{NN}-SUMMARY.md` frontmatter for `stack:` (must be `react` or `fullstack`).
4. Resolve in-scope files:
   - Default: union of `.tsx` / `.ts` files touched in phase commits, using
     `git log --name-only` between phase-start commit and HEAD.
   - `--diff REV..REV`: explicit diff range.
5. Bail out for a phase if the resolved set is empty (record as "no UI shipped" in summary).

## Execution

For each in-scope phase, spawn one `release-react-ui-auditor` with this config:

```yaml
phase_number: "{NN}"
phase_dir: ".release-planning/phases/{NN}-{slug}"
ui_spec_path: "{phase_dir}/{NN}-UI-SPEC.md"
in_scope_files: [list of .tsx/.ts paths]
mode: initial | re-audit
strict: false | true
```

When `--all`, run audits in parallel (one auditor per phase). Collect each result.

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-UI-REVIEW.md
```

The auditor produces a scorecard (see `release-react-ui-auditor` for full template). Frontmatter
includes `audited_at`, `score_total`, `score_per_dim` (6 numbers). The skill rolls these up
into a printed summary table.

## Verdict logic (per phase)

- `EXCELLENT` — total ≥ 85 AND no dimension < 70
- `OK`        — total ≥ 70 AND no dimension < 60
- `DEBT`      — total ≥ 50 (any dim may be < 60; remediation needed)
- `BLOCK`     — total < 50 OR (in `--strict` mode) any dimension < 60

## Commit

After all audits complete, stage and commit the produced UI-REVIEW.md files only:

```bash
git add .release-planning/phases/{NN}-{slug}/{NN}-UI-REVIEW.md
git commit -m "chore(ui-review): retroactive audit phase {NN}"
```

For `--all`, commit once with all paths in the message:

```bash
git commit -m "chore(ui-review): retroactive audit phases {01,03,07}"
```

Never auto-commits any source-code changes — the audit is read-only.

## Constraints

- Read-only: never edits React components, hooks, tests, or commits source-code changes.
- Auditors are leaf workers — they spawn no sub-agents.
- Scores must be 0-100 integers with file:line evidence in the per-dim section.
- Remediation table must list concrete fixes (no vague advice like "improve a11y").
- Skipped phases (no UI shipped, missing UI-SPEC) are reported in the run summary, never as a
  failed audit.

## Example

```
/release:ui-review 03

→ Phase: 03-invoice-list  (stack: fullstack)
→ UI-SPEC.md found: 8 UI-DECs
→ Scope: 11 .tsx files from a1b2c3..HEAD
→ Spawning release-react-ui-auditor...

→ Auditor results:
   Accessibility:   72 (target 80)  — 4 inputs missing aria-label
   Responsive:      88               — tailwind sm:/md:/lg: present throughout
   Loading/Error:   65 (target 80)  — error boundary missing on bulk-archive path
   i18n:            42 (BELOW 60)   — 17 hardcoded strings detected
   Type contracts:  91               — all props typed, Zod on API
   Design system:   80               — 2 ad-hoc inline styles flagged

→ Verdict: DEBT  (total 73; i18n below threshold)
→ UI-REVIEW.md written
→ chore(ui-review): retroactive audit phase 03

Next:
  • Address i18n gap before next UI-bearing phase
  • Run /release:ui-review 03 again to confirm uplift
```

```
/release:ui-review --all

→ Phases with has_ui: true: 01, 03, 07
→ Spawning 3 release-react-ui-auditor instances in parallel...

→ Summary:
   | Phase | Total | A11y | Resp | L/E | i18n | Types | DS  | Verdict   |
   |-------|-------|------|------|-----|------|-------|-----|-----------|
   | 01    | 88    | 90   | 92   | 85  | 80   | 95    | 86  | EXCELLENT |
   | 03    | 73    | 72   | 88   | 65  | 42   | 91    | 80  | DEBT      |
   | 07    | 81    | 78   | 82   | 80  | 75   | 90    | 81  | OK        |

→ chore(ui-review): retroactive audit phases 01,03,07
```

---

## Stack dispatch

This skill is React-only by design — `/release:ui-review` refuses Django-only phases at the
pre-check step. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field
(`react` | `fullstack`). For fullstack phases, only the React side is audited; backend code
is ignored. `django`-only projects abort with a clear message at pre-check.
