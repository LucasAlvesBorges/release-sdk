---
name: session
description: Worktree-native parallel sessions with serialized, conflict-safe, code-only merge-back. Load only the selected subcommand procedure.
---

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
