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

# ${BASH_SOURCE[0]:-$0}: this suite must be runnable under zsh too — the libs are
# SOURCED by a zsh harness in production, and bash-only path resolution hid a real bug.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

PASS=0; FAIL=0; SKIP=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "bash=[$2] zsh=[$3]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1" "missing [$3] in: $2";; esac; }
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
printf 'test_harness: external\ntest_exec_prefix: docker compose exec -T backend\n' \
  > "$ROOT/.release-planning/EXEC-ENV.yml"
both "execenv config read"  release-execenv-lib.sh "release_execenv_get '$ROOT' test_exec_prefix"
both "execenv caps"         release-execenv-lib.sh "release_sched_max_parallel '$ROOT'"
both "execenv label"        release-execenv-lib.sh "release_execenv_label 'W1/T02 sess'"
both "execenv prefix"       release-execenv-lib.sh "execenv_prefix '$ROOT' /tmp/wt lbl"
mkdir -p "$TMP/pd"
both "progress write+read"  release-progress-lib.sh \
     "progress_write '$TMP/pd' task=T01 tasks_total=9 >/dev/null; progress_get '$TMP/pd' task; progress_get '$TMP/pd' tasks_total"
both "artifact globs"       release-planning-sync-lib.sh 'planning_artifact_globs'

# The real thing, not just the glob list: a phase-scoped round trip. Two zsh-only defects lived
# here — an unmatched glob ABORTS a loop in zsh (the worktree was born without its PLAN), and an
# unquoted variable in a `case` pattern is NOT re-parsed as a glob in zsh (every phase-scoped
# artifact was silently skipped on the way out).
sync_probe() {
  cat <<PROBE
M="\$(mktemp -d)"; W="\$(mktemp -d)"
mkdir -p "\$M/.release-planning/phases/12-inv" "\$M/.release-planning/phases/13-other"
printf 'plan\n'    > "\$M/.release-planning/phases/12-inv/12-PLAN.md"
printf 'locks\n'   > "\$M/.release-planning/RELEASE-LOCKS.md"
planning_sync_in "\$M" "\$W" '12-*' | grep FILES
printf 'summary\n' > "\$W/.release-planning/phases/12-inv/12-SUMMARY.md"
printf 'slice\n'   > "\$W/.release-planning/phases/12-inv/PLAN-SLICE-T1.md"
planning_sync_out "\$W" "\$M" '12-*' | grep FILES
find "\$M/.release-planning/phases" -type f | sed "s|\$M||" | sort
PROBE
}
both "phase-scoped round trip (in → produce → out)" release-planning-sync-lib.sh "$(sync_probe)"
Z="$(run_in zsh release-planning-sync-lib.sh "$(sync_probe)")"
has "zsh: the PLAN reached the worktree"      "$Z" "12-PLAN.md"
has "zsh: the SUMMARY came back to main"      "$Z" "12-SUMMARY.md"
case "$Z" in *PLAN-SLICE*) no "zsh: scratch stayed in the worktree" "PLAN-SLICE leaked to main";;
             *) ok "zsh: scratch stayed in the worktree";; esac

echo "── merge lib (land_branch runs under zsh in production) ──"
# bin/test-session-merge.sh is a bash harness (arrays, bash-only idioms) and is NOT run under zsh;
# these probes cover the LIB itself in both shells, which is what production sources. They also
# cover the lock lifecycle, because the zsh run of that harness reported `locked` where bash
# reported `merged` — a cascade from its own earlier failures, not a lib divergence.
merge_probe() {
  cat <<PROBE
D="\$(mktemp -d)"; cd "\$D" || exit 1
git init -q -b main . >/dev/null 2>&1
git config user.email t@t; git config user.name t
printf 'a\n' > f; git add .; git commit -qm init
git branch -q feat/x; git worktree add -q wt feat/x >/dev/null 2>&1
( cd wt && printf 'b\n' > g && git add . && git commit -qm work ) >/dev/null 2>&1
land_branch feat/x "\$D/wt" main | tail -1
git -C "\$D" log --oneline main | wc -l | tr -d ' '
PROBE
}
both "land_branch happy path + resulting history" release-merge-lib.sh "$(merge_probe)"
Z="$(run_in zsh release-merge-lib.sh "$(merge_probe)")"
has "zsh: the branch actually landed" "$Z" "RESULT=merged"

dirty_probe() {
  cat <<PROBE
D="\$(mktemp -d)"; cd "\$D" || exit 1
git init -q -b main . >/dev/null 2>&1
git config user.email t@t; git config user.name t
printf 'a\n' > f; git add .; git commit -qm init
git branch -q feat/y; git worktree add -q wt feat/y >/dev/null 2>&1
( cd wt && printf 'b\n' > g && git add . && git commit -qm work ) >/dev/null 2>&1
printf 'uncommitted\n' > f            # base is dirty ⇒ must HOLD, never clobber
land_branch feat/y "\$D/wt" main | tail -1
cat f
PROBE
}
both "land_branch holds on a dirty base (never clobbers)" release-merge-lib.sh "$(dirty_probe)"
Z="$(run_in zsh release-merge-lib.sh "$(dirty_probe)")"
has "zsh: held rather than merged" "$Z" "RESULT=held-dirty"
has "zsh: the user's uncommitted work is intact" "$Z" "uncommitted"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
