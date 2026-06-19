---
name: land
description: >
  Land a held / conflicted / --no-merge unit of work back onto base — the retry path for the auto
  merge-back that /release:quick and /release:execute perform on green. Use when a quick or a phase was
  HELD (the base checkout was dirty at land time, so it was never clobbered) or you ran with --no-merge,
  and now you want it on your trunk. Serialized + conflict-safe via the shared land_branch engine.
  Trigger words: "land", "aterrissa", "merge back the quick/phase", "finish the held merge".
---

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. This skill spawns no agents; it runs the shared
merge-back engine directly.

---

# /release:land — finish a deferred merge-back

`/release:quick` and `/release:execute` auto-land on green. When the base checkout was **dirty**, the
land is **held** (your uncommitted work is never clobbered); with `--no-merge` it is skipped on
purpose. `/release:land` is the retry: it lands the unit onto base through the SAME serialized,
conflict-safe `land_branch` engine that powers `/release:session finish`. A dirty base is still never
clobbered — land only proceeds when your trunk checkout is clean.

## Usage

```
/release:land                 # list landable units, pick one
/release:land <label>         # land the unit whose branch matches <label>  (quick/<label>, feat/<label>, session/<label>)
/release:land --all           # land every ready unit, serialized on the per-base lock
```

## Flow

### Step 1 — resolve base + enumerate landable units

```bash
MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"
BASE="$(git -C "$MAIN_ROOT" rev-parse --abbrev-ref HEAD)"   # land target = the branch you're testing on (main checkout's current branch)

# A landable unit = a worktree whose branch is quick/* | feat/* | session/* and is NOT yet an ancestor of base.
git worktree list --porcelain | awk '
  /^worktree /{w=substr($0,10)}
  /^branch /{b=$2; sub("refs/heads/","",b); if (b ~ /^(quick|feat|session)\//) print w "\t" b }
' | while IFS="$(printf '\t')" read -r wt br; do
  git -C "$MAIN_ROOT" merge-base --is-ancestor "$br" "$BASE" 2>/dev/null && continue   # already landed
  printf '%s\t%s\n' "$br" "$wt"   # branch <TAB> worktree
done
```

### Step 2 — pick the unit

- `<label>` given → select the unit whose branch is `quick/<label>`, `feat/<label>`, `session/<label>`,
  or whose branch basename matches `<label>`. Ambiguous or no match → list the units and ask via `AskUserQuestion`.
- no arg → if exactly one landable unit exists, use it; otherwise list them and ask (`AskUserQuestion`).
- `--all` → iterate every landable unit (Step 3 in a loop); the per-base lock serializes them safely.

### Step 3 — land via the shared engine

```bash
RELEASE_LIB="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/release-merge-lib.sh}"
[ -n "$RELEASE_LIB" ] && [ -f "$RELEASE_LIB" ] || RELEASE_LIB="$(find "$HOME/.claude" -name release-merge-lib.sh -path '*/bin/*' 2>/dev/null | head -1)"
[ -f "$RELEASE_LIB" ] || { echo "ABORT: release-merge-lib.sh not found (set CLAUDE_PLUGIN_ROOT)."; exit 1; }
. "$RELEASE_LIB"

# BR + WT come from the unit picked in Step 2 (for --all, loop over each pair)
RESULT="$(land_branch "$BR" "$WT" "$BASE" | tail -1)"
cd "$MAIN_ROOT"   # land may remove $WT from under us
case "$RESULT" in
  RESULT=merged)        echo "✓ $BR landed on $BASE (live) — hot-reload has it if your app runs on $BASE." ;;
  RESULT=held-dirty)    echo "⏸ $BASE still has uncommitted work. Commit/stash on $BASE, then re-run /release:land." ;;
  RESULT=conflict)      echo "✗ code conflict vs $BASE. Resolve in $WT, commit, then re-run /release:land." ;;
  RESULT=refused)       echo "✗ merge refused (untracked-file collision in $WT). Clean it, then re-run." ;;
  RESULT=locked)        echo "⏳ another land/finish is merging into $BASE. Retry in a moment." ;;
  RESULT=planningblock) echo "✗ base '$BASE' tracks planning files a land would delete. Untrack on base first." ;;
  RESULT=baseadvanced)  echo "✗ $BASE advanced under us — aborted, base byte-identical. Re-run /release:land." ;;
  RESULT=badbase)       echo "✗ base resolved to a session branch. Pin one: /release:session base <branch>." ;;
  *)                    echo "✗ land failed ($RESULT). Unit kept at $WT." ;;
esac
```

## Notes

- **Same engine everywhere.** `session finish`, `quick`, `execute` auto-land, and `land` all call
  `land_branch` (`bin/release-merge-lib.sh`, contract-tested by `bin/test-session-merge.sh`). One
  per-base lock serializes every merge-back, so nothing corrupts your trunk.
- **Nothing is lost.** A held unit's branch + worktree are preserved until it lands.
- **`--all` is fail-soft.** A unit that conflicts or holds is left for you; the rest still land.

---

_Retry path for the deferred auto-merge. Serialized, conflict-safe, never clobbers a dirty trunk._
