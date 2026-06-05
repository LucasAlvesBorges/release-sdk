#!/usr/bin/env bash
# Real-git contract test for /release:session (v0.16.0).
#
# The helpers below are FAITHFUL slices of skills/session/SKILL.md (base_token / untrack_planning /
# sync_into_session / finish / cleanup). They are a touch STRICTER than the doc on exactly one point:
# the cleanup uses BARE `git` after `cd "$MAIN_ROOT"` (the doc additionally uses `git -C` belt-and-
# suspenders) so the `cd "$MAIN_ROOT"` line is load-bearing — delete it and the from-inside test fails,
# guarding bug #1. stderr from the from-inside finish is captured and asserted clean.
#
# Coverage (each maps to a fixed bug):
#   #1  cwd-drift: finish FROM INSIDE the worktree → no `Unable to read cwd`, worktree AND branch gone
#   #2  refused merge (untracked-collision) STOPS, base untouched
#   #3  planning never leaks (assert ALL of .release-planning/ except base-branch); modify/delete planning
#       conflict auto-resolves by untracking
#   #4  base-tracks-planning ⇒ finish hard-stops (no silent delete)
#   #5  slash-in-base lockfile works (release/v2)
#   #6  drift: base advances between finishes → 2nd re-syncs under lock and merges clean, base never dirty
#   #7  throwaway path (base checked out NOWHERE) + cleanup with MAIN HEAD != base, branch -D
#   #8  per-base lock serializes; a stale lock from a DEAD pid is reclaimed
#   plus: code conflict STOPS base byte-identical (never auto-resolved)
#
# Run: bash bin/test-session-merge.sh
set -euo pipefail

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }

SBX="$(mktemp -d)"; trap 'rm -rf "$SBX"' EXIT
REPO="$SBX/app"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$REPO"
git -C "$REPO" init -q -b dev
printf 'app\n' > "$REPO/README.md"; git -C "$REPO" add -A; git -C "$REPO" commit -qm init
# .session marker is local-only: exclude it everywhere so `git add -A` never stages it (mirrors `start` step 6).
# Use the ABSOLUTE git dir — a relative --git-common-dir would resolve against the wrong cwd.
printf '.release-planning/.session\n' >> "$(git -C "$REPO" rev-parse --absolute-git-dir)/info/exclude"
WT="$REPO/../release-worktrees"; SESS="$WT/sessions"; LOCKS="$WT/.locks"
cd "$REPO"   # stand in the sandbox main checkout so cwd-based MAIN_ROOT resolves to $REPO

# ── faithful slices of skills/session/SKILL.md ───────────────────────────────────────────────────
main_root() { git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}'; }
base_token() { printf '%s' "$1" | tr '/' '_'; }

untrack_planning() {  # $1 = worktree
  local wt="$1"
  if git -C "$wt" ls-files -u -- .release-planning/base-branch 2>/dev/null | grep -q .; then
    git -C "$wt" checkout --theirs -- .release-planning/base-branch 2>/dev/null || true
    git -C "$wt" add -- .release-planning/base-branch 2>/dev/null || true
  fi
  git -C "$wt" rm -r --cached --quiet --ignore-unmatch -- .release-planning/ >/dev/null 2>&1 || true
  [ -f "$wt/.release-planning/base-branch" ] && git -C "$wt" add -f -- .release-planning/base-branch || true
}

sync_into_session() {  # $1 worktree, $2 base ; 0 synced, 2 code-conflict, 3 refused
  local wt="$1" base="$2" mout mrc
  [ -d "$wt" ] || return 1
  [ -z "$(git -C "$wt" status --porcelain --untracked-files=no)" ] || return 1
  mout="$(git -C "$wt" merge "$base" --no-commit --no-ff 2>&1)"; mrc=$?
  if [ "$mrc" -ne 0 ] && ! git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
       && [ -z "$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null)" ]; then
    return 3   # merge refused before it started (e.g. untracked-file collision)
  fi
  local code; code="$(git -C "$wt" diff --name-only --diff-filter=U -- ':(exclude).release-planning/' 2>/dev/null || true)"
  if [ -n "$code" ]; then git -C "$wt" merge --abort 2>/dev/null || true; return 2; fi
  untrack_planning "$wt"
  if git -C "$wt" diff --cached --quiet && ! git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then :
  else git -C "$wt" commit --no-edit -m "merge($base): sync + untrack planning" >/dev/null; fi
  return 0
}

