#!/usr/bin/env bash
# Contract test for the test-failure baseline substrate (v0.23.0).
#
# SOURCES the real shipped engine — bin/release-baseline-lib.sh — so there is NO drift: the code
# under test IS the code run_gate, test-runner and phase-verifier classify failures with.
#
# Coverage:
#   #1  signature is `id|error`, whitespace-trimmed, with a safe default error
#   #2  pytest output → signatures (FAILED and ERROR lines; noise ignored)
#   #3  vitest output → signatures
#   #4  baseline_has: exact signature match only — same test, DIFFERENT error is NOT a hit
#   #5  classify: baseline-only ⇒ verdict baseline-only; any unknown ⇒ verdict new
#   #6  classify with NO baseline file ⇒ everything NEW (fail-safe: absence never hides a regression)
#   #7  classify with zero failures ⇒ clean
#   #8  suite scoping: a signature recorded under another suite is not a hit for this one
#   #9  RELEASE_BASELINE_DISABLE=1 ignores the file entirely
#   #10 counts + end-to-end: parse real pytest output against a real baseline file
#
# Run: bash bin/test-baseline-lib.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-baseline-lib.sh
source "$HERE/release-baseline-lib.sh"

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1" "missing [$3] in: $2";; esac; }
hasnt() { case "$2" in *"$3"*) no "$1" "unexpected [$3] in: $2";; *) ok "$1";; esac; }

TMP="$(mktemp -d -t release-baseline-test-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/proj"; mkdir -p "$ROOT/.release-planning"
BARE="$TMP/bare"; mkdir -p "$BARE"

cat > "$ROOT/.release-planning/test-baselines.json" <<'EOF'
{
  "captured_at": "2026-08-11T10:00:00Z",
  "captured_on": "main@a1b2c3d",
  "suites": {
    "backend": {
      "cmd": "pytest backend/apps -q",
      "failures": [
        {"id": "backend/apps/financeiro/tests/test_dre.py::test_saldo", "error": "AssertionError"},
        {"id": "backend/apps/frota/tests/test_v.py::TestVeiculo::test_placa", "error": "IntegrityError"}
      ]
    },
    "frontend": {
      "cmd": "vitest run",
      "failures": [
        {"id": "src/x.test.tsx > InvoiceList > renders", "error": "TestFailure"}
      ]
    }
  }
}
EOF

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #1 signature shape ──"
eq "id|error"                 "a::b|AssertionError" "$(baseline_signature 'a::b' 'AssertionError')"
eq "trims whitespace"         "a::b|ValueError"     "$(baseline_signature '  a::b  ' '  ValueError ')"
eq "missing error → Failure"  "a::b|Failure"        "$(baseline_signature 'a::b')"

echo "── #2 pytest output → signatures ──"
PYOUT='===== short test summary info =====
FAILED backend/apps/financeiro/tests/test_dre.py::test_saldo - AssertionError: 1 != 2
FAILED backend/apps/frota/tests/test_v.py::TestVeiculo::test_placa - IntegrityError: dup key
ERROR backend/apps/api/tests/test_schema.py::test_spectacular - AttributeError: no attr
2 failed, 118 passed in 42.1s'
SIGS="$(printf '%s\n' "$PYOUT" | baseline_parse_failures django)"
has "FAILED parsed with its error type"  "$SIGS" "test_dre.py::test_saldo|AssertionError"
has "class-nested test id preserved"     "$SIGS" "TestVeiculo::test_placa|IntegrityError"
has "ERROR lines parsed too (collection/import errors are failures)" "$SIGS" "test_spectacular|AttributeError"
hasnt "summary noise ignored" "$SIGS" "118 passed"
eq "exactly 3 signatures" "3" "$(printf '%s\n' "$SIGS" | grep -c .)"

echo "── #3 vitest output → signatures ──"
JSOUT=' ❯ src/x.test.tsx (2)
   × src/x.test.tsx > InvoiceList > renders 12ms
   ✓ src/x.test.tsx > InvoiceList > sorts'
SIGS_JS="$(printf '%s\n' "$JSOUT" | baseline_parse_failures react)"
has "failing case parsed" "$SIGS_JS" "InvoiceList > renders|TestFailure"
hasnt "passing case ignored" "$SIGS_JS" "sorts"

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #4 exact-match semantics (the whole point of id|error) ──"
eq "known failure is a hit" "BASELINE_HIT=yes" \
   "$(baseline_has "$ROOT" 'backend/apps/financeiro/tests/test_dre.py::test_saldo|AssertionError')"
