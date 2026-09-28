#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/release-execenv-lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/project"
BARE="$TMP/bare"
mkdir -p "$ROOT/.release-planning" "$ROOT/worktree" "$BARE"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok: %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf 'FAIL: %s — %s\n' "$1" "$2"; }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2], got [$3]"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) no "$1" "missing [$3] in [$2]" ;; esac; }

echo "── host default ──"
eq "no config uses host" host "$(release_test_harness "$BARE")"
has "host preflight passes" "$(release_execenv_preflight "$BARE")" "EXECENV_PREFLIGHT=ok"
eq "no prefix on host" "" "$(execenv_prefix "$BARE" "$BARE" dev)"
eq "SDK owns zero live environments" 0 "$(release_execenv_max_parallel "$BARE")"

echo "── stable external dev runner ──"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_harness: external
test_exec_prefix: bash {root}/scripts/dev-test {worktree}
test_timeout: 120
EOF
eq "project config selected" "$ROOT/.release-planning/EXEC-ENV.yml" \
  "$(release_execenv_config "$ROOT")"
eq "external mode selected" external "$(release_test_harness "$ROOT")"
has "external preflight passes" "$(release_execenv_preflight "$ROOT")" "EXECENV_PREFLIGHT=ok"
eq "prefix renders current checkout" "bash $ROOT/scripts/dev-test $ROOT/worktree" \
  "$(execenv_prefix "$ROOT" "$ROOT/worktree" dev)"
eq "configured timeout read" 120 "$(release_test_timeout "$ROOT")"
eq "lifecycle remains inactive" "EXECENV=off" "$(release_execenv_active "$ROOT")"

echo "── lifecycle is fail-safe disabled ──"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_harness: managed
test_env_provision: touch {worktree}/SHOULD_NOT_EXIST
test_env_teardown: rm -f {worktree}/SHOULD_NOT_EXIST
test_exec_prefix: docker exec app-{label}
EOF
OUT="$(release_execenv_preflight "$ROOT")"
has "managed mode rejected" "$OUT" "EXECENV_ERROR=managed_harness_disabled_use_existing_dev"
eq "direct legacy provision is disabled" "EXECENV_PROVISION=disabled" \
  "$(execenv_provision "$ROOT" "$ROOT/worktree" old)"
[ ! -e "$ROOT/worktree/SHOULD_NOT_EXIST" ] && ok "legacy command was not evaluated" \
  || no "legacy command was not evaluated" "unexpected marker exists"
has "legacy phase prepare fails safely" \
  "$(execenv_phase_prepare "$ROOT" "$ROOT/worktree" old-session)" \
  "EXECENV_PHASE_PREPARE=failed"

echo "── mixed and phase-local configs are rejected/ignored ──"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_harness: external
test_exec_prefix: bash scripts/dev-test
test_env_provision: docker compose up -d
EOF
has "external lifecycle mix rejected" "$(release_execenv_preflight "$ROOT")" \
  "EXECENV_ERROR=dev_runner_cannot_define_lifecycle_commands"
PHASE="$ROOT/.release-planning/phases/42"
mkdir -p "$PHASE"
printf 'test_harness: managed\ntest_env_provision: docker compose up -d\n' > "$PHASE/EXEC-ENV.yml"
eq "phase override ignored even when env var is set" "$ROOT/.release-planning/EXEC-ENV.yml" \
  "$(RELEASE_PHASE_CONFIG_DIR="$PHASE" release_execenv_config "$ROOT")"

echo "── external compatibility prepare is non-mutating ──"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_harness: external
test_exec_prefix: bash {root}/scripts/dev-test {worktree}
test_timeout: 0
EOF
OUT="$(execenv_phase_prepare "$ROOT" "$ROOT/worktree" ignored-session)"
has "external prepare succeeds" "$OUT" "EXECENV_PHASE_PREPARE=ok"
has "external prefix returned" "$OUT" "EXECENV_PREFIX=bash $ROOT/scripts/dev-test $ROOT/worktree"
eq "compat teardown is non-mutating" "EXECENV_TEARDOWN=skipped" \
  "$(execenv_phase_teardown "$ROOT" "$ROOT/worktree" dev)"
eq "reuse slots are disabled" "EXECENV_REUSE=off" "$(release_execenv_reuse "$ROOT")"