# Faithful finish. Echoes RESULT=merged|conflict|refused|locked|planningblock|baseadvanced|badbase|nolabel.
# Always returns 0. Label: $1 or auto-detected from the cwd worktree's .session marker (the from-inside path).
sfinish() {
  local arg="${1:-}" MAIN_ROOT BASE label br wt SESS_DIR LOCK_DIR lock temp="" basewt rc hp
  MAIN_ROOT="$(main_root)"
  if [ -n "$arg" ]; then label="$arg"
  else label="$(sed -n 's/^label: //p' "$(git rev-parse --show-toplevel)/.release-planning/.session" 2>/dev/null)"; fi
  [ -n "$label" ] || { echo "RESULT=nolabel"; return 0; }
  br="session/$label"
  SESS_DIR="$MAIN_ROOT/../release-worktrees/sessions"; LOCK_DIR="$MAIN_ROOT/../release-worktrees/.locks"
  wt="$SESS_DIR/$label"
  BASE="$(sed -n 's/^base: //p' "$wt/.release-planning/.session" 2>/dev/null)"
  [ -n "$BASE" ] || BASE="$(cat "$MAIN_ROOT/.release-planning/base-branch" 2>/dev/null || git -C "$MAIN_ROOT" rev-parse --abbrev-ref HEAD)"
  case "$BASE" in session/*) echo "RESULT=badbase"; return 0;; esac

  # data-loss guard (#4): base tracks planning beyond base-branch?
  if [ -n "$(git -C "$MAIN_ROOT" ls-tree -r --name-only "$BASE" -- .release-planning/ 2>/dev/null | grep -v '^\.release-planning/base-branch$')" ]; then
    echo "RESULT=planningblock"; return 0; fi

  # lock FIRST (#6 atomic; #5 slash-safe; #8 stale-reclaim)
  mkdir -p "$LOCK_DIR"; lock="$LOCK_DIR/merge-$(base_token "$BASE").lock"
  if ! ( set -o noclobber; printf '%s\n' "$label $$" > "$lock" ) 2>/dev/null; then
    hp="$(awk 'NR==1{print $2}' "$lock" 2>/dev/null)"
    if [ -n "$hp" ] && ! kill -0 "$hp" 2>/dev/null; then
      rm -f "$lock"; ( set -o noclobber; printf '%s\n' "$label $$" > "$lock" ) 2>/dev/null || { echo "RESULT=locked"; return 0; }
    else echo "RESULT=locked"; return 0; fi
  fi

  # sync UNDER the lock
  sync_into_session "$wt" "$BASE"; rc=$?
  if [ "$rc" = 3 ]; then rm -f "$lock"; echo "RESULT=refused"; return 0; fi
  if [ "$rc" = 2 ]; then rm -f "$lock"; echo "RESULT=conflict"; return 0; fi
  [ "$rc" = 0 ] || { rm -f "$lock"; echo "RESULT=error"; return 0; }

  # locate base checkout; throwaway if base is checked out nowhere (#7)
  basewt="$(git worktree list --porcelain | awk -v b="refs/heads/$BASE" '/^worktree /{w=substr($0,10)} /^branch /{if($2==b)print w}')"
  if [ -z "$basewt" ]; then temp="$MAIN_ROOT/../release-worktrees/.merge-$(base_token "$BASE")"; git -C "$MAIN_ROOT" worktree add -q "$temp" "$BASE"; basewt="$temp"; fi

  # guarded merge: session ⊇ base ⇒ clean; abort+restore on any surprise conflict
  if ! git -C "$basewt" merge --no-ff "$br" -m "merge(session): $label into $BASE" -q 2>/dev/null; then
    git -C "$basewt" merge --abort 2>/dev/null || true
    [ -n "$temp" ] && git -C "$MAIN_ROOT" worktree remove --force "$temp" 2>/dev/null
    rm -f "$lock"; echo "RESULT=baseadvanced"; return 0
  fi

  # cwd-safe cleanup (#1): cd to MAIN_ROOT, then BARE git (the cd is the guard). stderr left VISIBLE.
  cd "$MAIN_ROOT" || cd /
  git worktree remove --force "$wt"
  if git merge-base --is-ancestor "$br" "$BASE"; then git branch -D "$br" >/dev/null; fi
  [ -n "$temp" ] && git worktree remove --force "$temp" 2>/dev/null
  git worktree prune 2>/dev/null
  rm -f "$lock"
  echo "RESULT=merged"; return 0
}

scleanup() {  # faithful cmd_cleanup slice ($1 = base). echoes CLEANED/SKIP-DIRTY/KEPT per session.
  local MAIN_ROOT BASE lbl br; MAIN_ROOT="$(main_root)"; BASE="$1"; cd "$MAIN_ROOT" || true
  git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while read -r wt; do
    case "$wt" in *"/sessions/"*) ;; *) continue;; esac
    lbl="$(sed -n 's/^label: //p' "$wt/.release-planning/.session" 2>/dev/null)"; [ -n "$lbl" ] || lbl="$(basename "$wt")"
    br="session/$lbl"; git show-ref --verify --quiet "refs/heads/$br" || continue
    if git merge-base --is-ancestor "$br" "$BASE" 2>/dev/null; then
      [ -n "$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null)" ] && { echo "SKIP-DIRTY $lbl"; continue; }
      git -C "$MAIN_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 && git -C "$MAIN_ROOT" branch -D "$br" >/dev/null 2>&1 && echo "CLEANED $lbl"
    else echo "KEPT $lbl"; fi
  done
  git -C "$MAIN_ROOT" worktree prune 2>/dev/null
}

sstart() {  # start a session off a base ($2, default dev) + write the local (excluded) .session marker
  local label="$1" base="${2:-dev}"
  git -C "$REPO" worktree add -q -b "session/$label" "$SESS/$label" "$base"
  mkdir -p "$SESS/$label/.release-planning"
  printf 'label: %s\nbase: %s\n' "$label" "$base" > "$SESS/$label/.release-planning/.session"
}
commit_in() { git -C "$SESS/$1" add -A; git -C "$SESS/$1" commit -qm "$2"; }
planning_in_base() { git -C "$REPO" ls-files .release-planning/ | grep -v '^\.release-planning/base-branch$'; }

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── Disjoint domains merge clean (finish by label) ──"
sstart financeiro; sstart rh
mkdir -p "$SESS/financeiro/financeiro"; printf 'refund\n' > "$SESS/financeiro/financeiro/models.py"; commit_in financeiro "feat(financeiro)"
mkdir -p "$SESS/rh/rh"; printf 'payroll\n' > "$SESS/rh/rh/models.py"; commit_in rh "feat(rh)"
eq "financeiro finish → merged" "RESULT=merged" "$(sfinish financeiro | tail -1)"
eq "rh finish → merged"         "RESULT=merged" "$(sfinish rh | tail -1)"
{ [ -f "$REPO/financeiro/models.py" ] && [ -f "$REPO/rh/models.py" ]; } && ok "base 'dev' has BOTH domains" || no "base missing a domain"
[ -z "$(git -C "$REPO" status --porcelain)" ] && ok "base clean after merges" || no "base dirty"
git -C "$REPO" branch | grep -qE 'session/(financeiro|rh)' && no "session branches lingered" || ok "session branches cleaned"

echo "── ACCEPTANCE: finish FROM INSIDE the worktree (#1 cwd-drift + #3 no planning leak) ──"
sstart inside
mkdir -p "$SESS/inside/inside"; printf 'code\n' > "$SESS/inside/inside/models.py"
mkdir -p "$SESS/inside/.release-planning/phases/03"
printf 'big plan markdown\n' > "$SESS/inside/.release-planning/phases/03/PLAN.md"   # planning under phases/
printf 'state\n' > "$SESS/inside/.release-planning/STATE.md"                        # planning at ROOT (must also not leak)
git -C "$SESS/inside" add -A; git -C "$SESS/inside" commit -qm "feat(inside): code + plan + state"
DEV0="$(git -C "$REPO" rev-parse dev)"
set +e; OUT="$( cd "$SESS/inside" && sfinish 2>&1 )"; RC=$?; set -e
eq "no cwd crash (exit 0)" "0" "$RC"
case "$OUT" in *"Unable to read current working directory"*) no "cwd-drift fatal emitted (#1 regression)" "$OUT";; *) ok "no 'Unable to read cwd' fatal (#1)";; esac
eq "finish from inside → merged" "RESULT=merged" "$(printf '%s\n' "$OUT" | tail -1)"
[ -f "$REPO/inside/models.py" ] && ok "base got the code" || no "base missing the merged code"
[ "$DEV0" != "$(git -C "$REPO" rev-parse dev)" ] && ok "base advanced (merge landed)" || no "base SHA unchanged"
[ -z "$(planning_in_base)" ] && ok "planning did NOT leak (NO .release-planning/ tracked but base-branch) (#3)" || no "planning leaked" "$(planning_in_base)"
[ ! -d "$SESS/inside" ] && ok "worktree removed (#1)" || no "worktree NOT removed"
git -C "$REPO" show-ref --verify --quiet refs/heads/session/inside && no "branch lingered (#1 regression)" || ok "branch removed (#1 — delete actually ran)"

echo "── #2 refused merge (untracked collision) STOPS, base untouched ──"
sstart conflictfile
mkdir -p "$SESS/conflictfile/cf" "$SESS/conflictfile/cfcode"
printf 'x\n' > "$SESS/conflictfile/cfcode/m.py"; commit_in conflictfile "feat(cf): code only"
printf 'session-untracked\n' > "$SESS/conflictfile/cf/data.txt"   # left UNTRACKED in the session (after commit)
# base now introduces cf/data.txt as a TRACKED file → merge into session would overwrite the untracked one
mkdir -p "$REPO/cf"; printf 'base-tracked\n' > "$REPO/cf/data.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -qm "base adds cf/data.txt"
DEVc="$(git -C "$REPO" rev-parse dev)"
eq "refused-merge finish → refused" "RESULT=refused" "$(sfinish conflictfile | tail -1)"
eq "base unchanged by refused merge" "$DEVc" "$(git -C "$REPO" rev-parse dev)"
[ -d "$SESS/conflictfile" ] && ok "session preserved after refusal" || no "session lost"
git -C "$REPO" worktree remove --force "$SESS/conflictfile" >/dev/null 2>&1; git -C "$REPO" branch -D session/conflictfile >/dev/null 2>&1 || true

echo "── CODE conflict STOPS, base byte-identical, never auto-resolved ──"
sstart alpha; sstart beta
printf 'A\n' > "$SESS/alpha/shared.py"; commit_in alpha "alpha edits shared"
printf 'B\n' > "$SESS/beta/shared.py";  commit_in beta  "beta edits shared"
eq "alpha finish → merged" "RESULT=merged" "$(sfinish alpha | tail -1)"
DEVb="$(git -C "$REPO" rev-parse dev)"
eq "beta finish → conflict" "RESULT=conflict" "$( cd "$SESS/beta" && sfinish | tail -1 )"
eq "base SHA unchanged by stopped merge" "$DEVb" "$(git -C "$REPO" rev-parse dev)"
[ -z "$(git -C "$REPO" status --porcelain)" ] && ok "base clean after stop (no half-merge)" || no "base left dirty"
git -C "$REPO" show-ref --verify --quiet refs/heads/session/beta && ok "beta branch preserved" || no "beta branch lost"
[ -d "$SESS/beta" ] && ok "beta worktree preserved" || no "beta worktree lost"
[ -z "$(git -C "$SESS/beta" status --porcelain --untracked-files=no)" ] && ok "session clean after abort (conflict stayed in session)" || no "session left mid-merge"
git -C "$REPO" worktree remove --force "$SESS/beta" >/dev/null 2>&1; git -C "$REPO" branch -D session/beta >/dev/null 2>&1 || true

echo "── #3 planning modify/delete conflict auto-resolves (real conflict) ──"
mkdir -p "$REPO/.release-planning/phases/09"; printf 'V1\n' > "$REPO/.release-planning/phases/09/PLAN.md"
git -C "$REPO" add -f .release-planning/phases/09/PLAN.md; git -C "$REPO" commit -qm "base tracks PLAN v1"
sstart pmod                                                        # forks dev WITH PLAN.md tracked
git -C "$REPO" rm -q .release-planning/phases/09/PLAN.md; git -C "$REPO" commit -qm "base deletes PLAN"   # base no longer tracks planning
printf 'V2\n' > "$SESS/pmod/.release-planning/phases/09/PLAN.md"   # session MODIFIES the now-base-deleted file
mkdir -p "$SESS/pmod/pmod"; printf 'p\n' > "$SESS/pmod/pmod/models.py"
git -C "$SESS/pmod" add -A; git -C "$SESS/pmod" commit -qm "feat(pmod): code + modify plan"
eq "pmod finish (modify/delete planning conflict) → merged" "RESULT=merged" "$( cd "$SESS/pmod" && sfinish | tail -1 )"
[ -f "$REPO/pmod/models.py" ] && ok "pmod code reached base despite planning conflict" || no "pmod code missing"
[ -z "$(planning_in_base)" ] && ok "planning conflict auto-resolved by untracking" || no "planning still tracked" "$(planning_in_base)"
[ -z "$(git -C "$REPO" status --porcelain)" ] && ok "base clean after planning auto-resolve" || no "base dirty"

echo "── #4 base tracks planning ⇒ finish hard-stops (no silent delete) ──"
mkdir -p "$REPO/.release-planning/phases/11"; printf 'KEEP\n' > "$REPO/.release-planning/phases/11/PLAN.md"
git -C "$REPO" add -f .release-planning/phases/11/PLAN.md; git -C "$REPO" commit -qm "base legitimately tracks PLAN"
sstart guarded; mkdir -p "$SESS/guarded/g"; printf 'g\n' > "$SESS/guarded/g/m.py"; commit_in guarded "feat(guarded)"
eq "finish → planningblock (base planning protected)" "RESULT=planningblock" "$(sfinish guarded | tail -1)"
[ -f "$REPO/.release-planning/phases/11/PLAN.md" ] && ok "base planning NOT deleted" || no "base planning was deleted (data loss)"
git -C "$REPO" rm -q .release-planning/phases/11/PLAN.md; git -C "$REPO" commit -qm "cleanup test planning"   # reset for later blocks
eq "after untrack, finish proceeds → merged" "RESULT=merged" "$(sfinish guarded | tail -1)"

echo "── #5 slash in base name (release/v2): slash-safe lock, finish works ──"
git -C "$REPO" branch "release/v2" dev
sstart slashed "release/v2"; mkdir -p "$SESS/slashed/s"; printf 's\n' > "$SESS/slashed/s/m.py"; commit_in slashed "feat(slashed)"
eq "slashed-base finish → merged" "RESULT=merged" "$(sfinish slashed | tail -1)"
git -C "$REPO" merge-base --is-ancestor session/slashed "release/v2" 2>/dev/null && no "branch not deleted" || ok "slashed session merged into release/v2 + cleaned"
[ -f "$LOCKS/merge-release_v2.lock" ] && no "slash-lock left behind" || ok "slash-safe lock used + released (merge-release_v2.lock)"

echo "── #6 drift: base moves between finishes → 2nd re-syncs under lock, base never dirty ──"
sstart d1; sstart d2
mkdir -p "$SESS/d1/d1"; printf '1\n' > "$SESS/d1/d1/m.py"; commit_in d1 "feat(d1)"
mkdir -p "$SESS/d2/d2"; printf '2\n' > "$SESS/d2/d2/m.py"; commit_in d2 "feat(d2)"   # disjoint from d1
eq "d1 finish → merged" "RESULT=merged" "$(sfinish d1 | tail -1)"   # advances dev
eq "d2 finish (now behind) → merged" "RESULT=merged" "$(sfinish d2 | tail -1)"   # must re-sync d1's change then merge clean
{ [ -f "$REPO/d1/m.py" ] && [ -f "$REPO/d2/m.py" ]; } && ok "base has both drifted domains" || no "base missing a drifted domain"
[ -z "$(git -C "$REPO" status --porcelain)" ] && ok "base never left dirty across drifted finishes" || no "base dirty after drift"

echo "── #7 throwaway path (base checked out NOWHERE) + cleanup -D with MAIN HEAD != base ──"
git -C "$REPO" branch main dev 2>/dev/null || true
git -C "$REPO" checkout -q main          # now dev is checked out in NO worktree; MAIN HEAD = main != dev
sstart tw; mkdir -p "$SESS/tw/tw"; printf 't\n' > "$SESS/tw/tw/m.py"; commit_in tw "feat(tw)"
eq "throwaway-path finish → merged" "RESULT=merged" "$(sfinish tw | tail -1)"
ls "$WT/.merge-dev" >/dev/null 2>&1 && no "throwaway worktree leaked" || ok "throwaway worktree cleaned"
# session/tw is already deleted by a successful finish, so check dev's TREE (not the branch) for the work
git -C "$REPO" ls-tree -r --name-only dev -- tw/m.py | grep -q . && ok "tw merged into dev (throwaway worktree path)" || no "tw not merged into dev"
git -C "$REPO" show-ref --verify --quiet refs/heads/session/tw && no "tw branch lingered" || ok "tw branch -D'd (MAIN HEAD=main != base=dev)"
# cleanup: a session merged into dev (via simulated external/GitHub merge) but worktree+branch left behind
sstart cl; mkdir -p "$SESS/cl/cl"; printf 'c\n' > "$SESS/cl/cl/m.py"; commit_in cl "feat(cl)"
git -C "$REPO" worktree add -q "$WT/.m" dev                      # dev checked out nowhere → ok to add here
git -C "$WT/.m" merge --no-ff session/cl -m "external merge cl" -q; git -C "$REPO" worktree remove --force "$WT/.m"
sstart cldirty; mkdir -p "$SESS/cldirty/cd"; printf 'd\n' > "$SESS/cldirty/cd/m.py"; commit_in cldirty "feat(cldirty)"  # NOT merged
OUTC="$(scleanup dev)"
printf '%s\n' "$OUTC" | grep -qx 'CLEANED cl' && ok "cleanup removed merged session via -D (MAIN HEAD != base)" || no "cleanup failed to remove merged session" "$OUTC"
printf '%s\n' "$OUTC" | grep -qx 'KEPT cldirty' && ok "cleanup KEPT unmerged session" || no "cleanup wrongly touched unmerged session" "$OUTC"
git -C "$REPO" show-ref --verify --quiet refs/heads/session/cl && no "cleanup left merged branch" || ok "cleanup deleted merged branch"
git -C "$REPO" checkout -q dev

echo "── #8 per-base lock serializes; STALE (dead-pid) lock reclaimed ──"
sstart lk; mkdir -p "$SESS/lk/lk"; printf 'l\n' > "$SESS/lk/lk/m.py"; commit_in lk "feat(lk)"
mkdir -p "$LOCKS"; printf 'held %d\n' "$$" > "$LOCKS/merge-dev.lock"   # LIVE pid (this test) ⇒ refused
eq "finish refuses while live lock held" "RESULT=locked" "$(sfinish lk | tail -1)"
[ -d "$SESS/lk" ] && ok "session intact after lock refusal" || no "session removed despite lock"
printf 'ghost 999999\n' > "$LOCKS/merge-dev.lock"   # DEAD pid ⇒ reclaim + proceed
eq "finish reclaims stale (dead-pid) lock → merged" "RESULT=merged" "$(sfinish lk | tail -1)"
[ -f "$LOCKS/merge-dev.lock" ] && no "lock not released after merge" || ok "lock released after reclaim+merge"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
