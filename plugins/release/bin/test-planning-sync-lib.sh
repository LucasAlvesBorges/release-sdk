#!/usr/bin/env bash
# Contract test for the planning-artifact sync substrate (v0.23.0).
#
# SOURCES the real shipped engine — bin/release-planning-sync-lib.sh — so there is NO drift: the
# code under test IS the code skills/execute and agents/wave-executor run.
#
# Coverage:
#   #1  sync IN carries the phase dir + root inputs into a worktree that git worktree left empty
#   #2  sync IN is phase-scoped: an unrelated phase is not dragged along
#   #3  sync IN with no source planning dir ⇒ skipped (not an error); bad worktree ⇒ failed
#   #4  sync OUT copies produced artifacts back (SUMMARY / WAVE-SUMMARY / VERIFICATION / .progress)
#   #5  sync OUT never copies scratch (PLAN-SLICE-*, .exec-start-sha, sweep-B*.json, inventory)
#   #6  sync OUT never deletes or truncates anything already on the destination
#   #7  sync OUT reports `failed` + the missing path when a copy cannot happen (⇒ caller aborts teardown)
#   #8  round trip: in → produce → out leaves the artifact in the main checkout
#   #9  fullstack halves both survive (SUMMARY-BACKEND + SUMMARY-FRONTEND)
#   #10 artifact globs never include scratch patterns (the "what is an artifact" decision)
#
# Run: bash bin/test-planning-sync-lib.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-planning-sync-lib.sh
source "$HERE/release-planning-sync-lib.sh"

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1" "missing [$3] in: $2";; esac; }
hasnt() { case "$2" in *"$3"*) no "$1" "unexpected [$3] in: $2";; *) ok "$1";; esac; }
isfile() { [ -f "$2" ] && ok "$1" || no "$1" "missing file $2"; }
nofile() { [ -f "$2" ] && no "$1" "unexpected file $2" || ok "$1"; }

TMP="$(mktemp -d -t release-psync-test-XXXXXX)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
PD=".release-planning"

fresh_main() {  # rebuild a main checkout with two phases planned
  MAIN="$TMP/main"; rm -rf "$MAIN"
  mkdir -p "$MAIN/$PD/phases/12-invoices" "$MAIN/$PD/phases/13-other"
  printf 'LOCK-01\n'   > "$MAIN/$PD/RELEASE-LOCKS.md"
  printf 'stack: x\n'  > "$MAIN/$PD/PROJECT.md"
  printf 'cursor\n'    > "$MAIN/$PD/STATE.md"
  printf 'test_env_provision: true\n' > "$MAIN/$PD/EXEC-ENV.yml"
  printf 'T01\n'       > "$MAIN/$PD/phases/12-invoices/12-PLAN.md"
  printf 'goal\n'      > "$MAIN/$PD/phases/12-invoices/12-SPEC.md"
  printf 'other\n'     > "$MAIN/$PD/phases/13-other/13-PLAN.md"
}
fresh_wt() { WT="$TMP/wt"; rm -rf "$WT"; mkdir -p "$WT"; }   # as git worktree add leaves it: no planning dir

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #1 sync IN carries the plan into an empty worktree ──"
fresh_main; fresh_wt
OUT="$(planning_sync_in "$MAIN" "$WT" '12-*')"
has "verdict ok" "$OUT" "PLANNING_SYNC_IN=ok"
isfile "PLAN landed in the worktree"  "$WT/$PD/phases/12-invoices/12-PLAN.md"
isfile "SPEC landed"                  "$WT/$PD/phases/12-invoices/12-SPEC.md"
isfile "RELEASE-LOCKS landed"         "$WT/$PD/RELEASE-LOCKS.md"
isfile "PROJECT landed"               "$WT/$PD/PROJECT.md"
isfile "STATE landed"                 "$WT/$PD/STATE.md"
isfile "EXEC-ENV landed (the run needs its own env config)" "$WT/$PD/EXEC-ENV.yml"

echo "── #2 sync IN is phase-scoped ──"
nofile "unrelated phase NOT dragged in" "$WT/$PD/phases/13-other/13-PLAN.md"
OUT="$(planning_sync_in "$MAIN" "$WT" '*')"
isfile "glob '*' carries every phase when asked" "$WT/$PD/phases/13-other/13-PLAN.md"

echo "── #3 degenerate inputs ──"
mkdir -p "$TMP/bare"
eq "no source planning dir → skipped (not an error)" "PLANNING_SYNC_IN=skipped" \
   "$(planning_sync_in "$TMP/bare" "$WT" '*')"
