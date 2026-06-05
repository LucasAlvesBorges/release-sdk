---
name: workstreams
description: >
  Manage parallel workstreams within a milestone: list/create/switch/status/progress/complete/resume/remove.
  Each workstream gets isolated `.release-planning/workstreams/<name>/`, dedicated `ws-<name>` branch,
  session-scoped active pointer. Stack-aware (Django / React / fullstack) per workstream.
  Use when two or more features must progress in parallel in the same milestone without colliding.
---

> ⚠️ **DEPRECATED (v0.15.0).** The sustained per-domain `ws-<name>` model is superseded by
> **`/release:session`** — ephemeral worktrees on `session/<label>` branches off one base, with
> serialized conflict-safe merge-back. Use `/release:session start <label>` for parallel domains.
> This skill is kept only for repos still mid-migration and will be removed in a future release.

# /release:workstreams — Parallel Feature Isolation (deprecated → /release:session)

Top-level isolation for features running side-by-side. While `release:release-wave-executor`
parallelises *within* a phase, workstreams parallelise *across* phases and features.

Two engineers (or two Claude sessions) can work the same milestone on different
workstreams without touching each other's `.release-planning/`, branch, or active phase pointer.

## Usage

```
/release:workstreams list
/release:workstreams create <name>          # e.g., payments, dashboard-redesign
/release:workstreams switch <name>
/release:workstreams status
/release:workstreams progress               # progress across ALL workstreams
/release:workstreams complete <name>
/release:workstreams resume <name>
/release:workstreams remove <name>
```

Subcommand can be passed positionally (`/release:workstreams list`) or as a flag
(`/release:workstreams --list`). Positional wins on conflict.

---

## Concepts

### Workstream

A named, isolated track of work inside the current milestone:

- **Directory:** `.release-planning/workstreams/<name>/`
  - `ROADMAP.md` — workstream-scoped phases
  - `STATE.md` — workstream cursor (uses `WORKSTREAM-STATE.md` template)
  - `phases/` — phase artifacts (SPEC, PLAN, CONTEXT, REVIEW, SECURITY, etc.)
- **Branch:** `ws-<name>` cut from `main` at create time
- **Stack:** auto-detected at create — Django / React / fullstack (same logic as
  `/release:init`: checks `manage.py`, `package.json`, both → fullstack)

### Active workstream pointer

Resolution order (highest wins):

1. Env var `RELEASE_WORKSTREAM` (session/shell scoped — set when the user wants
   the pointer to NOT persist to disk, e.g., parallel terminals on different streams)
2. File `.release-planning/active-workstream` (single-line, contains workstream name)
3. None → all other release skills operate on top-level `.release-planning/` (legacy mode)

`switch` writes both the file and exports `RELEASE_WORKSTREAM` for the current
shell session (when invoked from a TTY context that can export).

### How other release skills consume this

When `.release-planning/active-workstream` exists OR `RELEASE_WORKSTREAM` is set, other
release skills (`/release:plan`, `/release:execute`, `/release:status`, etc.)
MUST resolve their root as:

```
ROOT = .release-planning/workstreams/<active>/   if a workstream is active
ROOT = .release-planning/                        otherwise
```

Skills that don't yet honour this fall back to root `.release-planning/` — no harm.

---

## Subcommands

### `list`

Reads `.release-planning/workstreams/` directory. For each subdirectory:

1. Read its `STATE.md` frontmatter (status, active phase, branch)
2. Run `git rev-parse --verify ws-<name> 2>/dev/null` — verifies branch exists
3. Run `git log -1 --format="%h %s" ws-<name>` — last commit
4. Compare to `main` — is the branch ahead/behind?

Render as table:

