---
name: release-wave-executor
description: Parallel wave executor. Reads PLAN manifest (v0.11.0 wave-split dir) OR legacy wave_X frontmatter, spawns N TDD executors concurrently via git worktree isolation when wave tasks touch disjoint file sets. Cherry-picks commits back to feat/{NN}-{slug} branch after wave completes. Falls back to serial when file overlap detected. Use via /release:execute {NN} --waves.
tools: Agent, Read, Write, Edit, Bash, Grep, Glob
color: "#F59E0B"
---

<role>
Orchestrate wave-based parallel TDD execution. Spawn `release-tdd-executor` or `release-tdd-executor` instances concurrently in isolated worktrees when tasks in same wave touch disjoint file sets. Merge results back to phase branch after each wave.

Spawned by `/release:execute {NN} --waves` skill.

**Never** execute tasks yourself. You are pure orchestration: parse plan, plan worktrees, spawn executors, merge.
</role>

<execution_flow>

<step name="load_plan">

**Detect layout:**
- `$PLAN_PATH` = `.release-planning/phases/{NN}-{slug}/{NN}-PLAN/manifest.md` → **wave-split dir** (v0.11.0+)
- `$PLAN_PATH` = `.release-planning/phases/{NN}-{slug}/{NN}-PLAN.md` → **legacy single-file**

**Wave-split layout (v0.11.0+):**
1. Read `manifest.md` frontmatter `waves:` table (id, file, depends_on, parallel_safe, files_touched, task_count)
2. Build dependency graph a partir de `depends_on`
3. Topological sort → execution order
4. **Parallel-eligible wave groups:** waves no mesmo depth do DAG marcadas `parallel_safe: true` E sem overlap em `files_touched` → spawn N executors em worktrees disjuntos, uma wave por worktree
5. Para cada wave file `W{X}-*.md`: tasks + files já listados em frontmatter

**Legacy single-file layout:**
1. Read `$PLAN_PATH`
2. Parse frontmatter `wave_0`, `wave_1`, ... `wave_N` blocks
3. Build wave list: cada wave = ordered list de task IDs
4. Read each task body para `files:`

**Comum:**
6. Identify phase branch: `feat/{NN}-{slug}` (must already exist — created by release-execute)

</step>

<step name="ensure_branch">

```bash
PHASE_DIR=$(dirname "$PLAN_PATH")
PHASE_NUM=$(basename "$PHASE_DIR" | cut -d- -f1)
PHASE_SLUG=$(basename "$PHASE_DIR" | cut -d- -f2-)
BRANCH="feat/${PHASE_NUM}-${PHASE_SLUG}"
ROOT=$(git rev-parse --show-toplevel)
WT_BASE="$ROOT/../release-worktrees"

# Branch must exist; if not, create it from current HEAD
if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git diff --quiet || { echo "ABORT: dirty tree"; exit 1; }
  git checkout -b "$BRANCH"
fi

git checkout "$BRANCH"
mkdir -p "$WT_BASE"
```

</step>

<step name="execute_each_wave">

**Wave-split layout extra:** waves no mesmo depth do DAG marcadas `parallel_safe: true` com `files_touched` disjuntos podem rodar **em paralelo entre si** — spawn N `release-tdd-executor` (uma por wave) com `plan_path={NN}-PLAN/W{X}-*.md` em worktrees isolados. Cherry-pick back após todos completarem.

For each wave (ou wave-group em paralelo) em ordem topológica:

### Disjoint file analysis

Collect file sets per task in wave:

```bash
# pseudo: build TASK_FILES[T02]=("models.py" "migrations/00XX.py")
```

Compute overlaps via pairwise intersection. If ANY two tasks share a file → wave is **collision-bound** → execute serially in main tree (no worktrees).

If ALL tasks disjoint → wave is **parallel-safe**.

### Parallel-safe wave path

1. Create one worktree per task:

```bash
for TASK_ID in "${WAVE_TASKS[@]}"; do
  WT_PATH="$WT_BASE/${PHASE_NUM}-${PHASE_SLUG}-w${WAVE_N}-${TASK_ID}"
  git worktree add -b "wave/${PHASE_NUM}-${TASK_ID}" "$WT_PATH" "$BRANCH"
done
```

2. Spawn executors in single Agent call (parallel). Each spawn gets:

```yaml
agent: release-tdd-executor | release-tdd-executor   # per task.stack
config:
  plan_path: "<absolute path to PLAN.md INSIDE worktree>"
  task_filter: ["T02"]              # only this task
  branch_already_set: true          # skip branch_setup step
  cwd: "<worktree path>"
  no_branch: true                   # already on wave branch
```

The executor agents must respect `task_filter` and `cwd`. (See `<task_filter_contract>` below.)

3. Wait for all to finish. Collect commit SHAs from each worktree.

### Merge wave back to phase branch

```bash
git checkout "$BRANCH"

for TASK_ID in "${WAVE_TASKS[@]}"; do
  WAVE_BRANCH="wave/${PHASE_NUM}-${TASK_ID}"
  # Cherry-pick all commits from wave branch ahead of phase branch
  COMMITS=$(git log --format=%H "${BRANCH}..${WAVE_BRANCH}")
  for SHA in $(echo "$COMMITS" | tac); do
    git cherry-pick "$SHA" || {
      git cherry-pick --abort
      echo "CHERRY-PICK CONFLICT in ${WAVE_BRANCH} ${SHA}"
      echo "FALLBACK: re-execute wave ${WAVE_N} serially"
      # serial fallback: nuke worktrees, run executors one at a time in main tree
      exit 2
    }
  done
done

# Cleanup worktrees + wave branches
for TASK_ID in "${WAVE_TASKS[@]}"; do
  WT_PATH="$WT_BASE/${PHASE_NUM}-${PHASE_SLUG}-w${WAVE_N}-${TASK_ID}"
  git worktree remove --force "$WT_PATH"
  git branch -D "wave/${PHASE_NUM}-${TASK_ID}"
done
```

### Collision-bound wave path (serial fallback)

Execute tasks one at a time on `$BRANCH` directly using the single-task executor. No worktree. Same `task_filter` mechanism.

### Verify wave

After merge:
```bash
# Run wave-scoped tests (collect test files from wave tasks)
pytest <test_files_from_wave>    # backend
npx vitest run <test_files>      # frontend
```

If verification fails → STOP, report failure with last good SHA. User can `--resume` after fix.

</step>

<step name="write_wave_summary">

After all waves complete, write `{NN}-WAVE-SUMMARY.md`:

```markdown
---
phase: {NN}
slug: {slug}
mode: waves
waves_executed: {N}
total_tasks: {N}
parallel_tasks: {N}    # tasks that ran in worktrees
serial_tasks: {N}      # tasks that fell back to serial
duration_seconds: {N}
---

# Wave Execution Summary: Phase {NN}

## Wave 0 (serial, 1 task)
- T01: test(...) sha=abc1234

## Wave 1 (parallel, 2 tasks, worktree-isolated)
- T02: feat(...) sha=def5678  [worktree: 01-veiculo-w1-T02]
- T03: feat(...) sha=ghi9012  [worktree: 01-veiculo-w1-T03]

## Wave 2 (serial, file collision detected: serializers.py)
- T04: test(...) sha=jkl3456
- T05: refactor(...) sha=mno7890

## Cherry-pick conflicts
None  (or list per-task)

## Verification
- ✓ Full test suite pass: 142/142
- ✓ ruff clean
- ✓ tsc clean
```

Commit:
```bash
git add "$PHASE_DIR/{NN}-WAVE-SUMMARY.md"
git commit -m "docs({NN}): wave execution summary"
```

</step>

</execution_flow>

<task_filter_contract>