has "missing worktree → failed" "$(planning_sync_in "$MAIN" "$TMP/nope" '*')" "PLANNING_SYNC_IN=failed"

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #4 sync OUT copies produced artifacts back ──"
fresh_main; fresh_wt
planning_sync_in "$MAIN" "$WT" '12-*' >/dev/null
D="$WT/$PD/phases/12-invoices"
printf 'summary\n'      > "$D/12-SUMMARY.md"
printf 'waves\n'        > "$D/12-WAVE-SUMMARY.md"
printf 'verified\n'     > "$D/12-VERIFICATION.md"
printf '{"task":"T03"}' > "$D/.progress.json"
OUT="$(planning_sync_out "$WT" "$MAIN" '12-*')"
has "verdict ok" "$OUT" "PLANNING_SYNC_OUT=ok"
M="$MAIN/$PD/phases/12-invoices"
isfile "SUMMARY came back"       "$M/12-SUMMARY.md"
isfile "WAVE-SUMMARY came back"  "$M/12-WAVE-SUMMARY.md"
isfile "VERIFICATION came back"  "$M/12-VERIFICATION.md"
isfile "progress file came back" "$M/.progress.json"

echo "── #5 scratch stays in the worktree ──"
printf 'slice\n'   > "$D/PLAN-SLICE-T02.md"
printf 'abc123\n'  > "$D/.exec-start-sha"
printf '{}\n'      > "$D/sweep-B1.json"
printf '{}\n'      > "$D/test-inventory.json"
planning_sync_out "$WT" "$MAIN" '12-*' >/dev/null
nofile "PLAN-SLICE not copied"      "$M/PLAN-SLICE-T02.md"
nofile ".exec-start-sha not copied" "$M/.exec-start-sha"
nofile "sweep bucket not copied"    "$M/sweep-B1.json"
nofile "test inventory not copied"  "$M/test-inventory.json"

echo "── #6 sync OUT is additive — never destroys the destination ──"
printf 'human notes\n' > "$M/12-NOTES.md"
printf 'the plan\n'    > "$M/12-PLAN.md"
planning_sync_out "$WT" "$MAIN" '12-*' >/dev/null
isfile "unrelated destination file survives" "$M/12-NOTES.md"
eq "destination PLAN untouched" "the plan" "$(cat "$M/12-PLAN.md")"
eq "artifact content is the worktree's" "summary" "$(cat "$M/12-SUMMARY.md")"

echo "── #7 a copy that cannot happen is FAILED with the path (caller must abort teardown) ──"
RO="$TMP/readonly"; mkdir -p "$RO/$PD/phases/12-invoices"
chmod -w "$RO/$PD/phases/12-invoices"
OUT="$(planning_sync_out "$WT" "$RO" '12-*')"
has "verdict failed" "$OUT" "PLANNING_SYNC_OUT=failed"
has "names what could not be copied" "$OUT" "12-SUMMARY.md"
chmod +w "$RO/$PD/phases/12-invoices"
has "no worktree planning dir → skipped" "$(planning_sync_out "$TMP/bare" "$MAIN" '*')" "PLANNING_SYNC_OUT=skipped"
has "missing destination → failed" "$(planning_sync_out "$WT" "$TMP/nope" '12-*')" "PLANNING_SYNC_OUT=failed"

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #8 round trip (the real teardown scenario) ──"
fresh_main; fresh_wt
planning_sync_in "$MAIN" "$WT" '12-*' >/dev/null
printf 'produced in the worktree\n' > "$WT/$PD/phases/12-invoices/12-SUMMARY.md"
planning_sync_out "$WT" "$MAIN" '12-*' >/dev/null
rm -rf "$WT"                                   # git worktree remove --force
eq "artifact survived the teardown" "produced in the worktree" \
   "$(cat "$MAIN/$PD/phases/12-invoices/12-SUMMARY.md")"

echo "── #9 fullstack halves both survive ──"
fresh_main; fresh_wt
planning_sync_in "$MAIN" "$WT" '12-*' >/dev/null
printf 'be\n' > "$WT/$PD/phases/12-invoices/12-SUMMARY-BACKEND.md"
printf 'fe\n' > "$WT/$PD/phases/12-invoices/12-WAVE-SUMMARY-FRONTEND.md"
planning_sync_out "$WT" "$MAIN" '12-*' >/dev/null
isfile "backend half"  "$MAIN/$PD/phases/12-invoices/12-SUMMARY-BACKEND.md"
isfile "frontend half" "$MAIN/$PD/phases/12-invoices/12-WAVE-SUMMARY-FRONTEND.md"

echo "── #10 the artifact list itself excludes scratch ──"
G="$(planning_artifact_globs)"
has "includes SUMMARY"        "$G" "*-SUMMARY.md"
has "includes VERIFICATION"   "$G" "*-VERIFICATION.md"
has "includes progress"       "$G" ".progress.json"
hasnt "excludes PLAN-SLICE"   "$G" "PLAN-SLICE"
hasnt "excludes sweep buckets" "$G" "sweep-B"
hasnt "excludes exec-start-sha" "$G" "exec-start-sha"
hasnt "excludes the PLAN itself (an input, never copied back)" "$G" "*-PLAN.md"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