```
━━━ Workstreams ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ACTIVE  NAME              STACK       STATUS         PHASE  BRANCH         LAST COMMIT
●       payments          fullstack   in-progress    03     ws-payments    a1b2c3 feat(financeiro): refund flow
        dashboard         frontend    idle           01     ws-dashboard   d4e5f6 chore: scaffold
        infra-migrate     backend     blocked        02     ws-infra-mig   g7h8i9 wip: postgres 16 upgrade

3 workstream(s) — 1 active, 1 idle, 1 blocked
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If no workstreams exist:

```
No workstreams yet. Create one with: /release:workstreams create <name>
```

### `create <name>`

Steps (abort on any failure, leave partial state intact for inspection):

1. **Validate name** — `^[a-z][a-z0-9-]{1,39}$`. Reject otherwise.
2. **Check uniqueness** — refuse if `.release-planning/workstreams/<name>/` exists OR
   branch `ws-<name>` exists.
3. **Detect stack** — read `manage.py` / `package.json` presence (mirror
   `/release:init` detection). Allow override via `--stack backend|frontend|fullstack`.
4. **Read milestone version** — from `.release-planning/PROJECT.md` or `STATE.md`. Falls
   back to `unversioned`.
5. **Create branch** — `git checkout main && git pull --ff-only` (warn, don't
   fail, if not on main), then `git switch -c ws-<name>`. Switch back to caller's
   branch after scaffolding (do not leave them stranded on a brand-new branch
   unless they `switch` immediately after).
6. **Scaffold** `.release-planning/workstreams/<name>/`:
   - `ROADMAP.md` — copy from `templates/ROADMAP.md` or top-level `.release-planning/ROADMAP.md`
     header + an empty phase list
   - `STATE.md` — render from `templates/WORKSTREAM-STATE.md` with placeholders
     filled (name, stack, branch=`ws-<name>`, created_at, status=`idle`)
   - `phases/` directory (empty)
7. **Set as active** — write `.release-planning/active-workstream` with `<name>`.
8. **Output:**

```
✓ Workstream 'payments' created
  Stack:   fullstack
  Branch:  ws-payments (from main @ a1b2c3)
  Path:    .release-planning/workstreams/payments/

Active workstream is now: payments

Next:
  /release:roadmap          (decompose milestone within this workstream)
  /release:plan 01          (plan first phase)
```

### `switch <name>`

1. Verify `.release-planning/workstreams/<name>/STATE.md` exists. Abort if not.
2. Write `.release-planning/active-workstream` with `<name>`.
3. Read workstream STATE — recommend `git switch ws-<name>` if caller is on
   a different branch (don't force-switch — caller may have uncommitted changes).
4. Output:

```
Active workstream: payments
Branch:            ws-payments
Active phase:      02 — refund-flow (stage: plan)

Branch you're on now: main
→ Run: git switch ws-payments
```

### `status`

Shows current workstream + its phase pointer. Reuses `/release:status` logic but
scoped to active workstream. If no workstream is active, says so and recommends `list`.

```
━━━ Workstream: payments ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Stack:           fullstack
Branch:          ws-payments  (current: ws-payments ✓)
Active phase:    02 — refund-flow
Active stage:    plan
Last commit:     a1b2c3 feat(financeiro): refund serializer
Uncommitted:     3 files modified, 1 untracked
Status:          in-progress

Handoff notes:
  - Waiting on @lucas to confirm gateway provider before T04
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### `progress`

Iterates every workstream and reports phase counts.

```
━━━ Workstream Progress ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

NAME            DONE   IN-PROGRESS   PLANNED   TOTAL   STATUS
payments        02     01            02        05      in-progress
dashboard       00     01            03        04      in-progress
infra-migrate   01     00            01        02      blocked

Milestone v0.3 — 11 phases total, 3 done, 2 in-progress, 6 planned, 1 blocked
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### `complete <name>`

Finalizes a workstream and folds it into the milestone archive.

1. **Confirmation gate** — use `AskUserQuestion`:
   > "Complete workstream '<name>'? This will merge `ws-<name>` to `main` and
   > archive `.release-planning/workstreams/<name>/` to `.release-planning/milestones/<v>/workstreams/<name>/`.
   > Proceed?" — Yes / No.
2. **Merge check** — run:
   ```bash
   git fetch origin main
   git merge-base --is-ancestor main ws-<name>   # ws contains all of main?
   git merge --no-commit --no-ff ws-<name>       # dry-run on a temp ref
   ```
   If conflicts or branch behind main, abort with:
   > "Branch `ws-<name>` is not mergeable into main (conflicts or behind).
   > Rebase first: `git switch ws-<name> && git rebase main`. Re-run when clean."
3. **Verify phases all complete** — every phase in workstream `ROADMAP.md` must
   have status `complete` in workstream `STATE.md`. Otherwise warn and ask
   confirmation again (allow override for "abandon" semantics).
4. **Merge** — `git switch main && git merge --no-ff ws-<name> -m "merge(ws): <name>"`.
   Do NOT delete the branch (let user do it).
5. **Archive** — `mv .release-planning/workstreams/<name>/ .release-planning/milestones/<v>/workstreams/<name>/`.
   Create `.release-planning/milestones/<v>/workstreams/` if missing.
6. **Clear active pointer** if it pointed at `<name>`.
7. **Output:**

```
✓ Workstream 'payments' completed
  Merged:    ws-payments → main (3 commits)
  Archived:  .release-planning/milestones/v0.3/workstreams/payments/
  Branch:    ws-payments  (kept — delete with: git branch -d ws-payments)

