#!/usr/bin/env bash
# release-gc-lib.sh — garbage collection for what quick/execute/land leave behind (v0.27.0).
#
# SINGLE SOURCE OF TRUTH for "what can be pruned safely?". Sourced by:
#   - skills/gc/SKILL.md          (/release:gc [--apply])
#   - hooks/release-efficiency-context.js reports the count only (advisory, SessionStart)
#   - bin/test-gc-lib.sh          (the contract test SOURCES this file — no drift)
#
# WHY THIS EXISTS
# A land removes its own unit. A crashed run, a held-dirty land that was later merged by hand, a
# --no-merge unit merged through a PR, or a Codex worktree merged externally all leave a worktree
# and a branch behind. Over a month that is dozens of worktrees and a hundred merged branches, and
# `git worktree list` stops being readable. GC prunes ONLY what is provably safe:
#
#   PRUNE-WORKTREE  branch already an ancestor of base AND working tree clean (tracked + untracked)
#   PRUNE-MISSING   registered worktree whose directory no longer exists (git worktree prune)
#   PRUNE-BRANCH    local branch already an ancestor of base, checked out nowhere, not protected
#   STALE-LOCK      ../release-worktrees/.locks/*.lock whose holder pid is dead
#
# and KEEPS everything else, saying why:
#
#   KEEP-MAIN       the main checkout
#   KEEP-BASE       the worktree that has base checked out
#   KEEP-DIRTY      merged but has uncommitted or untracked files — a remove would destroy them
#   KEEP-UNMERGED   work not yet on base
#   KEEP-EXTERNAL   registered outside <main_root>/.. (e.g. ~/.codex/worktrees, /tmp) — not ours
#   KEEP-LIVE-LOCK  lock whose holder is alive
#
# A `locked` worktree is NOT protection against gc: quick/execute lock units so `git worktree prune`
# never drops them mid-run; once merged and clean the lock is a leftover and gc unlocks it first.
#
# Public API (all echo verdict lines and ALWAYS return 0 — house style):
#   gc_scan  <main_root> <base>   → one `<VERDICT> <path-or-branch> [branch]` line per item (dry run)
#   gc_apply <main_root> <base>   → performs every PRUNE-*/STALE-LOCK from gc_scan, echoes
#                                    `GC=removed-worktree <path>` / `GC=deleted-branch <b>` /
#                                    `GC=removed-lock <f>` / `GC=pruned <path>` / `GC=failed <what>`
#                                    then `GC_SUMMARY worktrees=N branches=N locks=N kept=N`
#   gc_count <main_root> <base>   → exact number of prunable items (runs a status per worktree; seconds
#                                    on a repo with 50 worktrees — not for hooks)
#   gc_hint_count <main_root> <base> → cheap upper bound for a SessionStart hint: local branches already
#                                    on base (one git call, ~40 ms) + registered worktrees whose directory
#                                    vanished. Never runs status.

_gc_protected_branch() {  # $1 branch, $2 base → 0 when protected
  case "$1" in "$2"|main|master|dev|develop|trunk|HEAD) return 0;; esac
  return 1
}

_gc_worktrees() {  # $1 main_root → `<path>\t<branch-or-empty>\t<locked:0|1>` per registered worktree
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    function flush() { if (w != "") printf "%s\t%s\t%d\n", w, b, l; w=""; b=""; l=0 }
    /^worktree /{ flush(); w=substr($0,10) }
    /^branch /{ b=$2; sub("refs/heads/","",b) }
    /^locked/{ l=1 }
    END{ flush() }'
  return 0
}

_gc_is_clean() {  # $1 worktree path → 0 when no tracked change AND no untracked (non-ignored) file
  [ -z "$(git -C "$1" status --porcelain 2>/dev/null)" ]
}