echo "── bounded test execution ──"
QUEUE_NOTICE="$TMP/queue-notice"
OUT="$(run_test_bounded "$ROOT" 'printf dev-ok' "$ROOT" 2>"$QUEUE_NOTICE")"
has "passing command returns zero" "$OUT" "TEST_RC=0"
has "passing command is not hung" "$OUT" "TEST_HUNG=false"
has "unbounded timeout remains reported as unbounded" "$OUT" "TEST_BOUNDED=false"
has "queue waiting notice is emitted before completion" "$(cat "$QUEUE_NOTICE")" "TEST_QUEUE_STATUS=waiting"
OUT_FILE="$(printf '%s\n' "$OUT" | sed -n 's/^TEST_OUTPUT=//p')"
has "captured output is preserved" "$(cat "$OUT_FILE")" "dev-ok"
OUT="$(run_test_bounded "$ROOT" "python3 -c \"print('x' * 65536)\"" "$ROOT")"
OUT_FILE="$(printf '%s\n' "$OUT" | sed -n 's/^TEST_OUTPUT=//p')"
[ "$(wc -c < "$OUT_FILE")" -ge 65537 ] && ok "large output is written directly to its file" \
  || no "large output is written directly to its file" "output was truncated"
OUT="$(run_test_bounded "$ROOT" 'exit 137' "$ROOT")"
has "ordinary rc137 remains a test failure" "$OUT" "TEST_HUNG=false"
has "ordinary rc137 remains visible" "$OUT" "TEST_KILLED=true"

echo "── machine-wide test queue ──"
LOCK="$TMP/release-test.lock"
OWNER_MARKER="$TMP/owner-started"
OWNER_FINISHED="$TMP/owner-finished"
OWNER_META="$TMP/owner.meta"
WAITER_META="$TMP/waiter.meta"
ROOT_A="$TMP/repo-a"
ROOT_B="$TMP/repo-b"
mkdir -p "$ROOT_A" "$ROOT_B"
(
  RELEASE_TEST_LOCK_PATH="$LOCK" run_test_bounded "$ROOT_A" \
    "touch '$OWNER_MARKER'; sleep 2; touch '$OWNER_FINISHED'; printf owner-ok" "$ROOT_A"
) >"$TMP/owner.out" 2>&1 &
OWNER_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$OWNER_MARKER" ] && break; sleep 0.1; done
(
  RELEASE_TEST_LOCK_PATH="$LOCK" run_test_bounded "$ROOT_B" \
    "[ -f '$OWNER_FINISHED' ] || { printf overlap >&2; exit 91; }; printf waiter-ok" "$ROOT_B"
) >"$TMP/waiter.out" 2>&1 &
WAITER_PID=$!
wait "$OWNER_PID"; OWNER_RC=$?
wait "$WAITER_PID"; WAITER_RC=$?
OWNER_OUTPUT_FILE="$(sed -n 's/^TEST_OUTPUT=//p' "$TMP/owner.out")"
WAITER_OUTPUT_FILE="$(sed -n 's/^TEST_OUTPUT=//p' "$TMP/waiter.out")"
eq "different-root owner succeeds" 0 "$OWNER_RC"
eq "different-root waiter runs after owner" 0 "$WAITER_RC"
has "owner output remains preserved" "$(cat "$OWNER_OUTPUT_FILE")" "owner-ok"
has "waiter output preserves queue exclusion" "$(cat "$WAITER_OUTPUT_FILE")" "waiter-ok"
has "waiter records queue metadata" "$(cat "$TMP/waiter.out")" "TEST_QUEUE_WAIT="

(
  RELEASE_TEST_LOCK_PATH="$LOCK" RELEASE_TIMEOUT_COMMAND='sleep 2' \
    python3 "$HERE/release-timeout.py" 10
) >"$TMP/cancel-owner.out" 2>&1 &
CANCEL_OWNER_PID=$!
sleep 0.2
(
  RELEASE_TEST_LOCK_PATH="$LOCK" RELEASE_TEST_META_FILE="$WAITER_META" \
    RELEASE_TIMEOUT_COMMAND='printf should-not-run' \
    python3 "$HERE/release-timeout.py" 10
) >"$TMP/cancel-waiter.out" 2>&1 &
CANCEL_WAITER_PID=$!
sleep 0.2
kill "$CANCEL_WAITER_PID" 2>/dev/null || true
wait "$CANCEL_WAITER_PID" 2>/dev/null; CANCEL_WAITER_RC=$?
wait "$CANCEL_OWNER_PID"; CANCEL_OWNER_RC=$?
eq "queued waiter cancellation is preserved" 130 "$CANCEL_WAITER_RC"
eq "queued waiter cancellation leaves owner intact" 0 "$CANCEL_OWNER_RC"
has "cancelled waiter is never marked acquired" "$(cat "$WAITER_META")" "TEST_QUEUE_STATUS=cancelled"

