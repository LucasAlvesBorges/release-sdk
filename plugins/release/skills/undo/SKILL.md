---
name: undo
description: >
  Safe rollback for release-sdk phases, plans, or the last commit via `git revert` (additive — never
  rewrites history). Three modes: default (HEAD only), `--plan {NN.X}` (one plan slug), or `--phase
  {NN}` (whole phase). Pre-flights worktree cleanliness, refuses detached HEAD, and walks later
  phase manifests to detect `depends_on:` conflicts before any commit is touched. Always confirms
  via AskUserQuestion, supports `--dry-run` and `--force`.
  Use when: a phase or plan landed but needs to be undone without rewriting history or losing the
  audit trail.
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

# /release:undo — Dependency-Aware Rollback

Reverts release-sdk commits with full dependency awareness. Three scopes (HEAD / plan / phase),
one mechanism (`git revert`), zero history rewrites. The phase MANIFEST is the source of truth;
commit-message grep is the fallback.

## Usage

```
/release:undo                       # revert last commit (HEAD only)
/release:undo --plan 03.02          # revert all commits for plan 03-02
/release:undo --phase 03            # revert all commits for phase 03
/release:undo --dry-run             # print the revert plan, mutate nothing
/release:undo --force               # skip dependency check (DANGEROUS, opt-in)
```

`--phase` and `--plan` arguments are zero-padded (`03`, `03.02`) for tab-completion friendliness.
`--dry-run` is compatible with every mode.

---

## Pre-checks (hard gates, all modes)

All must pass before any commit is resolved. Failure → abort with the listed message; mutate
nothing.

| # | Probe | Failure message |
|---|---|---|
| 1 | `git status --short` is empty | `"Worktree dirty. Stash or commit before undo."` |
| 2 | `git symbolic-ref -q HEAD` succeeds (not detached) | `"Detached HEAD — checkout a branch before undo."` |
| 3 | Branch is NOT pushed to a protected remote OR `--force` was passed | `"Branch {name} is pushed to {remote}/{ref}. Re-run with --force to revert anyway."` |

Probe 3 uses `git config --get branch.{name}.remote` + `git ls-remote --heads {remote} {branch}`.
Protected refs (`main`, `master`, `release/*`, `prod/*`) additionally re-confirm via
AskUserQuestion even with `--force` (extra safety prompt — see Step 4).

---

## Execution flow

### Step 0 — Resolve target commits

| Mode | Resolution |
|---|---|
| default | `target_shas = [HEAD]` |
| `--plan NN.X` | Read `.release-planning/phases/{NN}-{slug}/{NN}-MANIFEST.md`; pull `commits:` list under the `plan: {NN}-{X}` block. **Fallback** if MANIFEST missing: `git log --grep="plan {NN}.{X}" --pretty=%H` |
| `--phase NN` | Read MANIFEST `commits:` (all plans). **Fallback**: `git log --grep="phase {NN}" --pretty=%H` |

If the resolved list is empty AND no MANIFEST exists → abort:

> `"Cannot identify commits for {scope}. MANIFEST missing and commit-message grep returned nothing. Run /release:undo (no args) to revert HEAD only."`

If MANIFEST exists but `commits:` is empty → abort:

> `"MANIFEST has no commits recorded for {scope}. Was the phase shipped? Run /release:status to verify."`

### Step 1 — Dependency check (phase/plan modes, skipped on `--force`)

Walk later phases for `depends_on:` references back to the scope being undone.

```python
target_NN = parsed phase number
for later_NN in roadmap_phases where later_NN > target_NN:
    manifest = f".release-planning/phases/{later_NN}-{slug}/{later_NN}-MANIFEST.md"
    if not exists(manifest): continue
    if target_NN in manifest.depends_on:
        if manifest.status == "shipped":
            ABORT: "Phase {later_NN} (shipped) depends_on phase {target_NN}.
                    Undo {later_NN} first, or re-run with --force."
        else:
            WARN: "Phase {later_NN} (status: {status}) depends_on {target_NN}.
                   You will need to replan it after undo. Continue? [yes/abort]"
```

