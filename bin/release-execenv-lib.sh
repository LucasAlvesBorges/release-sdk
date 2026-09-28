#!/usr/bin/env bash
# release-execenv-lib.sh — stable project development runner for /release:* tests.
#
# The SDK consumes an environment that the developer already owns. It never provisions or tears
# down Docker containers, Compose projects, databases, Redis instances, virtualenvs or phase-local
# harnesses. With no project config, tests run on the host. With `.release-planning/EXEC-ENV.yml`,
# the only active mode is `test_harness: external` plus a stable `test_exec_prefix`.

_RELEASE_EXECENV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

release_execenv_config() {  # $1 root → project EXEC-ENV.yml or empty
  [ "${RELEASE_EXECENV_DISABLE:-0}" = 1 ] && return 0
  local f="${1:-.}/.release-planning/EXEC-ENV.yml"
  [ -f "$f" ] && printf '%s' "$f"
  return 0
}

release_execenv_get() {  # $1 root, $2 key → raw value (first match wins)
  local cfg line val
  cfg="$(release_execenv_config "${1:-.}")"
  [ -n "$cfg" ] || return 0
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in \#*|'') continue ;; esac
    case "$line" in "$2":*) ;; *) continue ;; esac
    val="${line#*:}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    printf '%s' "$val"
    return 0
  done < "$cfg"
  return 0
}

release_test_harness() {  # $1 root → host | external | managed | invalid
  local root="${1:-.}" cfg mode
  cfg="$(release_execenv_config "$root")"
  [ -n "$cfg" ] || { printf 'host'; return 0; }
  mode="$(release_execenv_get "$root" test_harness)"
  [ -n "$mode" ] || mode=invalid
  printf '%s' "$mode"
  return 0
}

release_execenv_preflight() {  # $1 root → validates a non-owning project dev runner
  local root="${1:-.}" mode provision teardown migrate prefix
  mode="$(release_test_harness "$root")"
  provision="$(release_execenv_get "$root" test_env_provision)"
  teardown="$(release_execenv_get "$root" test_env_teardown)"
  migrate="$(release_execenv_get "$root" test_env_migrate)"
  prefix="$(release_execenv_get "$root" test_exec_prefix)"
  echo "EXECENV_HARNESS=$mode"
  case "$mode" in
    external)
      [ -n "$prefix" ] || {
        echo "EXECENV_PREFLIGHT=failed"
        echo "EXECENV_ERROR=external_requires_test_exec_prefix"
        return 0
      }
      [ -z "$provision$teardown$migrate" ] || {
        echo "EXECENV_PREFLIGHT=failed"
        echo "EXECENV_ERROR=dev_runner_cannot_define_lifecycle_commands"
        return 0
      }
      ;;
    host)
      [ -z "$provision$teardown$migrate$prefix" ] || {
        echo "EXECENV_PREFLIGHT=failed"
        echo "EXECENV_ERROR=host_harness_cannot_define_environment_commands"
        return 0
      }
      ;;
    managed)
      echo "EXECENV_PREFLIGHT=failed"
      echo "EXECENV_ERROR=managed_harness_disabled_use_existing_dev"
      return 0
      ;;
    *)
      echo "EXECENV_PREFLIGHT=failed"
      echo "EXECENV_ERROR=unknown_test_harness"
      return 0
      ;;
  esac
  echo "EXECENV_PREFLIGHT=ok"
  return 0
}

release_execenv_active() {  # compatibility: SDK-owned live environments no longer exist
  echo "EXECENV=off"
  return 0
}

release_execenv_label() {  # compatibility renderer label: [a-z0-9_], ≤32 chars
  local s="${*:-dev}"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_' | tr -s '_' \
       | sed -e 's/^_*//' -e 's/_*$//')"
  [ -n "$s" ] || s=dev
  case "$s" in [0-9]*) s="e$s" ;; esac
  printf '%s' "${s:0:32}"
  return 0
}

