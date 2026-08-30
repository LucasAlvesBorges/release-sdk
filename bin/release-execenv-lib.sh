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

execenv_prefix() {  # $1 root, $2 worktree, $3 label → stable external prefix
  local tpl
  tpl="$(release_execenv_get "${1:-.}" test_exec_prefix)"
  [ -n "$tpl" ] || return 0
  release_execenv_render "$tpl" "${2:-}" "${3:-dev}" "${1:-.}"
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
  local root="${1:-.}" cmd="${2:-}" cwd="${3:-.}" t runner rc start end elapsed builtin=0
  t="$(release_test_timeout "$root")"
  runner="$(release_timeout_cmd "$t")"
  start="$(date +%s 2>/dev/null)"; : "${start:=0}"
  if [ -z "$runner" ] && [ "$t" != 0 ] && command -v python3 >/dev/null 2>&1 \
    && [ -f "$_RELEASE_EXECENV_LIB_DIR/release-timeout.py" ]; then
    builtin=1
    _TEST_OUT="$( ( cd "$cwd" 2>/dev/null && RELEASE_TIMEOUT_COMMAND="$cmd" \
      python3 "$_RELEASE_EXECENV_LIB_DIR/release-timeout.py" "$t" ) </dev/null 2>&1 )"; rc=$?
  else
    _TEST_OUT="$( ( cd "$cwd" 2>/dev/null && eval "$runner $cmd" ) </dev/null 2>&1 )"; rc=$?
  fi
  end="$(date +%s 2>/dev/null)"; : "${end:=$start}"
  elapsed=$(( end - start ))
  local outf
  outf="$(mktemp -t release-test-XXXXXX)"
  printf '%s\n' "$_TEST_OUT" > "$outf"
  echo "TEST_OUTPUT=$outf"
  if [ -n "$runner" ] || [ "$builtin" = 1 ]; then echo "TEST_BOUNDED=true"
  else echo "TEST_BOUNDED=false"
  fi
  case "$rc" in
    124)
      echo "TEST_HUNG=true"; echo "TEST_ELAPSED=$elapsed"; echo "TEST_TIMEOUT=$t"
      echo "TEST_CMD=$cmd"; echo "TEST_RC=$rc"
      ;;
    137)
      if [ -n "$runner" ] || [ "$builtin" = 1 ]; then echo "TEST_HUNG=true"
      else echo "TEST_HUNG=false"
      fi
      echo "TEST_KILLED=true"; echo "TEST_ELAPSED=$elapsed"; echo "TEST_TIMEOUT=$t"
      echo "TEST_CMD=$cmd"; echo "TEST_RC=$rc"
      echo "TEST_NOTE=rc137 is SIGKILL — timeout follow-up, OOM killer, or external kill"
      ;;
    *)
      echo "TEST_HUNG=false"; echo "TEST_ELAPSED=$elapsed"; echo "TEST_RC=$rc"
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
