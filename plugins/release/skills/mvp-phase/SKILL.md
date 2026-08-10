---
name: mvp-phase
description: >
  Plan a phase as a vertical MVP slice. Captures a canonical user story (As a / I want to / So
  that), runs a heuristic size check, and offers SPIDR (Spoke / Paths / Interfaces / Data / Rules)
  decomposition when the slice is too big. Mutates the ROADMAP.md entry for phase NN with
  `Mode: mvp`, the assembled story as Goal, and the chosen SPIDR dimensions. Deferred slices
  auto-append to the ROADMAP backlog. Anchors to (does NOT rewrite) the existing SPEC.md and
  delegates planning to `/release:plan {NN} --mvp`.
  Use when: a phase risks scope creep and you want to enforce a tight vertical slice before
  planning.
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

# /release:mvp-phase — Vertical Slice Pre-Planner

Forces a phase to start as a thin, end-to-end slice: one persona, one path, one surface. The
SPIDR framework is the splitting tool; the canonical "As a... I want to... So that..." story
is the contract. Slices the rest into the backlog. Then hands off to `/release:plan`.

## Usage

```
/release:mvp-phase 03                  # interactive: capture story, size-check, SPIDR if needed
/release:mvp-phase 03 --force          # override phase-status guard (allows re-slicing in-progress phases)
/release:mvp-phase 03 --skip-spidr     # accept full story without splitting (only safe for small phases)
```

Phase argument is zero-padded (`03`, `12`) for tab-completion.

---

## Pre-checks (hard gates)

| # | Probe | Failure message |
|---|---|---|
| 1 | `.release-planning/ROADMAP.md` has phase NN | `"Phase {NN} not in ROADMAP.md. Run /release:phase to add it first."` |
| 2 | Phase NN status is `not-started` OR `--force` passed | `"Phase {NN} status is {status}. Pass --force to re-slice (NOT recommended once execute has started)."` |
| 3 | `.release-planning/PROJECT.md` exists | `"PROJECT.md missing. Run /release:init."` |
| 4 | `.release-planning/phases/{NN}-{slug}/{NN}-SPEC.md` exists | `"SPEC.md not found for phase {NN}. Run /release:spec {NN} first — mvp mode anchors the user story to an existing SPEC."` |

LOCK-XX rules from PROJECT.md are loaded but not enforced here — `/release:plan` enforces them
downstream. This skill is strictly a pre-planning scope contract.

---

## Execution flow

### Step 1 — Capture the user story

Three sequential AskUserQuestion calls. Each result is trimmed and stored.

```
Question 1:
  "As a... (which persona/role uses this slice?)"
  Hint: pick ONE role for v1. Don't say 'any user' or 'admin/manager/operator'.

Question 2:
  "I want to... (what action or capability does this slice deliver?)"
  Hint: one verb. 'archive', 'export', 'reassign'. Not 'manage' or 'handle'.

Question 3:
  "So that... (why does this matter? what value does the persona get?)"
  Hint: a measurable or observable outcome. Not 'so that things are better'.
```

After all three answers are captured, assemble:

```
story = f"As a {role}, I want to {action}, so that {value}."
```

### Step 2 — Validate against canonical regex

Canonical regex: `^As a .+, I want to .+, so that .+\.$`

If the assembled story fails, detect which part is malformed (missing `As a ` prefix, missing
`, I want to `, missing `, so that `, or missing trailing period) and re-ask **only that
part** — never re-ask all three when only one is bad.

### Step 3 — Size heuristic

Print the assembled story, then ask:

```
Assembled story:
  "As a logistics manager, I want to archive completed invoices in bulk,
   so that the active list stays focused on open items."

How many distinct user actions are in this story?
  (1-2)  → tight slice, no SPIDR needed
  (3-5)  → medium — recommend SPIDR-S or SPIDR-P
  (6+)   → too big — REQUIRE SPIDR split before continuing
```

Use AskUserQuestion with options `["1-2", "3-5", "6+"]`.

| Answer | Action |
|---|---|
| `1-2` | Skip SPIDR (unless user explicitly asked). Proceed to Step 5. |
| `3-5` | Recommend SPIDR. Proceed to Step 4 (recommended, not required). |
| `6+` | REQUIRE SPIDR. Proceed to Step 4. `--skip-spidr` is rejected here with: `"Story too big for --skip-spidr. SPIDR split is required when distinct actions >= 6."` |

### Step 4 — SPIDR split

Use AskUserQuestion with the 5 strategies + skip + custom:

