#!/usr/bin/env bash
# Real-git contract test for /release:session merge-back (v0.15.0 Model B).
# Proves: disjoint sessions merge clean; a conflicting session STOPS with base byte-identical
# (never auto-resolved); the per-base merge lock serializes fan-in.
#
# Run: bash bin/test-session-merge.sh
set -euo pipefail

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }

SBX="$(mktemp -d)"; trap 'rm -rf "$SBX"' EXIT
REPO="$SBX/app"; WT="$SBX/release-worktrees"; LOCKS="$WT/.locks"
mkdir -p "$REPO" "$LOCKS"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git -C "$REPO" init -q -b dev
printf 'app\n' > "$REPO/README.md"; git -C "$REPO" add -A; git -C "$REPO" commit -qm init

# ---- faithful slices of the skill's start/finish ----
sstart() { local label="$1"; git -C "$REPO" worktree add -q -b "session/$label" "$WT/sessions/$label" dev; }

sfinish() {                                   # $1 label ; echoes RESULT=merged|conflict
  local label="$1" BRANCH="session/$1" base=dev
  local lock="$LOCKS/merge-$base.lock"
  ( set -o noclobber; printf '%s\n' "$label" > "$lock" ) 2>/dev/null || { echo "RESULT=locked"; return; }
  # locate base's checkout
  local basewt
  basewt="$(git -C "$REPO" worktree list --porcelain | awk -v b="refs/heads/$base" '
    /^worktree /{wt=substr($0,10)} /^branch /{if($2==b)print wt}')"
  if git -C "$basewt" merge --no-ff "$BRANCH" -m "merge(session): $label" -q; then
    git -C "$REPO" worktree remove --force "$WT/sessions/$label"
    git -C "$REPO" branch -q -d "$BRANCH"
    echo "RESULT=merged"
  else
    git -C "$basewt" merge --abort
    echo "RESULT=conflict"      # worktree + branch left intact for retry
  fi
  rm -f "$lock"
}

commit_in() { git -C "$WT/sessions/$1" add -A; git -C "$WT/sessions/$1" commit -qm "$2"; }

echo "── Disjoint domains merge clean ──"
sstart financeiro; sstart rh
mkdir -p "$WT/sessions/financeiro/financeiro"; printf 'refund\n' > "$WT/sessions/financeiro/financeiro/models.py"; commit_in financeiro "feat(financeiro)"
mkdir -p "$WT/sessions/rh/rh"; printf 'payroll\n' > "$WT/sessions/rh/rh/models.py"; commit_in rh "feat(rh)"
eq "financeiro finish → merged" "RESULT=merged" "$(sfinish financeiro | tail -1)"
eq "rh finish → merged"         "RESULT=merged" "$(sfinish rh | tail -1)"
[ -f "$REPO/financeiro/models.py" ] && [ -f "$REPO/rh/models.py" ] && ok "base 'dev' has BOTH domains" || no "base missing a domain"
[ -z "$(git -C "$REPO" status --porcelain)" ] && ok "base clean after merges" || no "base dirty"
git -C "$REPO" branch | grep -qE 'session/(financeiro|rh)' && no "session branches lingered" || ok "session branches cleaned"

echo "── Conflicting session STOPS, base untouched ──"
sstart alpha; sstart beta                       # both fork from current dev
printf 'A\n' > "$WT/sessions/alpha/shared.txt"; commit_in alpha "alpha edits shared"
printf 'B\n' > "$WT/sessions/beta/shared.txt";  commit_in beta  "beta edits shared"
eq "alpha finish → merged" "RESULT=merged" "$(sfinish alpha | tail -1)"
DEV_BEFORE="$(git -C "$REPO" rev-parse dev)"
RES="$(sfinish beta | tail -1)"
eq "beta finish → conflict" "RESULT=conflict" "$RES"
eq "base SHA unchanged by aborted merge" "$DEV_BEFORE" "$(git -C "$REPO" rev-parse dev)"
[ -z "$(git -C "$REPO" status --porcelain)" ] && ok "base clean after aborted merge (no half-merge)" || no "base left dirty by conflict"
git -C "$REPO" show-ref --verify --quiet refs/heads/session/beta && ok "beta branch preserved for retry" || no "beta branch lost"
[ -d "$WT/sessions/beta" ] && ok "beta worktree preserved for retry" || no "beta worktree lost"

echo "── Merge lock serializes (held lock refuses) ──"
printf 'held\n' > "$LOCKS/merge-dev.lock"
eq "finish refuses while lock held" "RESULT=locked" "$(sfinish beta | tail -1)"
rm -f "$LOCKS/merge-dev.lock"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