For `--plan NN.X`, the same walk happens but the dependency key is the plan slug
(`depends_on_plans:` in MANIFEST). Also inspect later plans **within the same phase**:

```
plans = manifest.plans[plan_index+1:]
for p in plans:
    if f"{NN}.{X}" in p.depends_on_plans: ABORT (or WARN per status)
```

If multiple dependents exist, list all of them in the abort message, ordered by phase number.

### Step 2 — Build the revert plan

`git revert` requires reverse-chronological order (newest first). Use `git log --pretty=%H
--topo-order --no-walk ${target_shas[@]}` and annotate each with `git log -1 --pretty='%h
%s'` for the confirmation prompt.

### Step 3 — Confirm via AskUserQuestion

Print the full revert plan and ask:

```
→ /release:undo --phase 03 (invoice-pdf-export)
  About to revert 4 commits (reverse-chronological order):

  a1b2c3d  feat(03.04): wire pdf export to invoice list view
  9f8e7d6  feat(03.03): add pdf rendering service
  5c4b3a2  feat(03.02): add InvoicePdfTemplate model + migration
  1029384  feat(03.01): scaffold pdf export endpoint

  Dependency check: PASS (no later phase depends on 03)
  Revert strategy: git revert --no-edit a1b2c3d 9f8e7d6 5c4b3a2 1029384
  Result: 4 new revert commits on current branch

  Proceed?  [yes / abort]
```

For `--force` runs, the prompt also shows which dependency checks were **skipped**:

```
  Dependency check: SKIPPED (--force)
  Skipped warnings: phase 04 (in_progress) depends_on phase 03
```

If `--dry-run` → print the plan and exit immediately. Do NOT call AskUserQuestion.

### Step 4 — Run `git revert`

Single command, all SHAs at once. `--no-edit` keeps the default revert message; `-X theirs`
is NOT used (manual conflict resolution is the right escape hatch).

```bash
git revert --no-edit ${ordered_shas[@]}
```

#### Conflict handling

If git exits non-zero (merge conflicts during revert):

1. Do NOT call `git revert --abort` automatically.
2. Print:

   ```
   → CONFLICT during git revert at commit {sha}.
     Worktree left mid-revert. Choose one:
       (a) resolve conflicts, then:  git revert --continue
       (b) bail out entirely with:   git revert --abort
     STATE.md and MANIFEST will be updated only after a clean finish — re-run
     /release:undo --resume after (a) to record the rollback in artifacts.
   ```

3. Exit with status 1. Do NOT touch STATE.md or MANIFEST.

A future `--resume` mode (not implemented in v0.8.0; see Notes) will detect a finished revert
chain and update artifacts retroactively.

### Step 5 — Record the undo

Only after `git revert` exits 0:

1. **STATE.md history block** — append:

   ```markdown
   ## 2026-05-25T14:22:08-03:00 — undo
   - scope:    phase 03 (invoice-pdf-export)
   - commits:  a1b2c3d 9f8e7d6 5c4b3a2 1029384
   - reverts:  f00ba4 c0ffee b16b00 deadbe
   - by:       /release:undo --phase 03
   - reason:   (interactive — user did not provide)
   ```

2. **Cursor adjustment** — if `--phase NN` was undone AND STATE.md cursor was on a later
   phase, leave it alone. If cursor was on the undone phase, set its stage back to:
   - phase mode: `not-started`
   - plan mode: stage stays at `executing` (plan-level undo is a partial rollback within a
     phase)

3. **Phase manifest update** — append a `reverted_commits:` block:

   ```yaml
   reverted_commits:
     - original: a1b2c3d
       revert:   f00ba4
       when:     2026-05-25T14:22:08-03:00
       reason:   /release:undo --phase 03
   ```

   Add to the manifest of the phase being undone. Do NOT mutate any other manifest.

### Step 6 — Final summary