Active workstream cleared. Pick another with: /release:workstreams switch <name>
```

### `resume <name>`

Designed for cross-session pickup. Replays the workstream's last known context.

1. Read `.release-planning/workstreams/<name>/STATE.md` — extract active phase, stage, handoff notes.
2. Set active pointer to `<name>`.
3. Recommend branch switch (`git switch ws-<name>`).
4. Render handoff:

```
━━━ Resuming workstream: payments ━━━━━━━━━━━━━━━━━━━━━━━━━━

Active phase:  02 — refund-flow
Active stage:  execute (backend)
Last task:     T03 — refund serializer (commit a1b2c3)
Last commit:   2026-05-24 18:42

Handoff notes from previous session:
  - T04 blocked: gateway sandbox creds pending
  - Tests passing through T03; do not touch FraudCheck yet

Suggested next:
  git switch ws-payments
  /release:execute 02 --backend --resume
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### `remove <name>`

Destructive — used to discard an aborted experiment.

1. **Confirmation** via `AskUserQuestion`:
   > "Remove workstream '<name>'? This deletes `.release-planning/workstreams/<name>/`
   > and (optionally) branch `ws-<name>`. THIS IS NOT REVERSIBLE. Proceed?"
   > Options: "Remove planning only" / "Remove planning AND branch" / "Cancel".
2. If branch removal selected and branch has unmerged commits, second confirmation:
   > "Branch has N unmerged commits. Force-delete?" — Yes / No.
3. Delete planning dir: `rm -rf .release-planning/workstreams/<name>/`.
4. Delete branch if requested: `git branch -D ws-<name>` (force) or `-d` (safe).
5. Clear active pointer if it referenced `<name>`.
6. Output what was removed.

---

## Stack auto-detection

Per workstream, same rules as `/release:init`:

| Files present | Stack |
|---|---|
| `manage.py` only | `backend` |
| `package.json` (+ React in deps) only | `frontend` |
| Both | `fullstack` |
| Neither | ask user via `AskUserQuestion` |

Stored in workstream `STATE.md` frontmatter (`stack:` field).

## Integration with `release:release-wave-executor`

Workstreams and waves compose:

- A workstream picks up an active phase from its own `ROADMAP.md`.
- Inside that phase, `release:release-wave-executor` may still split tasks across waves.
- Wave sub-agents inherit the active workstream env var so their commits land
  on `ws-<name>`.

## Edge cases & rules

- **No workstreams = legacy mode.** Skills operate on top-level `.release-planning/`.
  This is intentional — workstreams are opt-in.
- **Cannot nest.** A workstream cannot create a sub-workstream. Use phases for
  that level of decomposition.
- **`main` is sacred.** `create` never modifies main beyond the initial branch
  cut. `complete` is the only command that touches main.
- **Branch left on caller after create.** We don't auto-switch to `ws-<name>`
  unless caller follows up with `switch`. This prevents stranding the user with
  uncommitted changes on an untracked branch.
- **Do not delete `main` or `ws-*` shared/protected branches** via `remove`.
- **No commits from this skill** other than the merge commit produced by
  `complete`. All other state mutations are file edits intended to be staged
  by the user when ready.

## Examples

```
# Two parallel features
/release:workstreams create payments
/release:workstreams create dashboard

# Engineer A:
git switch ws-payments
/release:workstreams switch payments
/release:plan 01
/release:execute 01

# Engineer B (different terminal):
RELEASE_WORKSTREAM=dashboard git switch ws-dashboard
/release:plan 01
/release:execute 01

# Later:
/release:workstreams progress      # see both
/release:workstreams complete payments
```