release_execenv_render() {  # $1 template, $2 worktree, $3 label, [$4 root]
  local tpl="${1:-}" wt="${2:-}" label="${3:-dev}" root="${4:-}"
  tpl="${tpl//\{worktree\}/$wt}"
  tpl="${tpl//\{label\}/$label}"
  tpl="${tpl//\{root\}/$root}"
  printf '%s' "$tpl"
  return 0
}

# A sibling worktree is only testable when the runner can SEE it. hubus mounted one checkout into
# its container and `docker exec -w /workspaces/moblity ...` had no `{worktree}` placeholder, so
# every quick worktree "passed pytest" against the MAIN checkout. host harness → safe; external →
# safe only when the prefix template renders the worktree path.
# Where a quick unit's worktree must live so the runner can test IT. A host runner sees any path,
# so the classic sibling `<root>/../release-worktrees/quick/<label>` keeps the main tree's tooling
# out of the unit. An external runner (docker exec) only sees what is mounted — the main checkout —
# so the worktree goes INSIDE it: `<root>/.release-worktrees/quick/<label>` (excluded from git
# status via .git/info/exclude by the caller).
release_execenv_worktree_path() {  # $1 root, $2 label → host path for the unit worktree
  local root="${1:-.}" label="${2:-unit}" host_root
  host_root="$(release_execenv_host_root "$root")" || return 1
  case "$(release_test_harness "$root")" in
    external) printf '%s/.release-worktrees/quick/%s' "$host_root" "$label" ;;
    *)        printf '%s/../release-worktrees/quick/%s' "$root" "$label" ;;
  esac
  return 0
}

# An external runner may mount a stable inner checkout rather than its caller root. This optional
# key makes that mount explicit so an unmapped host path cannot be rendered as a container path.
release_execenv_host_root() {  # $1 root → mounted host root (or root when no override exists)
  local root="${1:-.}" configured
  configured="$(release_execenv_get "$root" test_host_root)"
  [ -n "$configured" ] || { printf '%s' "$root"; return 0; }
  [ -d "$configured" ] || return 1
  cd "$configured" 2>/dev/null && pwd -P
}