```
Which SPIDR dimension narrows this slice the most?

  Spoke       — narrow the persona (e.g., 'manager' only, defer 'operator' + 'auditor')
  Paths       — narrow the workflow (happy path only, defer error/recovery paths)
  Interfaces  — narrow the surface (admin only, defer public UI; or API-only, defer UI)
  Data        — narrow the data scope (one entity type, one tenant, one status filter)
  Rules       — narrow the policy (skip soft-delete, skip audit log, skip notifications)
  skip        — don't split, accept the full story (only allowed when size = 1-2 or 3-5)
  custom      — describe a different split dimension
```

After the user picks a dimension, ask one follow-up:

```
What is being NARROWED to, and what is being DEFERRED?

  Example for Paths:
    narrowed_to: "happy path: select N invoices → confirm modal → bulk archive succeeds"
    deferred:    "partial-failure recovery, undo-archive, audit log entry, email notification"
```

Restate the narrowed story:

```
Restated story (narrowed):
  "As a logistics manager, I want to archive completed invoices in bulk via the happy path,
   so that the active list stays focused on open items."

Narrowed dimensions: Paths (happy-path only)
Deferred to backlog: partial-failure recovery, undo-archive, audit log, email notification
```

Re-run Step 3 (size check) on the restated story. If still `6+`, loop back to Step 4 and stack
a second SPIDR dimension. Allow up to 3 stacked dimensions before warning: `"3 SPIDR dimensions
stacked — consider splitting the phase entirely via /release:phase instead of slicing further."`

### Step 5 — Mutate ROADMAP entry

Locate the phase NN block in `.release-planning/ROADMAP.md`. Apply these edits surgically:

1. **After the phase header line** (`## Phase 03 — invoice-pdf-export`), insert/replace:

   ```markdown
   **Mode:** mvp
   ```

2. **Replace the `**Goal:**` line** with the assembled story:

   ```markdown
   **Goal:** As a logistics manager, I want to archive completed invoices in bulk via the
   happy path, so that the active list stays focused on open items.
   ```

3. **Add a new line** immediately below the Goal:

   ```markdown
   **SPIDR slice:** Paths (happy-path only)
   ```

   If multiple SPIDR dimensions were stacked, join with ` + `:

   ```markdown
   **SPIDR slice:** Paths (happy-path only) + Interfaces (admin UI only)
   ```

   If no SPIDR was applied (size 1-2 or `--skip-spidr`):

   ```markdown
   **SPIDR slice:** none (story already tight)
   ```

If `**Mode:**` or `**SPIDR slice:**` already exist (re-running with `--force`), replace in
place — do NOT duplicate lines.

### Step 6 — Append deferred slices to backlog

In `ROADMAP.md`, locate the `## Backlog` section (create it at the end of the file if
missing). For each deferred slice from Step 4, append:

```markdown
- **Deferred from phase 03 mvp split — Paths:** partial-failure recovery
- **Deferred from phase 03 mvp split — Paths:** undo-archive
- **Deferred from phase 03 mvp split — Paths:** audit log entry
- **Deferred from phase 03 mvp split — Paths:** email notification
```

One bullet per deferred item. Group by dimension when multiple SPIDR rounds were stacked.

### Step 7 — STATE.md history entry

Append to STATE.md history block:

```markdown
## 2026-05-25T15:08:44-03:00 — mvp-phase
- phase:        03 (invoice-pdf-export)
- story:        "As a logistics manager, I want to archive completed invoices in bulk via the
                 happy path, so that the active list stays focused on open items."
- size:         3-5 (SPIDR recommended)
- spidr:        Paths (happy-path only)
- deferred:     4 items added to ROADMAP backlog
- by:           /release:mvp-phase 03
```

### Step 8 — Delegate to `/release:plan`

Final action — invoke planning with the `--mvp` flag:

```python
Skill("release-plan", args=f"{NN} --mvp")
```

The `--mvp` flag tells `/release:plan` to:
- Read the ROADMAP `Mode: mvp` + `SPIDR slice:` fields
- Anchor plan items to the narrowed story
- Refuse plan items that fall outside the SPIDR scope (deferred dimensions become BLOCKERs
  during plan-review-convergence)

> **Note:** `/release:plan --mvp` is planned for v0.8.1. In v0.8.0 it accepts the flag but
> only logs it — the SPIDR enforcement is human-reviewed via the plan diff. See Notes.

---

## Constraints

- **The story regex is canonical.** No relaxation. If the user resists the format, ask them
  to rephrase — do not auto-fix or auto-format their input.
