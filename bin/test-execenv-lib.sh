#!/usr/bin/env bash
# Contract test for the per-worktree test-environment substrate (v0.22.0).
#
# SOURCES the real shipped engine — bin/release-execenv-lib.sh — so there is NO drift: the code
# under test IS the code agents/wave-executor.md and skills/execute run.
#
# Coverage:
#   #1  no EXEC-ENV.yml ⇒ every function is a no-op (the pre-v0.22.0 behaviour is byte-identical)
#   #2  config discovery + first-colon-only value parsing (values may contain ':' and '#')
#   #3  active/off detection keyed on test_env_provision
#   #4  label sanitization: lowercase, [a-z0-9_], collapsed, trimmed, ≤32, never digit-initial
#   #5  template rendering substitutes {worktree}/{label}/{root} and survives path metacharacters
#   #6  provision actually RUNS the rendered command in the worktree, exit 0 ⇒ ok
#   #7  provision failure ⇒ failed + EXECENV_EVIDENCE file containing the real command output
#   #8  teardown runs, tolerates a vanished worktree, and never reports fatally
#   #9  exec prefix rendering (set ⇒ rendered, unset ⇒ empty ⇒ host-local exec)
#   #10 env cap: machine default when active, 0 when off, explicit override, junk rejection
#   #11 RELEASE_EXECENV_DISABLE=1 forces the whole lib back to no-op
#   #12 machine-derived cap: min(8, max(1, cores/2)), clamped both ends
#   #13 scheduler cap is env-independent and never unlimited; explicit config wins
#
# Run: bash bin/test-execenv-lib.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-execenv-lib.sh
source "$HERE/release-execenv-lib.sh"

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1" "missing [$3] in: $2";; esac; }
hasnt() { case "$2" in *"$3"*) no "$1" "unexpected [$3] in: $2";; *) ok "$1";; esac; }

TMP="$(mktemp -d -t release-execenv-test-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Two roots: BARE (no config — legacy behaviour) and ROOT (configured).
BARE="$TMP/bare"; mkdir -p "$BARE"
ROOT="$TMP/proj"; mkdir -p "$ROOT/.release-planning"
WT="$TMP/proj-wt";  mkdir -p "$WT"

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #1 no EXEC-ENV.yml → total no-op (legacy behaviour preserved) ──"
eq "config empty"            ""                    "$(release_execenv_config "$BARE")"
eq "active off"              "EXECENV=off"         "$(release_execenv_active "$BARE")"
eq "prefix empty"            ""                    "$(execenv_prefix "$BARE" "$WT" lbl)"
eq "provision skipped"       "EXECENV_PROVISION=skipped" "$(execenv_provision "$BARE" "$WT" lbl)"
eq "teardown skipped"        "EXECENV_TEARDOWN=skipped"  "$(execenv_teardown "$BARE" "$WT" lbl)"
eq "env cap 0 (no envs to cap — host-local exec)" "0" "$(release_execenv_max_parallel "$BARE")"

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #2 config discovery + first-colon-only parsing ──"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<EOF
# comment line: ignored
test_env_provision: touch {worktree}/.provisioned-{label} && printf 'ready %s' {label} > {worktree}/.state
  test_env_teardown: rm -f {worktree}/.provisioned-{label}
test_exec_prefix: docker exec app-{label} -v {worktree}/backend:/app
test_env_max_parallel: 3
EOF
eq "config found" "$ROOT/.release-planning/EXEC-ENV.yml" "$(release_execenv_config "$ROOT")"
has "value keeps everything after the FIRST colon" \
    "$(release_execenv_get "$ROOT" test_exec_prefix)" "{worktree}/backend:/app"
eq "indented key still parsed" "rm -f {worktree}/.provisioned-{label}" \
    "$(release_execenv_get "$ROOT" test_env_teardown)"
eq "unknown key → empty" "" "$(release_execenv_get "$ROOT" no_such_key)"

