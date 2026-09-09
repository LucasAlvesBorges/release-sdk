---
name: gc
description: >
  Prune what quick/execute/land left behind: worktrees whose branch already landed on base and
  whose tree is clean, registered worktrees whose directory vanished, merged local branches checked
  out nowhere, and merge locks whose holder is dead. Dry run by default; --apply performs it. Never
  touches dirty, unmerged, external (Codex/tmp) or protected units. Trigger words: "gc", "limpa
  worktrees", "prune branches", "cleanup stale", "worktree list is huge".
---

# /release:gc — prune merged units, keep everything else

## Usage

```text
/release:gc                 # dry run: one verdict line per worktree/branch/lock
/release:gc --apply         # prune every PRUNE-* / STALE-LOCK item
/release:gc --base <branch> # judge against another trunk (default: base-branch file, else current branch)
```

## Flow

```bash
find_lib(){ local p="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/$1}"; [ -n "$p" ]&&[ -f "$p" ]&&{ printf %s "$p"; return; }; find "$HOME/.claude" -name "$1" -path '*/bin/*' 2>/dev/null|head -1; }
. "$(find_lib release-merge-lib.sh)"; . "$(find_lib release-gc-lib.sh)"
MAIN_ROOT="$(release_main_root)"; BASE="${BASE_ARG:-$(release_read_base)}"
gc_scan "$MAIN_ROOT" "$BASE"            # dry run
# --apply:
gc_apply "$MAIN_ROOT" "$BASE"           # ends with GC_SUMMARY worktrees=N branches=N locks=N kept=N
```

Print the scan grouped: **will prune** (PRUNE-WORKTREE / PRUNE-MISSING / PRUNE-BRANCH / STALE-LOCK)
then **kept** with the reason (KEEP-DIRTY, KEEP-UNMERGED, KEEP-EXTERNAL, KEEP-LIVE-LOCK, KEEP-BASE,
KEEP-MAIN). Without `--apply`, end with the exact command to apply. With `--apply`, end with the
`GC_SUMMARY` line and the kept reasons that still need a human (dirty or unmerged units).

## Rules

- Prunable means provably safe: branch is an ancestor of base AND the working tree has no tracked
  change and no untracked file. A `locked` worktree is unlocked first; the lock was the SDK's guard
  against `git worktree prune` mid-run, not a keep signal.
- Never removes worktrees registered outside `<main_root>/..` (Codex, /tmp). Never deletes
  `main`/`master`/`dev`/`develop`/`trunk` or the base. Never runs `git branch -D` on unmerged work.
- Runs from `MAIN_ROOT`, so it is safe to call from inside a worktree that is about to be removed.
- The SessionStart hook prints a one-line hint when the cheap upper bound reaches 3; it never applies.
