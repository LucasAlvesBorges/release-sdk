#!/usr/bin/env bash
# Contract test for the loop budget/guardrail substrate (v0.18.0).
#
# SOURCES the real shipped engine — bin/release-loop-lib.sh — so there is NO drift: the code under
# test IS the code skills/{loop,audit-fix,plan-review-convergence} run.
#
# Coverage:
#   #1  loop_signature is stable (same input ⇒ same hash) and discriminating (diff input ⇒ diff hash)
#   #2  loop_signature normalizes volatile temp-paths: two failures differing ONLY in the gate temp
#       file path hash EQUAL (so an unchanged failure is detected as no-progress next round)
#   #3  loop_signature reads stdin as well as args
#   #4  loop_guard continues when under cap and the signature changed
#   #5  loop_guard stops with budget-iters at the cap
#   #6  loop_guard stops with no-progress when prev==cur (and prev is non-empty)
#   #7  loop_guard does NOT no-progress on the first iteration (prev empty)
#   #8  no-progress takes precedence over budget when both hold
#   #9  loop_token_spend degrades gracefully when the daemon is down (TOKENS= , no stop)
#
# Run: bash bin/test-loop-lib.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-loop-lib.sh
source "$HERE/release-loop-lib.sh"

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }
ne() { [ "$2" != "$3" ] && ok "$1" || no "$1" "both were [$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1" "missing [$3] in: $2";; esac; }
hasnt() { case "$2" in *"$3"*) no "$1" "unexpected [$3] in: $2";; *) ok "$1";; esac; }

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #1 loop_signature stable + discriminating ──"
S1="$(loop_signature "pytest failed: assert 1 == 2")"
S2="$(loop_signature "pytest failed: assert 1 == 2")"
S3="$(loop_signature "ruff E501 line too long")"
eq "same input → same hash" "$S1" "$S2"
ne "different input → different hash" "$S1" "$S3"

echo "── #2 volatile temp-path normalized (same failure, different gate tmp → equal sig) ──"
A="$(loop_signature "# command: pytest
/var/folders/xx/release-gate-AAAAAA: BOOM at views.py:42")"
B="$(loop_signature "# command: pytest
/var/folders/yy/release-gate-BBBBBB: BOOM at views.py:42")"
eq "temp-path differences normalized away" "$A" "$B"
C="$(loop_signature "# command: pytest
/var/folders/yy/release-gate-BBBBBB: BOOM at views.py:99")"
ne "real change (line 42→99) still differs" "$A" "$C"

echo "── #3 loop_signature reads stdin ──"
SA="$(loop_signature "hello world")"
SB="$(printf 'hello world' | loop_signature)"
eq "stdin == args for same content" "$SA" "$SB"

echo "── #4 loop_guard continues under cap with changed signature ──"
eq "iter 2/6, sig changed → continue" "LOOP=continue" "$(loop_guard 2 6 aaa bbb)"

echo "── #5 loop_guard budget cap ──"
has "iter 6/6 → stop budget-iters" "$(loop_guard 6 6 aaa bbb)" "reason=budget-iters"
has "iter 7/6 → stop budget-iters" "$(loop_guard 7 6 aaa bbb)" "reason=budget-iters"

echo "── #6 loop_guard no-progress ──"
has "prev==cur (non-empty) → stop no-progress" "$(loop_guard 2 6 xyz xyz)" "reason=no-progress"

echo "── #7 first iteration never no-progress (prev empty) ──"
eq "iter 1, prev empty → continue" "LOOP=continue" "$(loop_guard 1 6 '' abc)"

echo "── #8 no-progress wins over budget when both hold ──"
has "iter 6/6 AND prev==cur → no-progress (more actionable)" "$(loop_guard 6 6 same same)" "reason=no-progress"

echo "── #9 loop_token_spend graceful when daemon down ──"
OUT="$(RELEASE_TOKEN_PORT=9 loop_token_spend 0.50)"
eq "daemon down → bare 'TOKENS=' (empty spend)" "TOKENS=" "$OUT"
hasnt "no spurious stop when meter unavailable" "$OUT" "LOOP=stop"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
