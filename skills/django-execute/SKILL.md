---
description: >
  Execute a planned Django phase TDD-strict. Reads .planning/phases/{NN}-{slug}/{NN}-PLAN.md, runs
  RED → GREEN → REFACTOR per task, atomic per-task commits with Conventional Commits format,
  .delay_on_commit() enforcement, migration generation. Produces SUMMARY.md with commit hashes + Q1-Q7 evidence.
  Use when: PLAN.md is ready (plan-checker PASS or WARN-accepted), implementing the phase.
allowed_tools: Agent, Read, Write, Edit, Bash, Grep, Glob
---

# /django:execute — TDD-Strict Phase Execution

Executes a Django phase PLAN.md task-by-task with strict RED → GREEN → REFACTOR ordering. Atomic per-task commits.

## Usage

```
/django:execute 01                       # execute phase 01 from PLAN.md
/django:execute 01 --resume              # resume from last completed task (per STATE.md cursor)
/django:execute 01 --dry-run             # show what would be executed
/django:execute 01 --gaps                # execute gap-closure plan (after /django:plan 01 --gaps)
/django:execute 01 --waves               # parallel wave executor (worktree-isolated)
/django:execute 01 --no-branch           # commit to current branch (no feat/{NN}-{slug})
```

## Arguments

- `$ARGUMENTS` — phase number (required)
- `--resume` — skip already-completed tasks (verified via git log)
- `--dry-run` — preview without committing
- `--gaps` — gap-closure execution

## Prerequisites

- `.planning/phases/{NN}-{slug}/{NN}-PLAN.md` exists
- `{NN}-PLAN-CHECK.md` verdict is PASS or WARN (not BLOCK)
- Working tree clean (or `--allow-dirty` flag)

## Workflow

1. Read `.planning/phases/{NN}-{slug}/{NN}-PLAN.md`
2. Read `.planning/PROJECT.md` (LOCK-XX) + `./CLAUDE.md`
3. If `--resume`: check `.planning/STATE.md` cursor for last completed task
4. Branch setup: checkout `feat/{NN}-{slug}` (create if missing, reuse if `--resume`)
5. If `--waves`: spawn `release-wave-executor` (parallel via git worktree)
   Else: spawn `release-tdd-executor` with `<plan_path>` config (serial)
6. Executor for each task in wave order:
   - **RED phase** (if `type: tdd-red`):
     - Write failing test file
     - Run pytest, confirm RED
     - Commit: `test({scope}): {task title}`
   - **GREEN phase** (if `type: tdd-green`):
     - Read existing files, Edit/Write implementation
     - Run `makemigrations` if model changed
     - Run pytest, confirm GREEN
     - Commit migration separately, then impl: `feat({scope}): {task title}`
   - **REFACTOR phase** (if Q1-Q7 non-N/A):
     - Apply Q1-Q7 optimizations per task author_checklist
     - Run pytest (must still pass)
     - Commit: `refactor({scope}): apply Q1-Q7 to {task title}`
   - **SECURITY task:** Write 9-category test file, commit `test({scope}): add 9-category security tests`
   - **RACE / MEMRAY tasks** (conditional): write threading / memory tests, commit
7. Apply deviation rules (auto-fix Rule 1/2/3, escalate beyond):
   - Rule 1: Missing critical functionality not in plan → add inline, track
   - Rule 2: CLAUDE.md violation in plan → apply CLAUDE.md, track
   - Rule 3: Trivial fix in touched file → fix in same commit, track
8. After all tasks:
   - Full app test suite
   - `makemigrations --check --dry-run`
   - `ruff check`
   - Q6 enforcement grep
9. Write `{NN}-SUMMARY.md` with:
   - Tasks completed (commit hashes)
   - Author Checklist Q1-Q7 evidence table
   - Threat flags (new attack surface)
   - Deviations (Rule 1/2/3 applied)
   - Verification results
