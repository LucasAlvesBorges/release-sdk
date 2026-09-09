#!/usr/bin/env bash
# Real-git contract test for the gc engine (v0.27.0).
#
# SOURCES the real shipped engine — bin/release-gc-lib.sh — so the code under test IS what
# /release:gc runs.
#
# Coverage:
#   #1  merged + clean worktree → PRUNE-WORKTREE; apply removes worktree AND its merged branch
#   #2  merged + dirty (tracked edit) → KEEP-DIRTY, untouched by apply
#   #3  merged + untracked file → KEEP-DIRTY (a --force remove would destroy it)
#   #4  unmerged work → KEEP-UNMERGED, branch survives
#   #5  LOCKED merged clean worktree → pruned (unlock first); lock is not protection
#   #6  registered worktree whose directory vanished → PRUNE-MISSING; apply prunes the registration
#   #7  worktree outside <main_root>/.. → KEEP-EXTERNAL even when merged+clean (Codex/tmp are not ours)
#   #8  merged branch with no worktree → PRUNE-BRANCH; protected names (main/dev/base) never listed
#   #9  stale merge lock (dead pid) removed; live lock kept
#   #10 main checkout and the base worktree are always KEEP-*
#   #11 gc_count matches the number of PRUNE/STALE lines; apply summary counts add up
#   #12 apply from INSIDE a doomed worktree does not crash (cd main_root first)
#
# Run: bash bin/test-gc-lib.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=release-gc-lib.sh
source "$HERE/release-gc-lib.sh"

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }
has() { printf '%s\n' "$2" | grep -qx -- "$3" && ok "$1" || no "$1" "missing line [$3] in: $2"; }
hasnot() { printf '%s\n' "$2" | grep -q -- "$3" && no "$1" "unexpected [$3]" || ok "$1"; }

SBX="$(mktemp -d)"; SBX="$(cd "$SBX" && pwd -P)"; trap 'rm -rf "$SBX"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
REPO="$SBX/proj/app"; mkdir -p "$REPO"
git -C "$REPO" init -q -b dev
printf 'app\n' > "$REPO/README.md"; git -C "$REPO" add -A; git -C "$REPO" commit -qm init
WT="$SBX/proj/release-worktrees"; LOCKS="$WT/.locks"; mkdir -p "$LOCKS"
cd "$REPO"

unit() {  # <label> [base] → worktree on feat/<label>
  git -C "$REPO" worktree add -q -b "feat/$1" "$WT/$1" "${2:-dev}"
}
commit_in() { git -C "$1" add -A; git -C "$1" commit -qm "$2"; }
merge_into_dev() { git -C "$REPO" merge --no-ff -q "$1" -m "merge $1"; }

# ── fixtures ───────────────────────────────────────────────────────────────────────────────────────
unit clean;    printf 'c\n' > "$WT/clean/c.py";    commit_in "$WT/clean" "feat(clean)";    merge_into_dev feat/clean
unit dirty;    printf 'd\n' > "$WT/dirty/d.py";    commit_in "$WT/dirty" "feat(dirty)";    merge_into_dev feat/dirty
printf 'WIP\n' >> "$WT/dirty/d.py"
unit untr;     printf 'u\n' > "$WT/untr/u.py";     commit_in "$WT/untr" "feat(untr)";      merge_into_dev feat/untr
printf 'scratch\n' > "$WT/untr/notes.txt"
unit open;     printf 'o\n' > "$WT/open/o.py";     commit_in "$WT/open" "feat(open)"          # NOT merged
unit locked;   printf 'l\n' > "$WT/locked/l.py";   commit_in "$WT/locked" "feat(locked)";  merge_into_dev feat/locked
git -C "$REPO" worktree lock --reason "quick in flight" "$WT/locked"
unit gone;     printf 'g\n' > "$WT/gone/g.py";     commit_in "$WT/gone" "feat(gone)";      merge_into_dev feat/gone
rm -rf "$WT/gone"
mkdir -p "$SBX/elsewhere"
git -C "$REPO" worktree add -q -b feat/ext "$SBX/elsewhere/ext" dev
printf 'e\n' > "$SBX/elsewhere/ext/e.py"; commit_in "$SBX/elsewhere/ext" "feat(ext)"; merge_into_dev feat/ext
git -C "$REPO" branch quick/orphan dev                       # merged (== dev), no worktree
git -C "$REPO" branch main dev                               # protected name, merged
git -C "$REPO" branch feat/ahead dev; git -C "$REPO" worktree add -q "$WT/ahead" feat/ahead
printf 'a\n' > "$WT/ahead/a.py"; commit_in "$WT/ahead" "feat(ahead)"; git -C "$REPO" worktree remove --force "$WT/ahead"   # branch ahead of dev, no worktree
printf 'held %d\n' "$$" > "$LOCKS/merge-dev.lock"            # LIVE lock (this shell)
printf 'ghost 999999\n' > "$LOCKS/merge-release_v2.lock"     # DEAD lock
git -C "$REPO" worktree add -q "$WT/basewt" -b tmpbase dev >/dev/null 2>&1 && git -C "$REPO" worktree remove --force "$WT/basewt" && git -C "$REPO" branch -D tmpbase >/dev/null 2>&1 || true

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── scan verdicts ──"
SCAN="$(gc_scan "$REPO" dev)"
has "#1 merged+clean → PRUNE-WORKTREE"        "$SCAN" "PRUNE-WORKTREE $WT/clean feat/clean"
has "#2 merged+dirty → KEEP-DIRTY"            "$SCAN" "KEEP-DIRTY $WT/dirty feat/dirty"
has "#3 merged+untracked → KEEP-DIRTY"        "$SCAN" "KEEP-DIRTY $WT/untr feat/untr"
has "#4 unmerged → KEEP-UNMERGED"             "$SCAN" "KEEP-UNMERGED $WT/open feat/open"
has "#5 locked merged clean → PRUNE-WORKTREE" "$SCAN" "PRUNE-WORKTREE $WT/locked feat/locked"
has "#6 vanished dir → PRUNE-MISSING"         "$SCAN" "PRUNE-MISSING $WT/gone feat/gone"
has "#7 external path → KEEP-EXTERNAL"        "$SCAN" "KEEP-EXTERNAL $SBX/elsewhere/ext feat/ext"
has "#8 merged orphan branch → PRUNE-BRANCH"  "$SCAN" "PRUNE-BRANCH quick/orphan"
hasnot "#8 protected main never listed"       "$SCAN" "PRUNE-BRANCH main"
hasnot "#8 base never listed"                 "$SCAN" "PRUNE-BRANCH dev"
hasnot "#8 ahead branch never listed"         "$SCAN" "PRUNE-BRANCH feat/ahead"
hasnot "#8 checked-out merged branch is a worktree verdict, not a branch verdict" "$SCAN" "PRUNE-BRANCH feat/clean"
has "#9 dead lock → STALE-LOCK"               "$SCAN" "STALE-LOCK $LOCKS/merge-release_v2.lock"
has "#9 live lock → KEEP-LIVE-LOCK"           "$SCAN" "KEEP-LIVE-LOCK $LOCKS/merge-dev.lock"
has "#10 main checkout → KEEP-MAIN"           "$SCAN" "KEEP-MAIN $REPO"
eq "#11 gc_count = prunable lines" "$(printf '%s\n' "$SCAN" | grep -c -E '^(PRUNE-|STALE-LOCK)')" "$(gc_count "$REPO" dev)"
eq "#11 gc_count is 5 (clean, locked, gone, orphan, stale lock)" "5" "$(gc_count "$REPO" dev)"
# hint = merged unprotected branches (clean, dirty, untr, locked, gone, ext, orphan = 7) + vanished dirs (gone = 1)
eq "#11 gc_hint_count is a cheap upper bound (8)" "8" "$(gc_hint_count "$REPO" dev)"

