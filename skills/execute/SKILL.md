---
name: execute
description: >
  Context-aware phase executor (v0.12.0 BREAKING — waves-by-default). Detects backend/frontend
  phase type from PLAN, ALWAYS spawns wave-executor which fans out N tdd-executor
  in worktree-isolated parallel branches per disjoint task group. TDD-strict per task:
  RED → GREEN → REFACTOR → SECURITY. Atomic Conventional commits cherry-picked back to phase branch.
  Use when: PLAN ready (plan-checker PASS or WARN-accepted).
---

# /release:execute — Context-Aware Phase Executor (waves-by-default)

**v0.12.0 BREAKING**: Always routes through `release:wave-executor`. Legacy direct `release:tdd-executor`
serial path removed. Single-worktree falls out naturally for waves with 1 task / collision-bound waves.

## Usage

```
/release:execute 01                  # auto-detect, branch-per-phase, waves-parallel
/release:execute 01 --backend        # force Django planner+executor (waves-parallel)
/release:execute 01 --frontend       # force React planner+executor (waves-parallel)
/release:execute 01 --resume         # skip tasks already committed on phase branch
/release:execute 01 --dry-run        # preview parallel_groups + spawn count without committing
/release:execute 01 --gaps           # execute gap-closure plan (still via wave-executor)
/release:execute 01 --no-branch      # disable branch-per-phase (commit to current branch)
```

`--waves` flag REMOVED in v0.12.0 — waves are the only execution mode.

## Detection logic

1. Read `.release-planning/phases/{NN}-{slug}/{NN}-PLAN.md` frontmatter.
   - `stack: django` → backend
   - `stack: react-tsx` → frontend
2. If both `{NN}-PLAN-BACKEND.md` and `{NN}-PLAN-FRONTEND.md` exist → fullstack (require `--backend` or `--frontend` flag).
3. `--backend` / `--frontend` flags override auto-detect.

## Branch-per-phase (default ON) — session-isolated (v0.13.1)

**v0.13.1 BREAKING (concurrency-safe):** execução NUNCA muta o checkout principal. Cada
`/release:execute` roda numa **worktree de fase própria, com escopo de sessão**, protegida por um
**lock por-fase**. Isso permite N sessões simultâneas no mesmo repo sem colidir HEAD/índice/worktree.

Before T01 runs, the executor (a) acquires a per-phase lock, (b) creates a session-scoped phase
worktree, then spawns `release:wave-executor` with `cwd` pointing at that worktree:

**Inside a `/release:session` worktree (Model B, v0.15.0):** if `.release-planning/.session` exists,
treat this run as `--no-branch` — commit in place on the current `session/<label>` branch and SKIP the
lock + nested phase-worktree block below (the session already isolates this checkout; its `finish`
merges these commits back to base). Spawn `release:wave-executor` with `no_branch: true`, `cwd: .`.
The block below applies only OUTSIDE a session.

```bash
[ -f .release-planning/.session ] && NO_BRANCH=1   # Model B: session worktree → commit in place, skip block
ROOT=$(git rev-parse --show-toplevel)
BRANCH="feat/{NN}-{slug}"
WT_ROOT="$ROOT/../release-worktrees"
LOCK="$WT_ROOT/.locks/{NN}-{slug}.lock"          # shared sibling — visible to ALL sessions
SESSION_ID="$(date +%s)-$$-$RANDOM"               # unique per execute invocation
mkdir -p "$WT_ROOT/.locks"
git worktree prune                                # drop dead registrations first

# --- per-phase lock (Camada 2): prevents two sessions on the SAME phase branch ---
if ! ( set -o noclobber; printf '%s %s\n' "$SESSION_ID" "$(date +%s)" > "$LOCK" ) 2>/dev/null; then
  HOLDER="$WT_ROOT/$(cut -d' ' -f1 "$LOCK" 2>/dev/null)/phase"
  if git worktree list --porcelain | grep -qF "worktree $HOLDER"; then
    echo "ABORT: phase {NN}-{slug} is being executed by another session."
    echo "       Run a different phase, or remove $LOCK if you are sure that session is dead."
    exit 1
  fi
  printf '%s %s\n' "$SESSION_ID" "$(date +%s)" > "$LOCK"   # holder worktree gone → reclaim stale lock
fi
trap 'rm -f "$LOCK"; git worktree remove --force "$WT_ROOT/$SESSION_ID/phase" 2>/dev/null' EXIT

# --- session-scoped phase worktree (Camada 1): main checkout is NEVER touched ---
PHASE_WT="$WT_ROOT/$SESSION_ID/phase"
mkdir -p "$(dirname "$PHASE_WT")"
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git worktree add "$PHASE_WT" "$BRANCH"            # resume: attach existing branch, isolated
else
  git worktree add -b "$BRANCH" "$PHASE_WT" HEAD    # new phase: branch from main's HEAD (read-only on main)
fi

# Record start SHA (inside the worktree) for rollback / diff
git -C "$PHASE_WT" rev-parse HEAD > "$PHASE_WT/.release-planning/phases/{NN}-{slug}/.exec-start-sha"
```

