#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/release-economy-lib.sh"

PASS=0; FAIL=0
eq() { local label="$1" want="$2" got="$3"; if [ "$want" = "$got" ]; then PASS=$((PASS+1)); else echo "FAIL: $label want=$want got=$got"; FAIL=$((FAIL+1)); fi; }
ok() { local label="$1"; shift; if "$@"; then PASS=$((PASS+1)); else echo "FAIL: $label"; FAIL=$((FAIL+1)); fi; }
no() { local label="$1"; shift; if "$@"; then echo "FAIL: $label"; FAIL=$((FAIL+1)); else PASS=$((PASS+1)); fi; }

eq "C0 lean" lean "$(release_delivery_profile C0)"
eq "C1 lean" lean "$(release_delivery_profile 1)"
eq "C2 standard" standard "$(release_delivery_profile C2)"
eq "C3 strict" strict "$(release_delivery_profile C3)"
eq "C4 strict" strict "$(release_delivery_profile 4)"
eq "unknown safe default" standard "$(release_delivery_profile nonsense)"
eq "auth floor" C3 "$(release_risk_floor C1 auth)"
eq "punctuated auth floor" C3 "$(release_risk_floor C1 'auth/payment')"
eq "multi-tenant floor" C3 "$(release_risk_floor C0 multi-tenant)"
eq "destructive floor" C4 "$(release_risk_floor C2 destructive migration)"
eq "ordinary unchanged" C1 "$(release_risk_floor C1 docs)"
no "standard does not fan out" release_should_parallelize C2 5 1
no "strict needs 3 tasks" release_should_parallelize C3 2 1
no "strict needs disjoint files" release_should_parallelize C3 3 0
ok "strict disjoint fan-out" release_should_parallelize C3 3 1
no "standard checker off" release_should_check C2 0
ok "risk turns checker on" release_should_check C2 1
ok "strict checker on" release_should_check C3 0
eq "lean loop cap" 1 "$(release_loop_default_iters C1)"
eq "standard loop cap" 2 "$(release_loop_default_iters C2)"
eq "strict loop cap" 3 "$(release_loop_default_iters C4)"
eq "lean tests" focused "$(release_test_scope C1)"

echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