echo "── #10 base checked out in a worktree is KEEP-BASE ──"
git -C "$REPO" checkout -q main
git -C "$REPO" worktree add -q "$WT/devwt" dev
has "base worktree → KEEP-BASE" "$(gc_scan "$REPO" dev)" "KEEP-BASE $WT/devwt dev"
git -C "$REPO" worktree remove --force "$WT/devwt"; git -C "$REPO" checkout -q dev

echo "── apply ──"
DEV0="$(git -C "$REPO" rev-parse dev)"
cd "$WT/locked"   # #12: stand inside a doomed worktree
OUT="$(gc_apply "$REPO" dev)"; cd "$REPO"
has "removed clean worktree"   "$OUT" "GC=removed-worktree $WT/clean"
has "deleted its branch"       "$OUT" "GC=deleted-branch feat/clean"
has "removed locked worktree"  "$OUT" "GC=removed-worktree $WT/locked"
has "pruned vanished worktree" "$OUT" "GC=pruned $WT/gone"
has "deleted orphan branch"    "$OUT" "GC=deleted-branch quick/orphan"
has "removed stale lock"       "$OUT" "GC=removed-lock $LOCKS/merge-release_v2.lock"
has "#6 vanished worktree branch deleted" "$OUT" "GC=deleted-branch feat/gone"
has "#11 summary adds up"      "$OUT" "GC_SUMMARY worktrees=3 branches=4 locks=1 kept=6"
[ -d "$WT/clean" ] && no "clean worktree still present" || ok "clean worktree gone"
[ -d "$WT/locked" ] && no "locked worktree still present" || ok "locked worktree gone"
[ -d "$WT/dirty" ] && ok "#2 dirty worktree preserved" || no "dirty worktree removed (data loss)"
grep -q WIP "$WT/dirty/d.py" && ok "#2 uncommitted edit intact" || no "uncommitted edit lost"
[ -f "$WT/untr/notes.txt" ] && ok "#3 untracked file intact" || no "untracked file lost"
[ -d "$WT/open" ] && ok "#4 unmerged worktree preserved" || no "unmerged worktree removed"
git -C "$REPO" show-ref --verify --quiet refs/heads/feat/open && ok "#4 unmerged branch preserved" || no "unmerged branch deleted"
[ -d "$SBX/elsewhere/ext" ] && ok "#7 external worktree untouched" || no "external worktree removed"
git -C "$REPO" show-ref --verify --quiet refs/heads/feat/ext && ok "#7 external branch untouched" || no "external branch deleted"
git -C "$REPO" show-ref --verify --quiet refs/heads/main && ok "#8 protected main intact" || no "main deleted"
git -C "$REPO" show-ref --verify --quiet refs/heads/feat/ahead && ok "#8 ahead branch intact" || no "ahead branch deleted"
[ -f "$LOCKS/merge-dev.lock" ] && ok "#9 live lock kept" || no "live lock removed"
git -C "$REPO" show-ref --verify --quiet refs/heads/feat/gone && no "gone branch lingered" || ok "gone branch cleaned by prune"
eq "base SHA untouched by gc" "$DEV0" "$(git -C "$REPO" rev-parse dev)"
[ -z "$(git -C "$REPO" status --porcelain)" ] && ok "main checkout clean after gc" || no "main checkout dirty"
eq "second apply is a no-op" "GC_SUMMARY worktrees=0 branches=0 locks=0 kept=6" "$(gc_apply "$REPO" dev | tail -1)"
eq "bad base reports failure" "GC=failed unknown-base nope" "$(gc_scan "$REPO" nope)"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
