---
description: >
  Context-aware phase executor. Detects backend/frontend phase type from PLAN.md, routes to
  release-tdd-executor (stack-dispatched). Supports --backend/--frontend flags for fullstack phases.
  TDD-strict: RED → GREEN → REFACTOR → SECURITY. Atomic per-task commits.
  Use when: PLAN.md is ready (plan-checker PASS or WARN-accepted).
allowed_tools: Agent, Read, Write, Edit, Bash, Grep, Glob
---

# /release:execute — Context-Aware Phase Executor

Detects plan type and routes to the correct TDD executor.

## Usage

```
/release:execute 01                  # auto-detect, branch-per-phase, execute
/release:execute 01 --backend        # force Django executor
/release:execute 01 --frontend       # force React executor
/release:execute 01 --resume         # resume from last completed task (reuses existing branch)
/release:execute 01 --dry-run        # preview without committing
/release:execute 01 --gaps           # execute gap-closure plan
/release:execute 01 --no-branch      # disable branch-per-phase (commit to current branch)
/release:execute 01 --waves          # parallel wave executor (worktree-isolated)
```

## Detection logic

1. Read `.planning/phases/{NN}-{slug}/{NN}-PLAN.md` frontmatter.
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
git rev-parse HEAD > .planning/phases/{NN}-{slug}/.exec-start-sha
```

**Rules:**
- New phase + clean tree → `git checkout -b feat/{NN}-{slug}` from current HEAD
- New phase + dirty tree → ABORT (instruct user to commit/stash)
- `--resume` and branch exists → `git checkout feat/{NN}-{slug}`
- `--no-branch` → skip branch creation, commit to current branch (legacy behavior)
- Fullstack: same branch holds both `--backend` and `--frontend` commits (no split)

PR is opened from `feat/{NN}-{slug}` after `/release:verify {NN}` PASS.

## Workflow by stack

### backend (stack: django)
Delegates entirely to `/django:execute` workflow:
- Spawns `release-tdd-executor`
- RED → GREEN → REFACTOR → SECURITY (9-category) → RACE (if Q5) → MEMRAY (if Q7)
- Conventional Commits: `test(app):`, `feat(app):`, `refactor(app):`
- Verification: `pytest`, `ruff`, `makemigrations --check`
- Produces: `{NN}-SUMMARY.md`

### frontend (stack: react-tsx)
Delegates entirely to release-tdd-executor:
- Spawns `release-tdd-executor`
- RED → GREEN → REFACTOR → SECURITY (9-category)
- Conventional Commits: `test(ui):`, `feat(ui):`, `refactor(ui):`
- Verification: `vitest run`, `tsc --noEmit`
- Produces: `{NN}-SUMMARY.md`

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
  --body "$(cat .planning/phases/{NN}-{slug}/{NN}-SUMMARY.md)"
```

## Parallel waves (--waves)

When `--waves` flag passed, executor delegates to `release-wave-executor` agent:
- Reads `wave_X` blocks from PLAN.md frontmatter
- Tasks inside a wave run in parallel via `git worktree` isolation
- Each parallel task gets `../worktrees/{NN}-{slug}-w{wave}-t{task}` working dir
- After wave finishes, commits cherry-picked back to `feat/{NN}-{slug}` branch
- Next wave starts from merged state

Safe only when wave tasks touch disjoint file sets. Wave executor verifies file disjointness before parallel spawn — falls back to serial if overlap detected.

## Output

```
.planning/phases/{NN}-{slug}/
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

This skill spawns merged `release-*` agents. Stack is inferred from `.planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