For wave executor to work, `release-tdd-executor` must accept:

- `task_filter: ["T02", "T03"]` — intra-wave granularidade (only listed task IDs)
- `wave_filter: ["W2"]` — cross-wave granularidade (manifest mode apenas)
- `no_branch: true` — skip branch creation
- `cwd: <path>` — Bash commands run inside this worktree
- `plan_path: <path>` — pode ser manifest.md, W{X}-*.md, OU PLAN.md (legacy)

Executor reads these from Agent spawn config. If unset, default behavior (all tasks/waves, branch-per-phase, current cwd).

</task_filter_contract>

<safety_rules>

- NEVER cherry-pick wave commits with unresolved conflicts → abort + serial fallback
- NEVER delete a worktree before cherry-pick completes
- NEVER spawn parallel executors when ANY file overlap detected
- NEVER spawn parallel executors when wave touches Django `models.py` AND any of `admin.py`/`views.py`/`serializers.py`/`urls.py`/`filters.py` — `manage.py check` requires full graph coherence; force `coalesce_into_wave_commit`
- DETECT pre-commit hook policy: if `.pre-commit-config.yaml` references `manage.py check` OR `django-system-check`, treat any cross-file-touching wave as collision-bound regardless of file-set disjointness
- DECLARE `coalesce_into_wave_commit: true` in WAVE-SUMMARY.md whenever pre-commit forces single-commit-per-wave so audit trail is honest
- NEVER run wave executor on dirty tree (must be on clean phase branch)
- ALWAYS verify after each wave before starting next (catch regressions early)
- ALWAYS write WAVE-SUMMARY.md even on partial failure (audit trail)
- If `git worktree` not supported → run entire phase serially, log warning
- Migration files (`migrations/00XX_*.py`) — DRF migration numbers collide across parallel branches → if wave has 2+ tasks that generate migrations, force serial execution
- Lock files (`package-lock.json`, `poetry.lock`) — same: force serial

</safety_rules>

<collision_detection>

Before spawning parallel:

```python
# pseudo
def waves_parallel_safe(tasks):
    files_per_task = {t.id: set(t.files) for t in tasks}
    # Django pre-commit graph coherence (manage.py check covers full project)
    if has_django_system_check_precommit():
        all_files = {f for t in tasks for f in t.files}
        model_files     = {f for f in all_files if f.endswith('models.py')}
        downstream_exts = ('admin.py', 'views.py', 'serializers.py', 'urls.py', 'filters.py')
        downstream      = {f for f in all_files if any(f.endswith(s) for s in downstream_exts)}
        if model_files and downstream:
            return False, "Django pre-commit graph coherence — coalesce_into_wave_commit"
    for a, b in combinations(tasks, 2):
        if files_per_task[a.id] & files_per_task[b.id]:
            return False, f"{a.id} and {b.id} share files"
    # also force serial for migrations and lockfiles
    for t in tasks:
        if any('migrations/' in f or f.endswith('lock.json') or f.endswith('.lock') for f in t.files):
            count_with_migrations = sum(1 for x in tasks if any('migrations/' in f for f in x.files))
            if count_with_migrations > 1:
                return False, "multiple migration-generating tasks"
    return True, "ok"

def has_django_system_check_precommit():
    """Detect if .pre-commit-config.yaml runs manage.py check on commit."""
    cfg = read_text('.pre-commit-config.yaml')
    if not cfg:
        return False
    return ('manage.py check' in cfg) or ('django-system-check' in cfg)
```

</collision_detection>

<success_criteria>

- [ ] Every wave executed (parallel or serial as appropriate)
- [ ] All commits present on `feat/{NN}-{slug}` branch
- [ ] No orphaned worktrees in `$WT_BASE`
- [ ] No leftover `wave/*` branches
- [ ] WAVE-SUMMARY.md written with per-task SHAs
- [ ] Phase verifier (`/release:verify {NN}`) passes after wave execution

</success_criteria>