CANCEL_CHILD_PID="$TMP/cancel-child.pid"
(
  RELEASE_TEST_LOCK_PATH="$LOCK" RELEASE_TIMEOUT_COMMAND="trap '' TERM; (trap '' TERM; sleep 30) & child=\$!; echo \$child > '$CANCEL_CHILD_PID'; wait" \
    python3 "$HERE/release-timeout.py" 0
) >"$TMP/cancel-run.out" 2>&1 &
CANCEL_RUN_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$CANCEL_CHILD_PID" ] && break; sleep 0.1; done
kill "$CANCEL_RUN_PID" 2>/dev/null || true
wait "$CANCEL_RUN_PID" 2>/dev/null; CANCEL_RUN_RC=$?
eq "unbounded cancellation escalates after grace" 130 "$CANCEL_RUN_RC"
[ -f "$CANCEL_CHILD_PID" ] && ! kill -0 "$(cat "$CANCEL_CHILD_PID")" 2>/dev/null && ok "cancellation kills TERM-ignoring descendants" \
  || no "cancellation kills TERM-ignoring descendants" "child process remains alive"

TIMEOUT_META="$TMP/timeout.meta"
CHILD_PID="$TMP/timeout-child.pid"
set +e
RELEASE_TEST_LOCK_PATH="$LOCK" RELEASE_TEST_META_FILE="$TIMEOUT_META" \
  RELEASE_TIMEOUT_COMMAND="sleep 5 & child=\$!; echo \$child > '$CHILD_PID'; wait" \
  python3 "$HERE/release-timeout.py" 1 >"$TMP/timeout.out" 2>&1
TIMEOUT_RC=$?
set -e
eq "timeout preserves deadline exit code" 124 "$TIMEOUT_RC"
[ -f "$CHILD_PID" ] && ! kill -0 "$(cat "$CHILD_PID")" 2>/dev/null && ok "timeout kills owned descendants" \
  || no "timeout kills owned descendants" "child process remains alive"
has "timeout reports actual execution elapsed" "$(cat "$TIMEOUT_META")" "TEST_RUN_ELAPSED="

set +e
RELEASE_TEST_LOCK_PATH="$LOCK" RELEASE_TIMEOUT_COMMAND="trap '' TERM; sleep 30" \
  python3 "$HERE/release-timeout.py" 1 >"$TMP/forced-timeout.out" 2>&1
FORCED_TIMEOUT_RC=$?
set -e
eq "TERM-ignoring deadline returns SIGKILL exit code" 137 "$FORCED_TIMEOUT_RC"

echo "── worktree safety: the runner must SEE the worktree ──"
rm -f "$ROOT/.release-planning/EXEC-ENV.yml"
eq "host harness ⇒ safe" "WORKTREE_SAFE=yes" "$(release_execenv_worktree_safe "$ROOT")"
printf 'test_harness: external\ntest_exec_prefix: docker exec -w /workspaces/app app-django-1\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "external prefix without {worktree} ⇒ unsafe (tests would hit the main checkout)" \
   "WORKTREE_SAFE=no reason=test_exec_prefix_lacks_{worktree}_placeholder" "$(release_execenv_worktree_safe "$ROOT")"
printf 'test_harness: external\ntest_exec_prefix: docker exec -w /workspaces/{worktree} app-django-1\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "external prefix with {worktree} ⇒ safe" "WORKTREE_SAFE=yes" "$(release_execenv_worktree_safe "$ROOT")"
printf 'test_harness: managed\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
has "managed ⇒ unsafe" "$(release_execenv_worktree_safe "$ROOT")" "WORKTREE_SAFE=no"
rm -f "$ROOT/.release-planning/EXEC-ENV.yml"