```
→ /release:undo --phase 03 — complete
  4 commits reverted via 4 new revert commits.
  Worktree clean.  Branch: feat/03-invoice-pdf-export

  Phase 03 status:    not-started (was: shipped)
  Manifest updated:   .release-planning/phases/03-invoice-pdf-export/03-MANIFEST.md
  STATE.md history:   logged

  Next: re-plan if needed, or /release:execute 03 to retry.
```

---

## Constraints

- **`git revert` only.** Never `git reset --hard`, never `git push --force`, never `git
  rebase`. History stays linear and auditable.
- **Worktree must be clean before AND no edits during.** Conflicts are user-resolved — this
  skill never `--abort`s a mid-revert state without explicit instruction.
- **Dependency check is the default.** `--force` skips it but never silently — the
  confirmation prompt always lists skipped warnings.
- **Read-only on `.release-planning/` except STATE.md history + the target phase's
  MANIFEST.md.** Never touch other phases' manifests, never touch SPEC/CONTEXT/PLAN/VERIFY.
- **Tab-completion friendly:** zero-pad phase (`03`) and plan (`03.02`) arguments. Reject
  unpadded input with a hint.
- **Cross-branch / merged-via-PR safety:** if the commits to revert are part of a merged PR
  on `main`, additionally require `--force` AND a re-confirmation prompt (the first revert
  is harmless but conceptually changes the merge intent).
- **Never `/release:auto` fallback.** This skill is explicit-dispatch only.
- **Never touch `.planning/`.** GSD-owned.
- **Idempotent re-runs.** Re-running `/release:undo --phase 03` after a successful revert is
  a no-op: the manifest already lists `reverted_commits:` and the targeted SHAs no longer
  appear in `git log` as un-reverted heads → abort with `"Phase 03 already reverted (see
  reverted_commits in MANIFEST). Nothing to do."`

---

## Example — dependency block

```
/release:undo --phase 02

→ Pre-checks
  ✓ worktree clean
  ✓ on branch feat/04-bulk-archive (not detached)
  ✓ branch not pushed to protected ref

→ Resolving commits for phase 02
  MANIFEST found: .release-planning/phases/02-invoice-schema/02-MANIFEST.md
  commits: 3 (e7f8a9b, 4c5d6e7, 1a2b3c4)

→ Dependency walk
  ✗ phase 03 (shipped)      depends_on: [02]
  ✗ phase 04 (in_progress)  depends_on: [02]

→ ABORTED
  Phase 03 (shipped) and phase 04 (in_progress) depend on phase 02.
  Recommended order:
    1. /release:undo --phase 04
    2. /release:undo --phase 03
    3. /release:undo --phase 02
  Or pass --force to revert phase 02 anyway (you will need to re-plan 03 and 04).
```

---

## Notes

- GSD analog: this mirrors `gsd-undo`. The release-sdk version is **dependency-aware via
  MANIFEST**, which GSD does not yet emit.
- The `--resume` flag (record artifacts after a manually-resolved conflict) is not in v0.8.0.
  Planned for v0.8.1 alongside `/release:plan --mvp` wiring.
- This skill does NOT run tests after revert. Pair with `/release:verify-work {NN}` if you
  want to confirm the reverted state still passes its checks (which it should — the revert
  commits are pure inverse diffs).
- Reverting a merge commit requires `-m 1` on `git revert`. This skill detects merge commits
  via `git rev-list --merges` intersected with the target set and adds `-m 1` automatically
  with a printed note.
- The MANIFEST contract (`commits:`, `depends_on:`, `depends_on_plans:`, `reverted_commits:`)
  is enforced by `/release:execute` at commit time. If a phase predates the MANIFEST contract
  (pre-v0.7.0 artifacts), the commit-message grep fallback handles it.

## Stack dispatch

Stack-agnostic. `git revert` does not care whether the diff is Django or React. No agent
spawning. The revert plan + dependency walk happen entirely in this skill; no `/release:*`
sub-skill is dispatched.

*Roll back without rewriting. The audit trail is the point.*
