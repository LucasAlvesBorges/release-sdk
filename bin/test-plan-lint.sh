#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi; }
no() { if "$@" >/dev/null 2>&1; then echo "FAIL: expected rejection: $1"; FAIL=$((FAIL+1)); else PASS=$((PASS+1)); fi; }

printf '%s\n' '# Plan' '### T01 — test' '- files: [tests/test_x.py]' '- depends_on: []' '- verification: pytest tests/test_x.py' '### T02 — implement' '- files: [app/x.py]' '- depends_on: [T01]' '- verification: pytest tests/test_x.py' > "$TMP/good.md"
ok node "$HERE/release-plan-lint.js" "$TMP/good.md"
printf '%s\n' '# Plan' '### T01 — broken' '- depends_on: [T99]' > "$TMP/missing.md"
no node "$HERE/release-plan-lint.js" "$TMP/missing.md"
printf '%s\n' '# Plan' '### T01 — a' '- files: [a]' '- depends_on: [T02]' '- verification: true' '### T02 — b' '- files: [b]' '- depends_on: [T01]' '- verification: true' > "$TMP/cycle.md"
no node "$HERE/release-plan-lint.js" "$TMP/cycle.md"
printf '%s\n' '# Plan' '### T01 — simple' '- files: [a]' '- depends_on: []' '- verification: pytest a' > "$TMP/no-harness.md"
ok node "$HERE/release-plan-lint.js" "$TMP/no-harness.md"
echo "RESULT: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