Then spawn the wave-executor handing down the isolation context:

```yaml
agent: release:wave-executor
config:
  cwd: "$PHASE_WT"            # ALL git ops run here — never the shared main checkout
  session_id: "$SESSION_ID"   # namespaces wave worktrees + wave branches across sessions
  branch: "feat/{NN}-{slug}"
  branch_already_set: true    # phase worktree already on the branch → skip its ensure_branch checkout
```

**Rules:**
- New phase → `git worktree add -b feat/{NN}-{slug} $PHASE_WT HEAD` (branch point = main's HEAD commit; uncommitted main edits stay in main, NOT carried in — commit/stash them first if intended).
- `--resume` and branch exists → `git worktree add $PHASE_WT feat/{NN}-{slug}` (attach in isolation) + wave-executor skips tasks already committed (greps `T{NN}` in `git log`).
- Same phase already running in another session → **lock refuses** with a clean message (no silent corruption). Stale lock (holder worktree gone) auto-reclaims.
- `--no-branch` → skip lock + worktree entirely, commit to current branch in the main checkout (legacy, single-session responsibility on the user).
- Fullstack: same branch holds both `--backend` and `--frontend` commits (no split).
- Wave-executor creates short-lived `wave/{SESSION_ID}/w{N}-{TXX}` branches per worktree, deleted after cherry-pick back to phase branch.
- On completion the `trap` releases the lock and removes the phase worktree; the `feat/{NN}-{slug}` branch survives as a normal ref.

**Teardown (run on completion AND on any abort — the `trap` above documents intent, but since
steps run as discrete shell calls you MUST run this explicitly as the final step):**

```bash
git worktree remove --force "$WT_ROOT/$SESSION_ID/phase" 2>/dev/null   # commits already on $BRANCH
git worktree prune
rm -f "$LOCK"                                                          # release the per-phase lock
```

Leave the phase worktree in place ONLY when execution failed mid-wave and you want it for debugging —
then print its path and still release the lock (a held lock on a dead session blocks future runs).

`feat/{NN}-{slug}` is a shared ref after execute — `verify`/push/PR reach it without re-checkout:
`git push -u origin feat/{NN}-{slug}` works from the main checkout regardless of its current branch.
PR is opened from `feat/{NN}-{slug}` after `/release:verify {NN}` PASS.

## Workflow by stack

`/release:execute` ALWAYS spawns `release:wave-executor`. Wave-executor:
1. Parses PLAN (`{NN}-PLAN/manifest.md` wave-split dir, OR legacy `{NN}-PLAN.md`)
2. Auto-derives `parallel_groups` per wave when frontmatter omits them (via `files:` per task disjoint analysis)
3. Slices PLAN per task into worktree-local `PLAN-SLICE.md` (~3KB) to drop redundant context cost
4. Spawns N `release:tdd-executor` concurrently in `git worktree`-isolated branches when disjoint files detected
5. Falls back serial-in-main-tree when files collide (Django graph coherence, migrations, lockfiles)
6. Cherry-picks per-task commits back to `feat/{NN}-{slug}` branch after each wave
7. Verify per-wave (intermediate) + full suite at end-of-phase (terminal wave only)

### backend (stack: django)
- Wave-executor dispatches `release:tdd-executor` per task per worktree
- Per-task: RED → GREEN → REFACTOR (Q1-Q7) → SECURITY (9-category) → RACE (if Q5) → MEMRAY (if Q7)
- Conventional Commits: `test(app):`, `feat(app):`, `refactor(app):`
- Verification per-wave: `ruff`, `makemigrations --check`. Full pytest sweep ONLY after terminal wave.
- Produces: `{NN}-SUMMARY.md` + `{NN}-WAVE-SUMMARY.md`

### frontend (stack: react-tsx)
- Wave-executor dispatches `release:tdd-executor` per task per worktree
- Per-task: RED → GREEN → REFACTOR (RC1-RC7) → SECURITY (9-category)
- Conventional Commits: `test(ui):`, `feat(ui):`, `refactor(ui):`
- Verification per-wave: `tsc --noEmit`, RC6 grep. Full vitest sweep ONLY after terminal wave.
- Produces: `{NN}-SUMMARY.md` + `{NN}-WAVE-SUMMARY.md`

### fullstack
Requires explicit flag. When both plans exist and no flag given:
```
Phase {NN} is fullstack. Two plans found:
  - {NN}-PLAN-BACKEND.md  (Django)
  - {NN}-PLAN-FRONTEND.md (React)

Recommended order:
  1. /release:execute 01 --backend   (API first — frontend needs the endpoint)
  2. /release:execute 01 --frontend  (component second)

Which do you want to execute first?
```

## Verification after execute

After execution completes, suggests:
```
/release:verify {NN}   # goal-backward verification
```

Then:
```
git push -u origin feat/{NN}-{slug}
gh pr create --base main --head feat/{NN}-{slug} --title "feat({NN}): {phase-slug}" \
  --body "$(cat .release-planning/phases/{NN}-{slug}/{NN}-SUMMARY.md)"
```

## Parallel waves (default since v0.12.0)

Wave-executor handles everything — no flag required.

**Wave-split layout (preferred, v0.11.0+):**
- Planner emits `{NN}-PLAN/manifest.md` + `W{X}-*.md` wave files (each 200-600 lines)
- Wave-executor reads manifest DAG, executes waves in topological order
- Parallel-safe waves with disjoint `files_touched` → fan out N worktrees concurrently
- Each spawn receives sliced PLAN (~3KB) instead of monolithic `{NN}-PLAN.md` (100KB+)

**Legacy single-file fallback:**
- Monolithic `{NN}-PLAN.md` > 600 lines → wave-executor REFUSES with error pointing to `/release:plan {NN}` to re-split
- ≤ 600 lines → executes as single wave (still uses 1 worktree + slice-per-task)

**Disjointness rules (collision_detection automatic):**
- Same file in 2+ tasks → serial-in-main-tree (no worktree)
- Migration files in 2+ tasks → serial (numbering collision)
- Lockfiles touched → serial
- Django `models.py` + downstream (`admin/views/serializers/urls/filters.py`) when pre-commit runs `manage.py check` → coalesce_into_wave_commit (graph coherence)
- Otherwise → parallel worktrees

Token economy: serial PLAN re-read per spawn dropped from ~115KB × N spawns to ~3KB × N (-97% input cost).

## Output

```
.release-planning/phases/{NN}-{slug}/
  {NN}-SUMMARY.md       # commits, RC1-RC7/Q1-Q7 evidence, security matrix
```

## Example

```
/release:execute 01

→ Reading PLAN.md frontmatter: stack: react-tsx
→ Routing to release:tdd-executor

→ T01 RED: InvoiceList.test.tsx (8 failing tests)
   vitest: 8 failed ✓ (expected)
   commit a1b2c3: test(ui): add failing tests for InvoiceList

→ T02 GREEN: InvoiceList.tsx + useInvoices.ts
   vitest: 8 passing ✓
   tsc: clean ✓
   commit d4e5f6: feat(ui): implement InvoiceList component

→ T03 REFACTOR: RC1-RC7
   React.memo applied (RC1)
   isLoading/isError states (RC2)
   InvoiceSchema Zod type (RC3)
   aria-labels on action buttons (RC4)
   vitest: 8 passing ✓
   commit g7h8i9: refactor(ui): apply RC1-RC7 to InvoiceList

→ T04 SECURITY: InvoiceList.security.test.tsx
   9 security tests passing ✓
   localStorage: no token usage ✓
   commit j0k1l2: test(ui): add 9-category security tests

→ Final:
   ✓ Full vitest suite: 34/34 pass
   ✓ tsc: clean
   ✓ RC6 grep: no localStorage auth
   ✓ SUMMARY.md written

→ Next: /release:verify 01
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
