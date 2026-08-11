#!/usr/bin/env bash
# Cross-shell contract test for every release-* lib (v0.24.1).
#
# WHY THIS EXISTS
# The other suites run under `bash`, but the libs are SOURCED by the agent harness — on macOS that
# is **zsh**. The two shells disagree in ways that silently corrupt a function whose STDOUT IS ITS
# CONTRACT. The one that shipped: `local id err` (declaration without assignment) PRINTS the
# variables' previous values in zsh, so from the second loop iteration the parser emitted `id=…`
# lines as if they were test-failure signatures. One inherited failure looked fine; two turned every
# gate RED — precisely the scenario the baseline feature exists for. Bash never showed it.
#
# The rule these tests enforce: for every function whose output is parsed, zsh output == bash output,
# and no `name=value` leakage. Add a case here whenever a lib grows a stdout contract.
#
# Run: bash bin/test-zsh-compat.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0; FAIL=0; SKIP=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "bash=[$2] zsh=[$3]"; }
# A leak looks like a bare `varname=value` LINE (zsh echoing a re-declared local), not like a
# verdict line such as `LOOP=continue` or `profile=fable-opus` — those are the contract.
noleak() {
  if printf '%s\n' "$2" | grep -qE '^(id|err|line|val|sig|hit|recorded|buf|tok|tmp|out|cmd|rc|elapsed|start|end|dir|f|v|s|c|n|i|k|pair|key|suite|root|stack|note|max|age|mt|now|depth|carry|existing|ek|first|new|known|verdict)=' ; then
    no "$1" "leaked local on stdout: $(printf '%s\n' "$2" | grep -mE1 '^[a-z_]+=' || true)"
  else ok "$1"; fi
}

if ! command -v zsh >/dev/null 2>&1; then
  echo "zsh not installed — cross-shell contract UNVERIFIED on this host"
  echo "RESULT: 0 passed, 0 failed (skipped)"
  exit 0
fi

TMP="$(mktemp -d -t release-zsh-test-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/proj"; mkdir -p "$ROOT/.release-planning"

# both shells run the SAME snippet against the SAME fixtures; only the interpreter differs
run_in() {  # $1 shell, $2 lib, $3 snippet, [stdin file]
  local sh="$1" lib="$2" snip="$3" stdin="${4:-/dev/null}"
  "$sh" -c "source '$HERE/$lib'; $snip" < "$stdin" 2>/dev/null
}
both() {  # $1 label, $2 lib, $3 snippet, [stdin file] — asserts identical output + no leakage
  local b z
  b="$(run_in bash "$2" "$3" "${4:-/dev/null}")"
  z="$(run_in zsh  "$2" "$3" "${4:-/dev/null}")"
  eq "$1 — same output in both shells" "$b" "$z"
  noleak "$1 — no leaked assignments (zsh)" "$z"
}

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── baseline lib (the one that broke: multi-failure parsing) ──"
cat > "$TMP/pytest.out" <<'EOF'
===== short test summary info =====
FAILED backend/apps/a/tests/test_x.py::test_one - AssertionError: 1 != 2
FAILED backend/apps/b/tests/test_y.py::TestC::test_two - IntegrityError: dup
FAILED backend/apps/c/tests/test_z.py::test_three[1,2] - TypeError: nope
ERROR  backend/apps/d/tests/test_w.py::test_four - AttributeError: missing
4 failed, 118 passed in 42.1s
EOF
cat > "$ROOT/.release-planning/test-baselines.json" <<'EOF'
{ "suites": { "test": { "failures": [
  {"id": "backend/apps/a/tests/test_x.py::test_one", "error": "AssertionError"},
  {"id": "backend/apps/b/tests/test_y.py::TestC::test_two", "error": "IntegrityError"}
] } } }
EOF
both "parse 4 failures" release-baseline-lib.sh 'baseline_parse_failures django' "$TMP/pytest.out"
Z="$(run_in zsh release-baseline-lib.sh 'baseline_parse_failures django' "$TMP/pytest.out")"
eq "exactly 4 signatures under zsh (not 4 + leaked lines)" "4" "$(printf '%s\n' "$Z" | grep -c .)"
both "classify against a real baseline" release-baseline-lib.sh \
     "baseline_parse_failures django | baseline_classify '$ROOT' test" "$TMP/pytest.out"
both "recorded-signature scan"  release-baseline-lib.sh "baseline_count '$ROOT' test"
both "signature helper"         release-baseline-lib.sh "baseline_signature 'a::b' 'ValueError'"
both "vitest parsing"           release-baseline-lib.sh 'baseline_parse_failures react' "$TMP/pytest.out"

echo "── gate lib (verdict lines are parsed by every loop) ──"
cat > "$ROOT/.release-planning/VERIFY-GATE.yml" <<'EOF'
lint: true
test: printf 'FAILED backend/apps/a/tests/test_x.py::test_one - AssertionError: 1 != 2\nFAILED backend/apps/b/tests/test_y.py::TestC::test_two - IntegrityError: dup\n'; exit 1
EOF
both "run_gate with 2 baselined failures" release-gate-lib.sh "run_gate '$ROOT' | grep -v EVIDENCE"
Z="$(run_in zsh release-gate-lib.sh "run_gate '$ROOT'")"
case "$Z" in *"GATE=GREEN"*) ok "zsh: 2 inherited failures still PASS_BASELINE (the B1 scenario)";;
             *) no "zsh: 2 inherited failures still PASS_BASELINE" "got: $Z";; esac

echo "── loop / model / execenv / progress / planning-sync ──"
both "loop_guard"        release-loop-lib.sh    'loop_guard 2 6 aaa bbb'
both "loop_signature"    release-loop-lib.sh    'loop_signature "pytest failed: assert 1 == 2"'
both "model summary"     release-model-lib.sh   'RELEASE_MODEL_PROFILE=fable-opus release_model_summary'
both "per-task tier"     release-model-lib.sh   'RELEASE_MODEL_PROFILE=fable-opus release_worker_model_for simple'
printf 'test_env_provision: true\ntest_env_max_parallel: 3\ntest_exec_prefix: docker exec app-{label}\n' \
  > "$ROOT/.release-planning/EXEC-ENV.yml"
both "execenv config read"  release-execenv-lib.sh "release_execenv_get '$ROOT' test_exec_prefix"
both "execenv caps"         release-execenv-lib.sh "release_sched_max_parallel '$ROOT'"
both "execenv label"        release-execenv-lib.sh "release_execenv_label 'W1/T02 sess'"
both "execenv prefix"       release-execenv-lib.sh "execenv_prefix '$ROOT' /tmp/wt lbl"
mkdir -p "$TMP/pd"
both "progress write+read"  release-progress-lib.sh \
     "progress_write '$TMP/pd' task=T01 tasks_total=9 >/dev/null; progress_get '$TMP/pd' task; progress_get '$TMP/pd' tasks_total"
both "artifact globs"       release-planning-sync-lib.sh 'planning_artifact_globs'

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
