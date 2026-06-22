#!/usr/bin/env bash
# Contract test for the objective verification GATE (v0.18.0).
#
# SOURCES the real shipped engine — bin/release-gate-lib.sh — so there is NO faithful-slice drift:
# the code under test IS the code skills/{loop,execute,quick} + agents/code-fixer run.
#
# Coverage:
#   #1  stack detection: django (manage.py), react (package.json react), fullstack, unknown
#   #2  default gate is used when no VERIFY-GATE.yml present (django default mentions ruff + pytest)
#   #3  VERIFY-GATE.yml overrides the default; comments + blank lines ignored; order preserved
#   #4  all steps exit 0 → GATE=GREEN, one PASS line per step, no evidence file
#   #5  a step exits non-zero → GATE=RED + GATE_EVIDENCE file with the failing command's output
#   #6  fail-fast (default): stops at the first red step; later steps NOT run
#   #7  GATE_FAILFAST=0: every step runs even after a red
#   #8  first-colon split: a command containing a colon runs intact
#   #9  unknown stack + no config → empty `GATE=` verdict (caller decides)
#
# Run: bash bin/test-gate-lib.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-gate-lib.sh
source "$HERE/release-gate-lib.sh"

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1" "missing [$3] in: $2";; esac; }
hasnt() { case "$2" in *"$3"*) no "$1" "unexpected [$3] in: $2";; *) ok "$1";; esac; }

SBX="$(mktemp -d)"; trap 'rm -rf "$SBX"' EXIT

# verdict() — echo just the terminal GATE= value from a run_gate output blob
verdict() { printf '%s\n' "$1" | sed -n 's/^GATE=//p' | tail -1; }

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #1 stack detection ──"
DJ="$SBX/dj"; mkdir -p "$DJ"; : > "$DJ/manage.py"
eq "manage.py → django" "django" "$(release_detect_stack "$DJ")"
RC="$SBX/rc"; mkdir -p "$RC"; printf '{"dependencies":{"react":"18"}}\n' > "$RC/package.json"
eq "package.json react → react" "react" "$(release_detect_stack "$RC")"
FS="$SBX/fs"; mkdir -p "$FS/backend" "$FS/frontend"; : > "$FS/backend/manage.py"
printf '{"dependencies":{"react":"18"}}\n' > "$FS/frontend/package.json"
eq "backend/manage.py + frontend react → fullstack" "fullstack" "$(release_detect_stack "$FS")"
UN="$SBX/un"; mkdir -p "$UN"
eq "empty dir → unknown" "unknown" "$(release_detect_stack "$UN")"

echo "── #2 default gate used when no config (django) ──"
DEF="$(release_resolve_gate "$DJ")"
has "django default mentions ruff" "$DEF" "ruff"
has "django default mentions pytest" "$DEF" "pytest"
has "django default mentions makemigrations" "$DEF" "makemigrations"

echo "── #3 VERIFY-GATE.yml overrides default + ignores comments/blanks, keeps order ──"
CFG="$SBX/cfg"; mkdir -p "$CFG/.release-planning"
cat > "$CFG/.release-planning/VERIFY-GATE.yml" <<'YML'
# project gate
lint: true

test: true
YML
RES="$(release_resolve_gate "$CFG")"
hasnt "default NOT used when config present (no ruff)" "$RES" "ruff"
has "config step lint present" "$RES" "lint: true"
has "config step test present" "$RES" "test: true"
hasnt "comment line dropped" "$RES" "project gate"
eq "blank lines dropped (2 real steps)" "2" "$(printf '%s\n' "$RES" | grep -c .)"

echo "── #4 all green → GATE=GREEN, PASS per step, no evidence ──"
GRN="$SBX/grn"; mkdir -p "$GRN/.release-planning"
printf 'lint: true\ntest: true\n' > "$GRN/.release-planning/VERIFY-GATE.yml"
OUT="$(run_gate "$GRN")"
eq "verdict GREEN" "GREEN" "$(verdict "$OUT")"
has "lint PASS" "$OUT" "GATE_STEP=lint PASS"
has "test PASS" "$OUT" "GATE_STEP=test PASS"
hasnt "no evidence on green" "$OUT" "GATE_EVIDENCE="

echo "── #5 a red step → GATE=RED + evidence file with the failing output ──"
RED="$SBX/red"; mkdir -p "$RED/.release-planning"
cat > "$RED/.release-planning/VERIFY-GATE.yml" <<'YML'
lint: true
test: sh -c 'echo BOOM-FAILURE >&2; exit 7'
YML
OUT="$(run_gate "$RED")"
eq "verdict RED" "RED" "$(verdict "$OUT")"
has "test FAIL" "$OUT" "GATE_STEP=test FAIL"
EV="$(printf '%s\n' "$OUT" | sed -n 's/^GATE_EVIDENCE=//p' | head -1)"
{ [ -n "$EV" ] && [ -f "$EV" ]; } && ok "evidence file created" || no "no evidence file" "$EV"
has "evidence captures the failing output" "$(cat "$EV" 2>/dev/null)" "BOOM-FAILURE"
has "evidence records the exit code" "$(cat "$EV" 2>/dev/null)" "exit: 7"

echo "── #6 fail-fast (default): stop at first red, later step not run ──"
FF="$SBX/ff"; mkdir -p "$FF/.release-planning"
printf 'a: false\nb: true\n' > "$FF/.release-planning/VERIFY-GATE.yml"
OUT="$(run_gate "$FF")"
has "step a ran (FAIL)" "$OUT" "GATE_STEP=a FAIL"
hasnt "step b NOT run (fail-fast)" "$OUT" "GATE_STEP=b"
eq "fail-fast verdict RED" "RED" "$(verdict "$OUT")"

echo "── #7 GATE_FAILFAST=0: run every step despite a red ──"
OUT="$(GATE_FAILFAST=0 run_gate "$FF")"
has "step a ran" "$OUT" "GATE_STEP=a FAIL"
has "step b ALSO ran (no fail-fast)" "$OUT" "GATE_STEP=b PASS"
eq "no-failfast verdict still RED" "RED" "$(verdict "$OUT")"

echo "── #8 first-colon split: command containing a colon runs intact ──"
COL="$SBX/col"; mkdir -p "$COL/.release-planning"
printf 'unit: sh -c "echo a:b:c"\n' > "$COL/.release-planning/VERIFY-GATE.yml"
OUT="$(run_gate "$COL")"
eq "colon-in-command → GREEN" "GREEN" "$(verdict "$OUT")"
has "step name parsed as 'unit'" "$OUT" "GATE_STEP=unit PASS"

echo "── #9 unknown stack + no config → empty verdict ──"
OUT="$(run_gate "$UN")"
eq "empty verdict when nothing resolves" "" "$(verdict "$OUT")"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
