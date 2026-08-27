# Session operations

Read only the selected subcommand.

## Shared resolution

Set `MAIN_ROOT` from the first entry of `git worktree list --porcelain`. Session directory is `$MAIN_ROOT/../release-worktrees/sessions`; branch is `session/<label>`. Resolve the merge library as `${CLAUDE_PLUGIN_ROOT}/bin/release-merge-lib.sh`, falling back to `$MAIN_ROOT/bin/release-merge-lib.sh` only in a source checkout, then source it. Use its `release_read_base`, `release_sync_base_into`, and `land_branch` functions. Prefer the base recorded in the session marker so a later branch switch does not change its integration target.

## base [branch]

With no argument, show the resolved base. With a branch, verify the local ref exists and is not `session/*`; create `.release-planning/` if needed, write the name to `MAIN_ROOT/.release-planning/base-branch`, and force-add only that file. Explain that a blanket `.release-planning/` ignore must become `.release-planning/*` plus `!.release-planning/base-branch` for persistence. Do not commit unless the caller requested it.

## start <label> [--base]

Validate the label, base ref, and uniqueness of both branch and target path. Run `git worktree prune`, create the parent directory, then `git worktree add -b session/<label> <path> <base>`. Create `<path>/.release-planning/.session` with `label`, `base`, and timestamp. Ensure `.release-planning/.session`, `.release-planning/STATE.md`, and `.release-planning/active-workstream` are ignored in that worktree. Do not switch the caller's worktree. Return the path and command for opening a separate Claude Code or Codex session there.

## sync [label]

Resolve the worktree, marker base, and branch. Require no tracked changes. Call `release_sync_base_into <worktree> <base>` and map `0` to synced, `2` to code conflict, `3` to untracked-file/refused collision, and anything else to error. On conflict the library aborts the merge; tell the author to resolve/commit in the session and retry. Planning-only conflicts are removed by the library.

## finish [label] [--keep|--pr]

Validate marker, worktree, branch, base, and clean tracked state. For `--pr`, call `release_sync_base_into`, push `session/<label>` to origin, and use `gh pr create --base <base> --head <branch>` (or report an existing PR); keep worktree/branch.

For local finish call `land_branch <branch> <worktree> <base> [--keep]` and use the terminal result exactly:

- `merged`: landed; default cleanup completed.
- `conflict` or `refused`: session kept; resolve there and retry.
- `held-dirty`: base checkout preserved; commit/stash it and use `/release:land` or retry.
- `locked`: another integration is running; retry later.
- `planningblock`: untrack base planning except `base-branch` first.
- `baseadvanced`: base stayed clean; retry so it re-syncs.
- `badbase` or `error`: correct configuration/scope.

Do not manually merge around the library.

## list

Enumerate worktrees under `/sessions/`. For each valid `session/<label>` ref, show marker base, ahead/behind counts from `git rev-list --left-right --count <base>...<branch>`, tracked dirty status, last commit, and an open PR number when `gh` is available. Do not fetch or mutate.

## doctor

Check that: the resolved base exists and is not a session branch; only `.release-planning/base-branch` is tracked under planning; that file is tracked/persistable; every marker points to an existing branch/base; worktree paths and refs agree; sessions with tracked changes are called out; and behind counts recommend sync. Diagnose only.

## cleanup

For each session, remove it only if its branch is an ancestor of its recorded base and the worktree has no tracked changes. Change cwd to MAIN_ROOT, remove the worktree, delete the proven-merged branch, then prune. Keep dirty or unmerged sessions and report why. This is the normal cleanup after a merged PR.

## abort <label>

Show the exact worktree, branch, ahead count, and dirty/untracked status. Require explicit confirmation that unmerged commits and files will be lost. Then change cwd to MAIN_ROOT, force-remove only that resolved worktree, delete only `session/<label>`, and prune. Never accept an empty, globbed, root, home, or unresolved target.