- **SPIDR narrowing is one-way.** Once you cut a dimension, the deferred slices become
  backlog items. Re-running with `--force` re-cuts but does NOT auto-remove previous backlog
  entries (manual cleanup in ROADMAP if reslicing).
- **Never modify SPEC.md.** SPEC is owned by `/release:spec`. This skill ANCHORS to SPEC
  (Pre-check #4), it does not rewrite it. If the user wants the SPEC to reflect the slice,
  they re-run `/release:spec {NN}` after this.
- **Never plan or execute.** This skill strictly delegates to `/release:plan`. No code edits,
  no test scaffolding, no commits beyond the ROADMAP/STATE/backlog mutations.
- **One phase per invocation.** No batch mode. Re-slicing multiple phases means multiple
  calls.
- **Read-only on PROJECT.md, RELEASE-LOCKS.md, REQUIREMENTS.md.** Mutates only ROADMAP.md and
  STATE.md.
- **Never touch `.planning/`.** GSD-owned.
- **Idempotent re-runs (with `--force`):** STATE.md history accumulates entries (audit
  trail). ROADMAP `Mode:` / `Goal:` / `SPIDR slice:` are replaced in place. Backlog entries
  from prior runs are NOT auto-removed (would lose the deferral audit trail) — manual
  cleanup if the user wants a clean ROADMAP.

---

## Example — full flow with one validation failure + SPIDR-S split

```
/release:mvp-phase 03

→ Pre-checks
  ✓ ROADMAP.md has phase 03 (invoice-pdf-export)
  ✓ phase 03 status: not-started
  ✓ PROJECT.md exists
  ✓ 03-SPEC.md exists (ambiguity: LOW)

→ Capture user story
  Q1: "As a..."        → "operations manager or auditor"
  Q2: "I want to..."   → "bulk archive completed invoices"
  Q3: "So that..."     → "active list stays focused"

→ Validating canonical form
  Assembled: "As a operations manager or auditor, I want to bulk archive completed invoices,
              so that active list stays focused"
  ✗ trailing period missing
  Re-enter the 'so that...' clause with a period.
  Q3 (retry): "So that the active list stays focused on open items."

  ✓ canonical OK
  Story: "As a operations manager or auditor, I want to bulk archive completed invoices,
          so that the active list stays focused on open items."

→ Size heuristic
  How many distinct user actions are in this story?
  User: 3-5 → SPIDR recommended

→ SPIDR split — which dimension narrows the most?
  User: Spoke (narrow the persona)

  narrowed_to: "operations manager only"
  deferred:    "auditor role + auditor-specific report view"

  Restated story:
    "As an operations manager, I want to bulk archive completed invoices,
     so that the active list stays focused on open items."

  Re-size:  User: 1-2 → tight, no further split needed.

→ Mutating ROADMAP.md
  Phase 03 header updated:
    + Mode: mvp
    ~ Goal: (replaced with assembled story)
    + SPIDR slice: Spoke (operations manager only)

→ Appending to ROADMAP backlog
  + Deferred from phase 03 mvp split — Spoke: auditor role
  + Deferred from phase 03 mvp split — Spoke: auditor-specific report view

→ STATE.md history logged.

→ Delegating to /release:plan 03 --mvp ...
```

---

## Notes

- GSD analog: this mirrors `gsd-mvp-phase` (same SPIDR pattern, same canonical story regex).
  The release-sdk version differs by writing to `.release-planning/` and using the
  release-sdk artifact contract (`Mode:` / `SPIDR slice:` in ROADMAP, not GSD's
  `mvp_slice:` frontmatter).
- `/release:plan --mvp` flag wiring is in v0.8.1. v0.8.0 accepts but only logs the flag —
  SPIDR-scope enforcement is human-reviewed via plan diff. Track in `RELEASE-LOCKS.md` if
  you want to harden this earlier.
- The `--skip-spidr` flag is a tactical escape hatch for small phases the heuristic
  flagged ambiguously. It is rejected when the size heuristic returns `6+`.
- The 3-dimension SPIDR ceiling is a soft warning, not a hard gate. Past 3, the
  recommendation is to split the phase entirely via `/release:phase` rather than slice it
  further — but the user can override.
- This skill does NOT validate that the narrowed story still fits the SPEC.md scope. That's
  `/release:plan --mvp`'s job downstream (it'll reject plan items outside the SPIDR scope).

## Stack dispatch

Stack-agnostic. SPIDR slicing applies equally to Django backend phases, React frontend
phases, and fullstack phases. No agent spawning here — the only delegation is the final
`Skill("release-plan", ...)` call, which itself routes by stack.

*Tight slices ship. Big slices linger. SPIDR is how you cut.*
