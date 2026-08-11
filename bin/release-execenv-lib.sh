#!/usr/bin/env bash
# release-execenv-lib.sh — per-worktree TEST ENVIRONMENT provisioning for /release:* execution.
#
# SINGLE SOURCE OF TRUTH for "how do I get a working test environment inside THIS worktree?".
# Sourced by:
#   - agents/wave-executor.md    (provision one env per parallel sub-worktree, teardown after cherry-pick)
#   - skills/execute/SKILL.md    (provision the env of the session-scoped phase worktree)
#   - bin/test-execenv-lib.sh    (the contract test SOURCES this file — no faithful-slice drift)
#
# WHY THIS EXISTS
# Wave parallelism assumes a task's tests can run inside the task's own git worktree. That holds
# when tests run on the host. It does NOT hold when tests run inside a container/VM that mounts ONE
# checkout and talks to ONE database: sub-worktree code is invisible to that container, so the only
# safe behaviour was to force serial execution — losing the whole point of waves. A project that can
# describe how to stand up (and tear down) a throwaway test environment for an arbitrary directory
# gets parallelism back: the executor provisions one env per worktree and prefixes every test
# command with that env's exec prefix.
#
# OPT-IN BY CONSTRUCTION: with no `.release-planning/EXEC-ENV.yml`, every function here is a no-op
# and execution behaves exactly as before this lib existed (host-local exec, serial-on-collision).
#
# Public API (all echo a verdict and ALWAYS return 0 — house style; callers parse the echo):
#   release_execenv_config <root>            → path to EXEC-ENV.yml if present, else empty
#   release_execenv_get <root> <key>         → raw (untemplated) value for key, else empty
#   release_execenv_active <root>            → `EXECENV=on` when a provision command is configured,
#                                              else `EXECENV=off`
#   release_execenv_label <raw>              → sanitized label: [a-z0-9_], ≤32 chars, never empty.
#                                              Safe for BOTH container names and Postgres db names.
#   release_execenv_render <tpl> <worktree> <label> [root]
#                                            → `{worktree}` / `{label}` / `{root}` substituted
#   release_execenv_max_parallel <root>      → concurrency cap (default 4 when active, 0 = unlimited)
#   execenv_provision <root> <worktree> <label>
#                                            → runs test_env_provision once for that worktree.
#                                              Echoes `EXECENV_PROVISION=<ok|skipped|failed>`; on
#                                              failure also `EXECENV_EVIDENCE=<file>` (stdout+stderr).
#   execenv_teardown <root> <worktree> <label>
#                                            → runs test_env_teardown. Echoes
#                                              `EXECENV_TEARDOWN=<ok|skipped|failed>`. Never fatal —
#                                              a teardown failure must not lose the commits.
#   execenv_prefix <root> <worktree> <label> → echoes the rendered test_exec_prefix (empty when
#                                              unset ⇒ caller runs tests host-locally, as before)
#
# Config format — .release-planning/EXEC-ENV.yml — an ORDERED flat map, one `key: value` per line,
# split on the FIRST colon only (values routinely contain colons: `-v {worktree}/backend:/app`):
#
#       test_env_provision:    docker run -d --name app-{label} -v {worktree}/backend:/app app:test
#                              && docker exec app-{label} createdb-from-template test_{label}
#       test_env_teardown:     docker rm -f app-{label} >/dev/null 2>&1 || true
#       test_exec_prefix:      docker exec app-{label}
#       test_env_max_parallel: 4
#
#   - Placeholders: `{worktree}` (absolute path of the worktree), `{label}` (unique, sanitized),
#     `{root}` (absolute path of the main repo checkout).
#   - `test_env_provision` MUST be synchronous (return only when the env can run tests) and
#     idempotent (re-running for the same label must not fail) — the executor may retry.
#   - Exit 0 = provisioned. Any non-zero exit ⇒ that worktree is unusable and the caller falls back
#     to serial execution in the phase worktree.
#   - `test_env_teardown` runs before the worktree is removed; make it tolerate a missing env.
#   - `test_exec_prefix` is prepended to EVERY pytest / manage.py / vitest command the task executor
#     runs. Leave it unset when the provisioned env is reachable from the host.
#   - '#' comments and blank lines are ignored.
#
# Env overrides:
#   RELEASE_EXECENV_TIMEOUT   seconds allowed for provision/teardown (default 600; 0 = no timeout)
#   RELEASE_EXECENV_DISABLE=1 force every function to no-op (debug / bisect an env-related failure)

# ── config resolution ────────────────────────────────────────────────────────────────────────────
release_execenv_config() {  # $1 root → path to EXEC-ENV.yml if present, else empty
  [ "${RELEASE_EXECENV_DISABLE:-0}" = 1 ] && return 0
  local f="${1:-.}/.release-planning/EXEC-ENV.yml"
  [ -f "$f" ] && printf '%s' "$f"
  return 0
}

release_execenv_get() {  # $1 root, $2 key → raw value (first match wins), else empty
  local cfg line val; cfg="$(release_execenv_config "${1:-.}")"
  [ -n "$cfg" ] || return 0
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"          # tolerate indented keys
    case "$line" in \#*|'') continue;; esac
    case "$line" in "$2":*) ;; *) continue;; esac
    val="${line#*:}"
    # trim leading/trailing whitespace without a subshell-per-call
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
    printf '%s' "$val"; return 0
  done < "$cfg"
  return 0
}

