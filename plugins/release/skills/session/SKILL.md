---
name: session
description: Worktree-native parallel sessions with serialized, conflict-safe, code-only merge-back. Load only the selected subcommand procedure.
---

## Codex runtime contract

This generated Codex skill preserves the source workflow with these overrides:

- Use current Codex tools: targeted reads, `rg`, `apply_patch`, and shell commands. Never look for
  Claude-only tool names or runtime state (`~/.claude`, `.claude*`, `CLAUDE.md`). Release artifacts
  stay in `.release-planning/`; project guidance comes from the applicable `AGENTS.md` chain.
- Before a write, a root `AGENTS.md` must exist. The hook returns `AGENTS_MD_REQUIRED`; in bootstrap
  mode only `release-agents-md-builder` may draft it, after which the user reruns the task.
- Score C0-C4 and apply risk floors before spawning. Default is no child. Spawn only when a bounded
  independent/specialist/noisy subtask avoids more context than it costs. C0/C1 stays inline; C2 uses
  at most one normal worker/planner; C3/C4 may use the strict fleet with disjoint ownership.
- Map source `release:<name>` agents to Codex `release-<name>` custom agents. Pass paths and task
  deltas, never the transcript, copied files, full logs, or `AGENTS.md` contents. Writers preserve
  concurrent work and own non-overlapping paths.
- Custom agents already pin their model/effort. Ignore Claude model names and `CLAUDE_EFFORT`; do not
  increase effort unless the C3/C4 risk actually requires it.
- A child returns compact `SubagentResultV1`; the parent decides completion. User input stays in the
  parent. Retry once at most, then narrow/stop instead of grinding.

`/release:<name>` is the source workflow label; in Codex select the corresponding release skill.

# `/release:session`

Each parallel unit is an ephemeral worktree on `session/<label>`, rooted at `../release-worktrees/sessions/<label>`, and returns to one base branch through `bin/release-merge-lib.sh`.

```text
/release:session start <label> [--base <branch>]
/release:session sync [label]
/release:session finish [label] [--keep|--pr]
/release:session list
/release:session doctor
/release:session cleanup
/release:session abort <label>
/release:session base [branch]
```

Labels match `^[a-z][a-z0-9-]{1,39}$`. Resolve `MAIN_ROOT` as the first `worktree` entry from `git worktree list --porcelain`, even when invoked inside a session. Resolve a missing label from `.release-planning/.session`. Base precedence is explicit `--base`, the session marker, `MAIN_ROOT/.release-planning/base-branch`, then MAIN_ROOT's current branch; a base matching `session/*` is invalid.

Before acting, read only the matching section of `references/operations.md`. For merge behavior, source the shipped `bin/release-merge-lib.sh`; never reproduce its locking or conflict algorithm in the prompt.

## Invariants

- A dirty session blocks sync/finish. A dirty live base is preserved and yields `held-dirty`.
- Base is merged into the session first. Code conflicts stop in that worktree; base remains untouched.
- `.release-planning/` is stripped from integration except the force-tracked `base-branch`. If base tracks other planning files, stop with `planningblock`.
- Local finish calls `land_branch` and honors its exact result. `--pr` syncs first, then pushes the code-only branch and keeps the worktree.
- Finish/cleanup/abort change cwd to `MAIN_ROOT` before removing any worktree. Branch deletion follows an ancestor-of-base proof; abort is the only destructive exception and requires confirmation.
- Skills invoked inside a marker-bearing session commit in place; they never create a nested session worktree.

Report the command outcome, relevant path/branch/base, and the next action only.