10. Final metadata commit: `docs({NN}): complete {slug} phase`
11. Update STATE.md cursor: `active_stage: execute-complete` OR mark blocker if any task failed

## Verification suite (runs automatically)

After every task commit:
- `pytest <test_file>` — must pass
- `ruff check <file>` — must be clean

After all tasks:
- Full app test suite: `pytest backend/apps/{app}/tests/ -q`
- `makemigrations --check --dry-run` — must exit 0
- `grep -rn '\.delay(' backend/apps/{app}/ | grep -v tests/` — must be empty (Q6 LOCKED)
- `ruff format --check` — must be clean

## Deviation rules (auto-applied, tracked in SUMMARY.md)

| Rule | Trigger | Action |
|------|---------|--------|
| 1 | Plan missing critical functionality (e.g., validator required by D-XX but not in task action) | Add inline, track as `[Rule 1 - Auto-add]` |
| 2 | CLAUDE.md violation in plan (e.g., plan says `fields = '__all__'` but CLAUDE.md forbids) | Apply CLAUDE.md, track as `[Rule 2 - CLAUDE.md]` |
| 3 | Trivial fix discovered in touched file (typo, lint error in adjacent line) | Fix in same commit, track as `[Rule 3 - Trivial]` |

Beyond Rule 1-3 → checkpoint, escalate to user.

## Output

```
.planning/phases/{NN}-{slug}/
  {NN}-SUMMARY.md           # this skill's output
```

Plus per-task atomic commits in git log:
```
abc1234 docs(01): complete veiculo-bulk-import phase
def5678 test(frota): add memray test for bulk import
ghi9012 test(frota): add race test (N/A this phase)
jkl3456 test(frota): add 9-category security tests
mno7890 refactor(frota): apply Q1-Q7 to bulk import view
pqr1234 feat(frota): implement bulk import view + serializer
stu5678 feat(frota): add Veiculo bulk-import endpoint
vwx9012 test(frota): add failing tests for bulk import
```

## Example

```
/django:execute 01

→ Reading PLAN.md (7 tasks, wave structure: 0 → 1 → 2 → 3)
→ Reading PROJECT.md (LOCK-01 to LOCK-10)

→ Spawning release-tdd-executor...

→ T01 RED: tests/test_bulk_import.py (failing 5 tests)
   pytest: 5 failed ✓ (expected)
   commit a1b2c3: test(frota): add failing tests for bulk import

→ T02 GREEN: models.py + migration
   makemigrations: 0023_veiculo_csv_status.py
   pytest: 5 still failing (expected — endpoint not wired)
   commit d4e5f6: feat(frota): add Veiculo csv status field

→ T03 GREEN: serializers.py + views.py + urls.py
   pytest: 5 passing ✓
   commit g7h8i9: feat(frota): implement bulk import view

→ T04 REFACTOR: apply Q1, Q3, Q7
   pytest: 5 still passing ✓
   commit j0k1l2: refactor(frota): apply Q1-Q7 to bulk import

→ T05 SECURITY: tests/test_bulk_import_security.py (9 tests)
   pytest: 9 passing ✓
   commit m3n4o5: test(frota): add 9-category security tests

→ T07 MEMRAY (Q7 active): tests/test_bulk_import_memray.py
   pytest --memray: under 50MB ✓
   commit p6q7r8: test(frota): add memray test for bulk import

→ Final verification:
   ✓ Full app tests: 142/142 pass
   ✓ makemigrations --check clean
   ✓ ruff clean
   ✓ Q6: no .delay() in production code

→ Wrote SUMMARY.md
→ commit s9t0u1: docs(01): complete veiculo-bulk-import phase

→ Next: /django:verify 01
```


---

## Stack dispatch

This skill spawns merged `release-*` agents (one agent per role, dispatched internally by `stack`). All agent spawns from this skill pass `stack: django` as input. The agents apply Django-stack rules from their `<django-stack>` blocks.