# Map a host worktree path to the path the runner sees. `test_root_in_runner` is the container
# path of {root} (hubus: /workspaces/moblity); a worktree inside {root} renders as
# `<test_root_in_runner>/<relative>`, {root} itself as `<test_root_in_runner>`. Without the key the
# host path is used unchanged (host wrappers such as `bash scripts/dev-test {worktree}`).
release_execenv_runner_path() {  # $1 root, $2 host path → runner-visible path
  local root="${1:-.}" p="${2:-}" mapped rel host_root configured_host
  mapped="$(release_execenv_get "$root" test_root_in_runner)"
  [ -n "$mapped" ] && [ -n "$p" ] || { printf '%s' "$p"; return 0; }
  configured_host="$(release_execenv_get "$root" test_host_root)"
  host_root="$(release_execenv_host_root "$root")" || return 1
  host_root="$(cd "$host_root" 2>/dev/null && pwd -P || printf '%s' "$host_root")"
  p="$(cd "$p" 2>/dev/null && pwd -P || printf '%s' "$p")"
  case "$p" in
    "$host_root") printf '%s' "$mapped" ;;
    "$host_root"/*) rel="${p#"$host_root"/}"; printf '%s/%s' "$mapped" "$rel" ;;
    *)
      [ -n "$configured_host" ] && return 1
      printf '%s' "$p" ;;  # legacy default: wrappers may intentionally see another host path
  esac
  return 0
}

release_execenv_worktree_safe() {  # $1 root → WORKTREE_SAFE=yes | WORKTREE_SAFE=no reason=<why>
  local root="${1:-.}" harness tpl
  harness="$(release_test_harness "$root")"
  case "$harness" in
    host) echo "WORKTREE_SAFE=yes"; return 0 ;;
    external)
      tpl="$(release_execenv_get "$root" test_exec_prefix)"
      case "$tpl" in
        *"{worktree}"*) echo "WORKTREE_SAFE=yes"; return 0 ;;
        *) echo "WORKTREE_SAFE=no reason=test_exec_prefix_lacks_{worktree}_placeholder"; return 0 ;;
      esac ;;
    *) echo "WORKTREE_SAFE=no reason=harness_${harness}"; return 0 ;;
  esac
}

execenv_prefix() {  # $1 root, $2 worktree, $3 label → stable external prefix
  local tpl wt host_root
  tpl="$(release_execenv_get "${1:-.}" test_exec_prefix)"
  [ -n "$tpl" ] || return 0
  wt="$(release_execenv_runner_path "${1:-.}" "${2:-}")" || return 1
  host_root="$(release_execenv_host_root "${1:-.}")" || return 1
  release_execenv_render "$tpl" "$wt" "${3:-dev}" "$(release_execenv_runner_path "${1:-.}" "$host_root")"
  return 0
}

release_exec_cores() {
  local n="${RELEASE_EXEC_CORES:-}"
  if [ -z "$n" ]; then
    n="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" \
      || n="$(sysctl -n hw.ncpu 2>/dev/null)" \
      || n="$(nproc 2>/dev/null)" || n=""
  fi
  case "$n" in ''|*[!0-9]*|0) n=1 ;; esac
  printf '%s' "$n"
  return 0
}

release_default_max_parallel() {  # legacy host-only scheduler bound
  local c half
  c="$(release_exec_cores)"
  half=$(( c / 2 ))
  [ "$half" -lt 1 ] && half=1
  [ "$half" -gt 8 ] && half=8
  printf '%s' "$half"
  return 0
}

release_execenv_max_parallel() { echo 0; return 0; }
release_sched_max_parallel() { release_default_max_parallel; return 0; }

release_test_timeout() {  # $1 root → seconds; default 900; 0 = unbounded
  local v
  v="$(release_execenv_get "${1:-.}" test_timeout)"
  case "$v" in ''|*[!0-9]*) echo 900 ;; *) echo "$v" ;; esac
  return 0
}

release_timeout_cmd() {
  local t="${1:-0}"
  [ "$t" != 0 ] || return 0
  if command -v timeout >/dev/null 2>&1; then printf 'timeout -k 10 %s' "$t"
  elif command -v gtimeout >/dev/null 2>&1; then printf 'gtimeout -k 10 %s' "$t"
  fi
  return 0
}

release_timeout_available() {
  local t="${1:-0}"
  [ "$t" != 0 ] || { echo no; return 0; }
  if [ -n "$(release_timeout_cmd "$t")" ]; then echo yes
  elif command -v python3 >/dev/null 2>&1 \
    && [ -f "$_RELEASE_EXECENV_LIB_DIR/release-timeout.py" ]; then echo yes
  else echo no
  fi
  return 0
}

run_test_bounded() {  # $1 root, $2 command, [$3 cwd] → structured TEST_* verdict
  local root="${1:-.}" cmd="${2:-}" cwd="${3:-.}" t runner rc start end elapsed builtin=0 meta outf queue_wait run_elapsed timed_out
  t="$(release_test_timeout "$root")"
  runner="$(release_timeout_cmd "$t")"
  start="$(date +%s 2>/dev/null)"; : "${start:=0}"
  echo "TEST_QUEUE_STATUS=waiting" >&2
  meta="$(mktemp -t release-test-meta-XXXXXX)"
  outf="$(mktemp -t release-test-XXXXXX)"
  if command -v python3 >/dev/null 2>&1 \
    && [ -f "$_RELEASE_EXECENV_LIB_DIR/release-timeout.py" ]; then
    builtin=1
    ( cd "$cwd" 2>/dev/null && RELEASE_TEST_META_FILE="$meta" RELEASE_TIMEOUT_COMMAND="$cmd" \
      python3 "$_RELEASE_EXECENV_LIB_DIR/release-timeout.py" "$t" ) </dev/null >"$outf" 2>&1; rc=$?
  else
    ( cd "$cwd" 2>/dev/null && eval "$runner $cmd" ) </dev/null >"$outf" 2>&1; rc=$?
  fi
  end="$(date +%s 2>/dev/null)"; : "${end:=$start}"
  elapsed=$(( end - start ))
  queue_wait="$(sed -n 's/^TEST_QUEUE_WAIT=//p' "$meta" 2>/dev/null)"
  run_elapsed="$(sed -n 's/^TEST_RUN_ELAPSED=//p' "$meta" 2>/dev/null)"
  timed_out="$(sed -n 's/^TEST_TIMED_OUT=//p' "$meta" 2>/dev/null)"
  rm -f "$meta"
  echo "TEST_OUTPUT=$outf"
  if [ "$t" != 0 ] && { [ -n "$runner" ] || [ "$builtin" = 1 ]; }; then echo "TEST_BOUNDED=true"
  else echo "TEST_BOUNDED=false"
  fi
  [ -n "$queue_wait" ] && echo "TEST_QUEUE_WAIT=$queue_wait"
  [ -n "$run_elapsed" ] && echo "TEST_RUN_ELAPSED=$run_elapsed"
  [ -n "$queue_wait" ] && echo "TEST_QUEUE_STATUS=acquired"
  case "$rc" in
    124)
      if [ "$timed_out" = true ]; then echo "TEST_HUNG=true"; else echo "TEST_HUNG=false"; fi
      echo "TEST_ELAPSED=${run_elapsed:-$elapsed}"; echo "TEST_TIMEOUT=$t"
      echo "TEST_CMD=$cmd"; echo "TEST_RC=$rc"
      ;;
    137)
      if [ "$timed_out" = true ]; then echo "TEST_HUNG=true"
      else echo "TEST_HUNG=false"
      fi
      echo "TEST_KILLED=true"; echo "TEST_ELAPSED=${run_elapsed:-$elapsed}"; echo "TEST_TIMEOUT=$t"
      echo "TEST_CMD=$cmd"; echo "TEST_RC=$rc"
      if [ "$timed_out" = true ]; then
        echo "TEST_NOTE=rc137 is SIGKILL after the owned test deadline"
      else
        echo "TEST_NOTE=rc137 is SIGKILL — likely OOM killer or external kill; test failure preserved"
      fi
      ;;
    *)
      echo "TEST_HUNG=false"; echo "TEST_ELAPSED=${run_elapsed:-$elapsed}"; echo "TEST_RC=$rc"
      ;;
  esac
  return 0
}

# Compatibility entry points are deliberately non-mutating. Old workflow prompts fail safely
# instead of running legacy lifecycle commands.
execenv_provision() { echo "EXECENV_PROVISION=disabled"; return 0; }
execenv_teardown() { echo "EXECENV_TEARDOWN=skipped"; return 0; }
execenv_migrate_cmd() { return 0; }
release_execenv_reuse() { echo "EXECENV_REUSE=off"; return 0; }
release_execenv_slot_label() { release_execenv_label "s${2:-1}_${1:-dev}"; return 0; }
release_execenv_slot_path() { printf '%s/slot-s%s' "${1:-.}" "${2:-1}"; return 0; }

execenv_phase_prepare() {  # compatibility: external/host only, never provisions
  local root="${1:-.}" wt="${2:-}" check mode label prefix
  check="$(release_execenv_preflight "$root")"
  case "$check" in
    *EXECENV_PREFLIGHT=ok*) ;;
    *) printf '%s\n' "$check"; echo "EXECENV_PHASE_PREPARE=failed"; return 0 ;;
  esac
  mode="$(release_test_harness "$root")"
  label="$(release_execenv_label dev)"
  prefix="$(execenv_prefix "$root" "$wt" "$label")"
  echo "EXECENV_PHASE_PREPARE=ok"
  echo "EXECENV_HARNESS=$mode"
  echo "EXECENV_LABEL=$label"
  echo "EXECENV_PREFIX=$prefix"
  return 0
}

execenv_phase_teardown() { echo "EXECENV_TEARDOWN=skipped"; return 0; }