release_execenv_active() {  # $1 root → EXECENV=on|off  (on ⇔ a provision command is configured)
  local p; p="$(release_execenv_get "${1:-.}" test_env_provision)"
  [ -n "$p" ] && echo "EXECENV=on" || echo "EXECENV=off"
  return 0
}

# ── label + template rendering ───────────────────────────────────────────────────────────────────
release_execenv_label() {  # $1 raw → [a-z0-9_], ≤32 chars, never empty, never leading digit
  local s="${*:-env}"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_' | tr -s '_' \
       | sed -e 's/^_*//' -e 's/_*$//')"
  [ -n "$s" ] || s=env
  case "$s" in [0-9]*) s="e$s";; esac       # Postgres identifiers must not start with a digit
  printf '%s' "${s:0:32}"
  return 0
}

release_execenv_render() {  # $1 template, $2 worktree, $3 label, [$4 root] → substituted string
  local tpl="${1:-}" wt="${2:-}" label="${3:-}" root="${4:-}"
  # Pure bash substitution — never sed: worktree paths contain '/' and may contain sed metacharacters.
  tpl="${tpl//\{worktree\}/$wt}"
  tpl="${tpl//\{label\}/$label}"
  tpl="${tpl//\{root\}/$root}"
  printf '%s' "$tpl"
  return 0
}

release_execenv_max_parallel() {  # $1 root → cap (default 4 when active, 0 = unlimited)
  local v; v="$(release_execenv_get "${1:-.}" test_env_max_parallel)"
  case "$v" in
    ''|*[!0-9]*) [ "$(release_execenv_active "${1:-.}")" = "EXECENV=on" ] && echo 4 || echo 0 ;;
    *)           echo "$v" ;;
  esac
  return 0
}

# ── internal: run a provision/teardown command with a timeout, capturing output ──────────────────
_execenv_run() {  # $1 cmd, $2 cwd → sets _EXECENV_OUT / returns the command's rc
  local cmd="$1" cwd="$2" t="${RELEASE_EXECENV_TIMEOUT:-600}" runner=""
  if [ "$t" != 0 ]; then
    if   command -v timeout  >/dev/null 2>&1; then runner="timeout $t"
    elif command -v gtimeout >/dev/null 2>&1; then runner="gtimeout $t"
    fi
  fi
  _EXECENV_OUT="$( ( cd "$cwd" 2>/dev/null && eval "$runner $cmd" ) </dev/null 2>&1 )"
  return $?
}

# ── public: provision / teardown / prefix ────────────────────────────────────────────────────────
execenv_provision() {  # $1 root, $2 worktree, $3 label
  local root="${1:-.}" wt="${2:-}" label="${3:-}" tpl cmd rc ev
  tpl="$(release_execenv_get "$root" test_env_provision)"
  [ -n "$tpl" ] || { echo "EXECENV_PROVISION=skipped"; return 0; }
  [ -n "$wt" ] && [ -d "$wt" ] || { echo "EXECENV_PROVISION=failed"; return 0; }
  cmd="$(release_execenv_render "$tpl" "$wt" "$label" "$root")"
  _execenv_run "$cmd" "$wt"; rc=$?
  if [ "$rc" = 0 ]; then
    echo "EXECENV_PROVISION=ok"
  else
    ev="$(mktemp -t release-execenv-XXXXXX)"
    { printf '# EXEC-ENV PROVISION FAILED — label: %s\n# worktree: %s\n# command: %s\n# exit: %s\n\n' \
        "$label" "$wt" "$cmd" "$rc"
      printf '%s\n' "$_EXECENV_OUT"; } > "$ev"
    echo "EXECENV_PROVISION=failed"
    echo "EXECENV_EVIDENCE=$ev"
  fi
  return 0
}

execenv_teardown() {  # $1 root, $2 worktree, $3 label  — best effort, never fatal
  local root="${1:-.}" wt="${2:-}" label="${3:-}" tpl cmd rc
  tpl="$(release_execenv_get "$root" test_env_teardown)"
  [ -n "$tpl" ] || { echo "EXECENV_TEARDOWN=skipped"; return 0; }
  cmd="$(release_execenv_render "$tpl" "$wt" "$label" "$root")"
  # cwd falls back to root: teardown must still run when the worktree is already gone.
  [ -n "$wt" ] && [ -d "$wt" ] || wt="$root"
  _execenv_run "$cmd" "$wt"; rc=$?
  [ "$rc" = 0 ] && echo "EXECENV_TEARDOWN=ok" || echo "EXECENV_TEARDOWN=failed"
  return 0
}

execenv_prefix() {  # $1 root, $2 worktree, $3 label → rendered exec prefix (may be empty)
  local tpl; tpl="$(release_execenv_get "${1:-.}" test_exec_prefix)"
  [ -n "$tpl" ] || return 0
  release_execenv_render "$tpl" "${2:-}" "${3:-}" "${1:-.}"
  return 0
}