echo "── worktree placement + host→runner path mapping (quick tests ITS worktree) ──"
eq "host harness ⇒ sibling worktree" "$ROOT/../release-worktrees/quick/q1" "$(release_execenv_worktree_path "$ROOT" q1)"
printf 'test_harness: external\ntest_exec_prefix: docker exec -w {worktree} -e DB_TEST_NAME=test_{label} app-django-1\ntest_root_in_runner: /workspaces/app\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "external harness ⇒ worktree INSIDE the mounted root" "$ROOT/.release-worktrees/quick/q1" "$(release_execenv_worktree_path "$ROOT" q1)"
mkdir -p "$ROOT/.release-worktrees/quick/q1"
eq "root maps to runner root" "/workspaces/app" "$(release_execenv_runner_path "$ROOT" "$ROOT")"
eq "inner worktree maps to runner path" "/workspaces/app/.release-worktrees/quick/q1" "$(release_execenv_runner_path "$ROOT" "$ROOT/.release-worktrees/quick/q1")"
eq "outside path is left as is" "/elsewhere/wt" "$(release_execenv_runner_path "$ROOT" /elsewhere/wt)"
eq "prefix renders the RUNNER path of the worktree + label" \
   "docker exec -w /workspaces/app/.release-worktrees/quick/q1 -e DB_TEST_NAME=test_q1 app-django-1" \
   "$(execenv_prefix "$ROOT" "$ROOT/.release-worktrees/quick/q1" q1)"
eq "in-place phase renders the runner root" \
   "docker exec -w /workspaces/app -e DB_TEST_NAME=test_dev app-django-1" "$(execenv_prefix "$ROOT" "$ROOT" dev)"
eq "safe with {worktree}" "WORKTREE_SAFE=yes" "$(release_execenv_worktree_safe "$ROOT")"
printf 'test_harness: external\ntest_exec_prefix: bash {root}/scripts/dev-test {worktree}\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "no test_root_in_runner ⇒ host paths unchanged" "bash $ROOT/scripts/dev-test /tmp/wt" "$(execenv_prefix "$ROOT" /tmp/wt dev)"
rm -rf "$ROOT/.release-worktrees" "$ROOT/.release-planning/EXEC-ENV.yml"

echo "── external nested mount mapping ──"
CALLER_ROOT="$TMP/caller-root"
MOUNT_ROOT="$TMP/mounted/main-dev"
mkdir -p "$CALLER_ROOT/.release-planning" "$MOUNT_ROOT"
MOUNT_ROOT="$(cd "$MOUNT_ROOT" && pwd -P)"
cat > "$CALLER_ROOT/.release-planning/EXEC-ENV.yml" <<EOF
test_harness: external
test_exec_prefix: docker exec -w {worktree} app-django-1
test_root_in_runner: /workspaces/app
test_host_root: $MOUNT_ROOT
EOF
eq "nested mount receives quick worktree" "$MOUNT_ROOT/.release-worktrees/quick/q2" \
  "$(release_execenv_worktree_path "$CALLER_ROOT" q2)"
mkdir -p "$MOUNT_ROOT/.release-worktrees/quick/q2"
eq "nested mount maps worktree into runner" "/workspaces/app/.release-worktrees/quick/q2" \
  "$(release_execenv_runner_path "$CALLER_ROOT" "$MOUNT_ROOT/.release-worktrees/quick/q2")"
eq "nested mount renders runner root from mount" "docker exec -w /workspaces/app/.release-worktrees/quick/q2 app-django-1" \
  "$(execenv_prefix "$CALLER_ROOT" "$MOUNT_ROOT/.release-worktrees/quick/q2" q2)"
if release_execenv_runner_path "$CALLER_ROOT" "$CALLER_ROOT" >/dev/null; then
  no "caller outside nested mount is rejected" "unexpected runner path"
else
  ok "caller outside nested mount is rejected"
fi
has "phase preparation refuses caller outside nested mount" \
  "$(execenv_phase_prepare "$CALLER_ROOT" "$CALLER_ROOT" nested)" \
  "EXECENV_ERROR=worktree_outside_test_host_root"
has "execute workflow aborts when prefix mapping fails" "$(sed -n '68,82p' "$HERE/../skills/execute/SKILL.md")" \
  "current checkout is outside test_host_root"

echo "── rendering + scheduler compatibility ──"
eq "safe label retained" w1_t02_sess "$(release_execenv_label 'W1/T02 sess')"
eq "render substitutes placeholders" "run /tmp/wt dev $ROOT" \
  "$(release_execenv_render 'run {worktree} {label} {root}' /tmp/wt dev "$ROOT")"
eq "scheduler remains machine bounded" 4 "$(RELEASE_EXEC_CORES=8 release_sched_max_parallel "$ROOT")"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