gc_scan() {  # <main_root> <base>
  local mr="${1:-.}" base="${2:-}" parent line wt br locked lockf hp
  mr="$(cd "$mr" 2>/dev/null && pwd -P)" || { echo "GC=failed bad-main-root"; return 0; }
  [ -n "$base" ] || base="$(git -C "$mr" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  git -C "$mr" show-ref --verify --quiet "refs/heads/$base" || { echo "GC=failed unknown-base $base"; return 0; }
  parent="$(dirname "$mr")"

  # worktrees
  while IFS="$(printf '\t')" read -r wt br locked; do
    [ -n "$wt" ] || continue
    if [ "$wt" = "$mr" ]; then echo "KEEP-MAIN $wt"; continue; fi
    if [ ! -d "$wt" ]; then echo "PRUNE-MISSING $wt ${br:-(detached)}"; continue; fi
    case "$wt" in "$parent"/*) ;; *) echo "KEEP-EXTERNAL $wt ${br:--}"; continue;; esac
    if [ "$br" = "$base" ]; then echo "KEEP-BASE $wt $br"; continue; fi
    if [ -z "$br" ]; then
      # detached HEAD: prunable only when its commit is on base and the tree is clean
      if git -C "$mr" merge-base --is-ancestor "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" "$base" 2>/dev/null; then
        if _gc_is_clean "$wt"; then echo "PRUNE-WORKTREE $wt (detached)"; else echo "KEEP-DIRTY $wt (detached)"; fi
      else echo "KEEP-UNMERGED $wt (detached)"; fi
      continue
    fi
    if git -C "$mr" merge-base --is-ancestor "$br" "$base" 2>/dev/null; then
      if _gc_is_clean "$wt"; then echo "PRUNE-WORKTREE $wt $br"; else echo "KEEP-DIRTY $wt $br"; fi
    else
      echo "KEEP-UNMERGED $wt $br"
    fi
  done <<EOF
$(_gc_worktrees "$mr")
EOF

  # branches checked out nowhere, already on base, not protected
  git -C "$mr" for-each-ref --format='%(refname:short)%09%(worktreepath)' refs/heads 2>/dev/null \
  | while IFS="$(printf '\t')" read -r br wt; do
    [ -n "$br" ] || continue
    [ -z "$wt" ] || continue
    _gc_protected_branch "$br" "$base" && continue
    git -C "$mr" merge-base --is-ancestor "$br" "$base" 2>/dev/null && echo "PRUNE-BRANCH $br"
  done

  # merge locks whose holder is dead
  for lockf in "$parent"/release-worktrees/.locks/*.lock; do
    [ -f "$lockf" ] || continue
    hp="$(awk 'NR==1{print $2}' "$lockf" 2>/dev/null)"
    if [ -n "$hp" ] && kill -0 "$hp" 2>/dev/null; then echo "KEEP-LIVE-LOCK $lockf"; else echo "STALE-LOCK $lockf"; fi
  done
  return 0
}

gc_count() {  # <main_root> <base> → number of prunable items
  gc_scan "$1" "${2:-}" | grep -c -E '^(PRUNE-|STALE-LOCK)' 2>/dev/null || true
  return 0
}

gc_hint_count() {  # <main_root> <base> → cheap upper bound of prunable items (no per-worktree status)
  local mr="${1:-.}" base="${2:-}" n=0 br wt locked
  mr="$(cd "$mr" 2>/dev/null && pwd -P)" || { echo 0; return 0; }
  [ -n "$base" ] || base="$(git -C "$mr" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  git -C "$mr" show-ref --verify --quiet "refs/heads/$base" || { echo 0; return 0; }
  while IFS= read -r br; do
    [ -n "$br" ] || continue
    _gc_protected_branch "$br" "$base" || n=$((n+1))
  done <<GCEOF
$(git -C "$mr" branch --merged "$base" --format='%(refname:short)' 2>/dev/null)
GCEOF
  while IFS="$(printf '\t')" read -r wt br locked; do
    [ -n "$wt" ] && [ ! -d "$wt" ] && n=$((n+1))
  done <<GCEOF
$(_gc_worktrees "$mr")
GCEOF
  echo "$n"
  return 0
}

gc_apply() {  # <main_root> <base>
  local mr="${1:-.}" base="${2:-}" verdict target br nw=0 nb=0 nl=0 kept=0 scan
  mr="$(cd "$mr" 2>/dev/null && pwd -P)" || { echo "GC=failed bad-main-root"; return 0; }
  [ -n "$base" ] || base="$(git -C "$mr" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  cd "$mr" 2>/dev/null || cd / 2>/dev/null || true   # never remove the directory the shell stands in
  scan="$(gc_scan "$mr" "$base")"
  case "$scan" in GC=failed*) printf '%s\n' "$scan"; return 0;; esac
  while read -r verdict target br; do
    case "$verdict" in
      PRUNE-WORKTREE)
        git -C "$mr" worktree unlock "$target" >/dev/null 2>&1 || true
        if git -C "$mr" worktree remove --force "$target" >/dev/null 2>&1; then
          echo "GC=removed-worktree $target"; nw=$((nw+1))
          if [ -n "$br" ] && [ "$br" != "(detached)" ] && git -C "$mr" merge-base --is-ancestor "$br" "$base" 2>/dev/null \
             && ! _gc_protected_branch "$br" "$base"; then
            git -C "$mr" branch -D "$br" >/dev/null 2>&1 && { echo "GC=deleted-branch $br"; nb=$((nb+1)); }
          fi
        else echo "GC=failed remove-worktree $target"; fi ;;
      PRUNE-MISSING)
        git -C "$mr" worktree prune >/dev/null 2>&1 && { echo "GC=pruned $target"; nw=$((nw+1)); }
        # the registration was the only thing keeping a merged branch alive → same rule as a removed worktree
        if [ -n "$br" ] && [ "$br" != "(detached)" ] && git -C "$mr" merge-base --is-ancestor "$br" "$base" 2>/dev/null \
           && ! _gc_protected_branch "$br" "$base"; then
          git -C "$mr" branch -D "$br" >/dev/null 2>&1 && { echo "GC=deleted-branch $br"; nb=$((nb+1)); }
        fi ;;
      PRUNE-BRANCH)
        if git -C "$mr" branch -d "$target" >/dev/null 2>&1; then echo "GC=deleted-branch $target"; nb=$((nb+1))
        else echo "GC=failed delete-branch $target"; fi ;;
      STALE-LOCK)
        rm -f "$target" 2>/dev/null && { echo "GC=removed-lock $target"; nl=$((nl+1)); } ;;
      KEEP-*) kept=$((kept+1)) ;;
    esac
  done <<EOF
$scan
EOF
  git -C "$mr" worktree prune >/dev/null 2>&1 || true
  echo "GC_SUMMARY worktrees=$nw branches=$nb locks=$nl kept=$kept"
  return 0
}