eq "SAME test, DIFFERENT error → NOT a hit (a new bug hiding behind an old red)" "BASELINE_HIT=no" \
   "$(baseline_has "$ROOT" 'backend/apps/financeiro/tests/test_dre.py::test_saldo|IntegrityError')"
eq "unknown test → not a hit" "BASELINE_HIT=no" "$(baseline_has "$ROOT" 'brand/new.py::test_x|ValueError')"

echo "── #5 classify ──"
OUT="$(printf '%s\n' \
  'backend/apps/financeiro/tests/test_dre.py::test_saldo|AssertionError' \
  'backend/apps/frota/tests/test_v.py::TestVeiculo::test_placa|IntegrityError' \
  | baseline_classify "$ROOT")"
has "known failures marked BASELINE" "$OUT" "BASELINE=backend/apps/financeiro/tests/test_dre.py::test_saldo|AssertionError"
has "verdict baseline-only" "$OUT" "BASELINE_VERDICT=baseline-only"
has "new count zero" "$OUT" "NEW_COUNT=0"
hasnt "nothing marked NEW" "$OUT" "NEW="

OUT="$(printf '%s\n' \
  'backend/apps/financeiro/tests/test_dre.py::test_saldo|AssertionError' \
  'backend/apps/novo/tests/test_new.py::test_regression|TypeError' \
  | baseline_classify "$ROOT")"
has "unknown failure marked NEW" "$OUT" "NEW=backend/apps/novo/tests/test_new.py::test_regression|TypeError"
has "verdict new (one unknown poisons the run — correct)" "$OUT" "BASELINE_VERDICT=new"
has "counts split" "$OUT" "NEW_COUNT=1"
has "baseline counted too" "$OUT" "BASELINE_COUNT=1"

echo "── #6 no baseline file → fail-safe (everything NEW) ──"
OUT="$(printf '%s\n' 'any/test.py::t|AssertionError' | baseline_classify "$BARE")"
has "marked NEW" "$OUT" "NEW=any/test.py::t|AssertionError"
has "verdict new" "$OUT" "BASELINE_VERDICT=new"
eq "no file → empty path" "" "$(baseline_file "$BARE")"

echo "── #7 zero failures → clean ──"
OUT="$(printf '' | baseline_classify "$ROOT")"
has "verdict clean" "$OUT" "BASELINE_VERDICT=clean"
has "no new" "$OUT" "NEW_COUNT=0"

echo "── #8 suite scoping ──"
eq "frontend signature is NOT a backend hit" "BASELINE_HIT=no" \
   "$(baseline_has "$ROOT" 'src/x.test.tsx > InvoiceList > renders|TestFailure' backend)"
eq "frontend signature hits under its own suite" "BASELINE_HIT=yes" \
   "$(baseline_has "$ROOT" 'src/x.test.tsx > InvoiceList > renders|TestFailure' frontend)"

echo "── #9 kill switch ──"
eq "DISABLE=1 → file ignored" "" "$(RELEASE_BASELINE_DISABLE=1 baseline_file "$ROOT")"
has "DISABLE=1 → known failure becomes NEW (audit mode)" \
   "$(printf '%s\n' 'backend/apps/financeiro/tests/test_dre.py::test_saldo|AssertionError' \
      | RELEASE_BASELINE_DISABLE=1 baseline_classify "$ROOT")" "BASELINE_VERDICT=new"

echo "── #10 counts + end-to-end (real pytest output vs a real baseline) ──"
eq "3 signatures recorded in total" "3" "$(baseline_count "$ROOT")"
eq "2 recorded for backend"         "2" "$(baseline_count "$ROOT" backend)"
E2E="$(printf '%s\n' "$PYOUT" | baseline_parse_failures django | baseline_classify "$ROOT")"
has "the inherited AssertionError is BASELINE" "$E2E" "BASELINE=backend/apps/financeiro/tests/test_dre.py::test_saldo|AssertionError"
has "the drf-spectacular crash is NEW (never captured)" "$E2E" "NEW=backend/apps/api/tests/test_schema.py::test_spectacular|AttributeError"
has "verdict new — the run broke something" "$E2E" "BASELINE_VERDICT=new"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
