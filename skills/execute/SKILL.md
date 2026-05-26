---
name: execute
description: >
  Context-aware phase executor (v0.12.0 BREAKING — waves-by-default). Detects backend/frontend
  phase type from PLAN, ALWAYS spawns release-wave-executor which fans out N release-tdd-executor
  in worktree-isolated parallel branches per disjoint task group. TDD-strict per task:
  RED → GREEN → REFACTOR → SECURITY. Atomic Conventional commits cherry-picked back to phase branch.
  Use when: PLAN ready (plan-checker PASS or WARN-accepted).
---

# /release:execute — Context-Aware Phase Executor (waves-by-default)

**v0.12.0 BREAKING**: Always routes through `release-wave-executor`. Legacy direct `release-tdd-executor`
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

## Branch-per-phase (default ON)

Before T01 runs, executor isolates work on a dedicated branch:

```bash
BRANCH="feat/{NN}-{slug}"

# Resume case: branch exists → checkout
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git checkout "$BRANCH"
else
  # New phase: branch from current HEAD (must be clean)
  git diff --quiet || { echo "Working tree dirty — commit or stash"; exit 1; }
  git checkout -b "$BRANCH"
fi

# Record start SHA for rollback / diff
git rev-parse HEAD > .release-planning/phases/{NN}-{slug}/.exec-start-sha
```

**Rules:**
- New phase + clean tree → `git checkout -b feat/{NN}-{slug}` from current HEAD
- New phase + dirty tree → ABORT (instruct user to commit/stash)
- `--resume` and branch exists → `git checkout feat/{NN}-{slug}` + wave-executor skips tasks already committed (greps `T{NN}` in `git log`)
- `--no-branch` → skip branch creation, commit to current branch (legacy behavior)
- Fullstack: same branch holds both `--backend` and `--frontend` commits (no split)
- Wave-executor creates short-lived `wave/{NN}-{TXX}` branches per worktree, deleted after cherry-pick back to phase branch

PR is opened from `feat/{NN}-{slug}` after `/release:verify {NN}` PASS.

## Workflow by stack

`/release:execute` ALWAYS spawns `release-wave-executor`. Wave-executor:
1. Parses PLAN (`{NN}-PLAN/manifest.md` wave-split dir, OR legacy `{NN}-PLAN.md`)
2. Auto-derives `parallel_groups` per wave when frontmatter omits them (via `files:` per task disjoint analysis)
3. Slices PLAN per task into worktree-local `PLAN-SLICE.md` (~3KB) to drop redundant context cost
4. Spawns N `release-tdd-executor` concurrently in `git worktree`-isolated branches when disjoint files detected
5. Falls back serial-in-main-tree when files collide (Django graph coherence, migrations, lockfiles)
6. Cherry-picks per-task commits back to `feat/{NN}-{slug}` branch after each wave
7. Verify per-wave (intermediate) + full suite at end-of-phase (terminal wave only)

### backend (stack: django)
- Wave-executor dispatches `release-tdd-executor` per task per worktree
- Per-task: RED → GREEN → REFACTOR (Q1-Q7) → SECURITY (9-category) → RACE (if Q5) → MEMRAY (if Q7)
- Conventional Commits: `test(app):`, `feat(app):`, `refactor(app):`
- Verification per-wave: `ruff`, `makemigrations --check`. Full pytest sweep ONLY after terminal wave.
- Produces: `{NN}-SUMMARY.md` + `{NN}-WAVE-SUMMARY.md`

### frontend (stack: react-tsx)
- Wave-executor dispatches `release-tdd-executor` per task per worktree
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
→ Routing to release-tdd-executor

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