echo "── #3 active detection ──"
eq "provision configured → on" "EXECENV=on" "$(release_execenv_active "$ROOT")"

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #4 label sanitization ──"
eq "lowercased + non-alnum collapsed" "w1_t02_sess" "$(release_execenv_label 'W1/T02 sess')"
eq "leading/trailing separators trimmed" "abc" "$(release_execenv_label '--abc--')"
eq "empty input → 'env'" "env" "$(release_execenv_label '')"
eq "digit-initial gets a letter prefix (Postgres identifier rule)" "e1763_x" \
   "$(release_execenv_label '1763-x')"
LONG="$(release_execenv_label 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')"
eq "truncated to 32" "32" "${#LONG}"

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #5 template rendering ──"
R="$(release_execenv_render 'run -v {worktree}/backend:/app --name x-{label} # in {root}' "$WT" lab "$ROOT")"
has "worktree substituted" "$R" "$WT/backend:/app"
has "label substituted"    "$R" "--name x-lab"
has "root substituted"     "$R" "# in $ROOT"
WEIRD="$TMP/we&ird [dir]"; mkdir -p "$WEIRD"
eq "path metacharacters survive (bash substitution, never sed)" \
   "cd $WEIRD" "$(release_execenv_render 'cd {worktree}' "$WEIRD" l "$ROOT")"

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #6 provision runs the rendered command inside the worktree ──"
OUT="$(execenv_provision "$ROOT" "$WT" w1_t02)"
eq "verdict ok" "EXECENV_PROVISION=ok" "$OUT"
[ -f "$WT/.provisioned-w1_t02" ] && ok "provision side-effect landed in the worktree" \
  || no "provision side-effect landed in the worktree" "missing $WT/.provisioned-w1_t02"
eq "label reached the command" "ready w1_t02" "$(cat "$WT/.state")"

echo "── #7 provision failure → evidence file with the real output ──"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_env_provision: echo "boom: db template missing" >&2; exit 7
test_env_teardown: exit 3
EOF
OUT="$(execenv_provision "$ROOT" "$WT" bad)"
has "verdict failed" "$OUT" "EXECENV_PROVISION=failed"
EV="$(printf '%s\n' "$OUT" | sed -n 's/^EXECENV_EVIDENCE=//p')"
[ -n "$EV" ] && [ -f "$EV" ] && ok "evidence file written" || no "evidence file written" "got [$EV]"
has "evidence carries the failing command output" "$(cat "$EV")" "boom: db template missing"
has "evidence carries the exit code" "$(cat "$EV")" "# exit: 7"
rm -f "$EV"
eq "missing worktree → failed (never silently 'ok')" "EXECENV_PROVISION=failed" \
   "$(execenv_provision "$ROOT" "$TMP/does-not-exist" lbl)"

echo "── #8 teardown is best-effort and never fatal ──"
eq "non-zero teardown reported, not raised" "EXECENV_TEARDOWN=failed" \
   "$(execenv_teardown "$ROOT" "$WT" bad)"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_env_provision: true
test_env_teardown: printf 'gone-{label}' > TEARDOWN_MARK
EOF
OUT="$(execenv_teardown "$ROOT" "$TMP/vanished-worktree" zz)"
eq "vanished worktree → teardown still runs (falls back to root cwd)" "EXECENV_TEARDOWN=ok" "$OUT"
eq "teardown ran with the label rendered" "gone-zz" "$(cat "$ROOT/TEARDOWN_MARK")"

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #9 exec prefix ──"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_env_provision: true
test_exec_prefix: docker exec app-{label}
EOF
eq "rendered prefix" "docker exec app-w2_t07" "$(execenv_prefix "$ROOT" "$WT" w2_t07)"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_env_provision: true
EOF
eq "no prefix configured → empty (host-local exec)" "" "$(execenv_prefix "$ROOT" "$WT" w2_t07)"

