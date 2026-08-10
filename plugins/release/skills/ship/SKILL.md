---
name: ship
description: >
  Create a PR for the active phase after verification passes. Runs a final review pass
  (via `code-reviewer`), drafts a PR title + body grounded in the phase's
  `{NN}-SPEC.md` / `{NN}-PLAN.md` / `{NN}-UAT.md`, then opens the PR via `gh`. Updates
  `.release-planning/STATE.md` cursor to `shipped` on success. Does NOT auto-merge.
  Use when: phase is at `active_stage: verified` and you're ready to publish.
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

# /release:ship — Publish a Verified Phase

Final review → PR draft → `gh pr create` → cursor moves to `shipped`. No merge.

## Usage

```
/release:ship                         # ship the active phase
/release:ship 03                      # ship a specific phase (must be verified)
/release:ship --draft                 # open as draft PR
/release:ship --skip-review           # skip pre-ship review (not recommended)
```

## Pre-checks (hard gates)

1. `.release-planning/STATE.md` exists. Else: "Run `/release:init` first."
2. Target phase exists at `.release-planning/phases/{NN}-{slug}/`.
3. `active_stage` for target phase MUST be `verified`. Else abort with:
   > "Phase {NN} is at stage {stage}. Run `/release:verify-work {NN}` first."
4. Worktree clean (`git status --short` empty). Else: "Commit or stash open work."
5. Current branch is NOT `main` / `master`. Else abort with:
   > "Refusing to ship from main. Create a phase branch first."
6. `gh` CLI authenticated (`gh auth status` succeeds). Else: print login instructions.

## Execution flow

### Step 1 — Pre-ship review (skippable with `--skip-review`)

Spawn `release-code-reviewer` against the phase diff:

```
Agent({
  subagent_type: "release-code-reviewer",
  description: "Pre-ship review of phase {NN}",
  prompt: "Review diff for phase {NN}-{slug}. Scope: `git diff main...HEAD`. Focus: blockers only — bugs, security, broken contracts. Skip nits.",
  metadata: { stack, phase_path: ".release-planning/phases/{NN}-{slug}/" }
})
```

If reviewer returns any `severity: BLOCKER` findings → abort ship, write findings to
`.release-planning/phases/{NN}-{slug}/{NN}-SHIP-REVIEW.md`, exit with:
> "{N} blockers found. Fix and re-run /release:ship."

### Step 2 — Draft PR title + body

Read:
- `{NN}-SPEC.md` → goal, scope
- `{NN}-PLAN.md` → task list, decisions
- `{NN}-UAT.md` → user-facing acceptance checks (verified items only)
- `{NN}-CONTEXT.md` → D-XX decisions

Construct:

- **Title** (< 70 chars): `{type}({scope}): {goal-condensed}` where type is derived from
  the phase commits (feat / fix / refactor / chore).
- **Body**:

```markdown
## Summary
{2-3 bullets — what + why, grounded in SPEC goal}

## Decisions
{D-XX list from CONTEXT.md, one-liner each}

## Test plan
{UAT items, as a markdown checklist — pre-checked since verified}

## Phase artifacts
- `.release-planning/phases/{NN}-{slug}/{NN}-SPEC.md`
- `.release-planning/phases/{NN}-{slug}/{NN}-PLAN.md`
- `.release-planning/phases/{NN}-{slug}/{NN}-VERIFICATION.md`
- `.release-planning/phases/{NN}-{slug}/{NN}-UAT.md`

🤖 Generated with [Codex](https://claude.com/claude-code)
```

### Step 3 — Open PR

If `--draft` was passed, add `--draft` to the `gh` call.

```bash
git push -u origin "$(git branch --show-current)"
gh pr create \
  --title "{title}" \
  --body "$(cat /tmp/release-ship-body-{NN}.md)" \
  ${DRAFT_FLAG}
```

Capture PR URL from `gh` output.

### Step 4 — Update STATE.md

In `.release-planning/STATE.md`:
- Set `cursor.active_stage = shipped` for phase {NN}
- Append history: `{ISO timestamp} — phase {NN} shipped, PR: {url}`

Print PR URL to user.

## Constraints

- **No auto-merge.** Only opens the PR. Merge is a human decision.
- **Verified required.** Refuses to ship anything else.
- **Clean worktree.** No silent staging.
- **Review by default.** `--skip-review` is opt-out, not default.
- **One phase per invocation.** Multi-phase ship → call repeatedly.
- **No `.planning/` writes.** Only release-sdk paths.

## Example

```
/release:ship

→ Target: phase 03-invoice-pdf-export (active_stage: verified) ✓
→ Worktree clean ✓
→ Branch: feat/03-invoice-pdf-export (not main) ✓
→ gh auth ✓
→ Pre-ship review: release-code-reviewer…
  [no blockers]
→ Drafting PR title + body from SPEC + PLAN + UAT
→ Pushing branch + opening PR…
→ PR opened: https://github.com/acme/billing/pull/142
→ STATE.md: phase 03 → shipped
```

---

_Final gate before `git push origin main`. Reviewer-checked, SPEC-grounded, cursor-tracked._
