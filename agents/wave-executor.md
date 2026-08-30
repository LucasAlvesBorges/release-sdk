---
name: wave-executor
description: Compatibility coordinator for legacy parallel plans. Current workflows use one serial worker in the shared development checkout.
tools: Agent, Read, Write, Edit, Bash, Grep, Glob
model: sonnet
---

<inputs>
- cwd, plan_path, branch, session_id, worker_model
- cfg_root, test_exec_prefix, progress_mirror (optional)
</inputs>

<preconditions>
Return `serial_recommended` whenever the project uses a shared development runner. Never create an
environment to unlock parallelism. Legacy fan-out is allowed only when the caller already supplies
fully independent host-local execution and exact disjoint paths.
</preconditions>

<workflow>
1. Read PLAN once and build the task dependency graph. Refuse cycles/dangling IDs.
2. Compute ready tasks. Unknown file footprints, migrations sharing an app, lockfiles and overlapping
   files collide and run alone.
3. For each ready disjoint task, create an isolated worktree/branch and a compact task slice containing
   only its action, files, acceptance, verification, relevant decisions and risks. Pass the caller's
   exact host-local prefix; never allocate slots or call environment lifecycle commands.
4. Spawn one `release:tdd-executor` per active task with explicit cwd/ownership/task_filter. Respect
   session concurrency.
5. Harvest completions, verify commits exist, and cherry-pick serially in dependency order onto the
   phase branch. Never parallelize cherry-picks.
6. Remove a task worktree only after its commit lands. On conflict, retain evidence/worktree. The
   coordinator never provisions or tears down Docker, databases or other test environments.
7. Continue until all tasks land. The parent runs the single broad cached gate and checker.
8. Write a compact WAVE-SUMMARY only when parallel execution actually occurred.
</workflow>

<rules>
- No intermediate broad tests and no terminal test-discover/test-runner fleet.
- Focused task tests belong to workers; the one final suite belongs to parent execute.
- Do not reread parent PLAN after slices are created.
- Do not fan out one agent per file or artificial RED/GREEN task.
- Preserve phase lock, planning artifacts and no-clobber semantics.
</rules>