echo "── #10 env cap ──"
printf 'test_env_provision: true\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "active, unset → machine default (16 cores → 8)" "8" \
   "$(RELEASE_EXEC_CORES=16 release_execenv_max_parallel "$ROOT")"
printf 'test_env_provision: true\ntest_env_max_parallel: 2\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "explicit override honored" "2" "$(release_execenv_max_parallel "$ROOT")"
printf 'test_env_provision: true\ntest_env_max_parallel: lots\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "junk value → machine default (4 cores → 2)" "2" \
   "$(RELEASE_EXEC_CORES=4 release_execenv_max_parallel "$ROOT")"

echo "── #11 kill switch ──"
printf 'test_env_provision: touch {worktree}/SHOULD_NOT_EXIST\ntest_exec_prefix: docker exec x\n' \
  > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "DISABLE=1 → off"     "EXECENV=off" "$(RELEASE_EXECENV_DISABLE=1 release_execenv_active "$ROOT")"
eq "DISABLE=1 → skipped" "EXECENV_PROVISION=skipped" \
   "$(RELEASE_EXECENV_DISABLE=1 execenv_provision "$ROOT" "$WT" lbl)"
eq "DISABLE=1 → no prefix" "" "$(RELEASE_EXECENV_DISABLE=1 execenv_prefix "$ROOT" "$WT" lbl)"
[ -f "$WT/SHOULD_NOT_EXIST" ] && no "kill switch prevented the side effect" "file was created" \
  || ok "kill switch prevented the side effect"

echo "── #12 machine-derived cap: min(8, max(1, cores/2)) ──"
eq "16 cores → 8"                "8" "$(RELEASE_EXEC_CORES=16 release_default_max_parallel)"
eq "32 cores → clamped to 8"     "8" "$(RELEASE_EXEC_CORES=32 release_default_max_parallel)"
eq "8 cores → 4"                 "4" "$(RELEASE_EXEC_CORES=8  release_default_max_parallel)"
eq "4 cores → 2"                 "2" "$(RELEASE_EXEC_CORES=4  release_default_max_parallel)"
eq "2 cores → 1"                 "1" "$(RELEASE_EXEC_CORES=2  release_default_max_parallel)"
eq "1 core → 1 (never 0)"        "1" "$(RELEASE_EXEC_CORES=1  release_default_max_parallel)"
eq "junk core count → 1 core → 1" "1" "$(RELEASE_EXEC_CORES=banana release_default_max_parallel)"
CORES="$(release_exec_cores)"
case "$CORES" in ''|*[!0-9]*|0) no "detected core count is a positive integer" "got [$CORES]";; *) ok "detected core count is a positive integer ($CORES)";; esac

echo "── #13 scheduler cap (env-independent, never unlimited) ──"
eq "no EXEC-ENV.yml at all → machine default, NOT unlimited" "8" \
   "$(RELEASE_EXEC_CORES=16 release_sched_max_parallel "$BARE")"
printf 'test_env_provision: true\ntest_env_max_parallel: 3\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "explicit config below default wins" "3" "$(RELEASE_EXEC_CORES=16 release_sched_max_parallel "$ROOT")"
printf 'test_env_provision: true\ntest_env_max_parallel: 12\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "explicit config above default also wins (user sized their machine)" "12" \
   "$(RELEASE_EXEC_CORES=16 release_sched_max_parallel "$ROOT")"
printf 'test_env_provision: true\ntest_env_max_parallel: 0\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "0 = unlimited ENVS is not unlimited AGENTS → machine default" "2" \
   "$(RELEASE_EXEC_CORES=4 release_sched_max_parallel "$ROOT")"
SC="$(RELEASE_EXEC_CORES=1 release_sched_max_parallel "$BARE")"
[ "$SC" -ge 1 ] && ok "scheduler cap is always >=1 (never stalls the scheduler)" \
  || no "scheduler cap is always >=1" "got [$SC]"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
