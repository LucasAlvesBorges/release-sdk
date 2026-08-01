#!/usr/bin/env bash
# release-gate-lib.sh — the objective verification GATE for /release:* loop engineering.
#
# SINGLE SOURCE OF TRUTH for "is the work green?". Sourced by:
#   - skills/loop/SKILL.md      (the closed maker→gate→checker→land loop — the STOP condition)
#   - skills/execute/SKILL.md   (gate before phase auto-land)
#   - skills/quick/SKILL.md     (gate before quick auto-land)
#   - agents/code-fixer.md      (full-sweep verification after a fix)
#   - bin/test-gate-lib.sh      (the contract test SOURCES this file — no faithful-slice drift)
#
# The gate is the *verifiable goal* leg of a loop: a single, objective, tool-checked stop
# condition (lint / typecheck / migrations / tests / build). The agent does NOT decide "green" —
# this lib runs the real commands and decides. On RED it captures the FIRST failing command's
# output as EVIDENCE the next loop iteration feeds back into the maker's context. That is the
# whole point: stop being the element inside the loop; let a tool close it.
#
# Public API:
#   run_gate [root] [phase]
#       Runs the project's verify-gate commands IN ORDER against <root> (default: repo top-level).
#       Resolves commands from <root>/.release-planning/VERIFY-GATE.yml, else a stack default.
#       Echoes one `GATE_STEP=<name> <PASS|FAIL>` line per step run, and on the FIRST failure a
#       `GATE_EVIDENCE=<file>` line (captured stdout+stderr), then exactly one terminal
#       `GATE=<GREEN|RED>` (or empty `GATE=` when nothing could be resolved). ALWAYS returns 0 —
#       the verdict lives in the echo, exactly like land_branch in release-merge-lib.sh, so
#       `set -euo pipefail` callers never abort on a RED (RED is a normal outcome, not a script bug).
#       Fail-fast by default (stops at the first red step — cheapest-first ordering); set
#       GATE_FAILFAST=0 to run every step and report all failures.
#
# Config format — .release-planning/VERIFY-GATE.yml — an ORDERED flat map, one step per line:
#       lint:    ruff check backend/
#       migrate: python backend/manage.py makemigrations --check --dry-run
#       test:    pytest backend/apps -q
#   Lines run top-to-bottom (order = priority; put the cheapest/fastest first). Blank lines and
#   '#' comments are ignored. Split is on the FIRST colon only, so a command may itself contain
#   colons (e.g. `unit: pytest -k "parse:edge"` is fine). No config + unknown stack ⇒ empty verdict.

# ── helpers ─────────────────────────────────────────────────────────────────────────────────────
release_gate_root() {  # resolve a sane repo root from an optional arg, else cwd's top-level
  local r="${1:-}"
  [ -n "$r" ] && { printf '%s' "$r"; return; }
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

release_detect_stack() {  # $1 root → django | react | fullstack | unknown
  local root="$1" dj="" rc=""
  { [ -f "$root/manage.py" ] || [ -f "$root/backend/manage.py" ]; } && dj=1
  if   [ -f "$root/package.json" ]          && grep -q '"react"' "$root/package.json" 2>/dev/null; then rc=1
  elif [ -f "$root/frontend/package.json" ] && grep -q '"react"' "$root/frontend/package.json" 2>/dev/null; then rc=1
  fi
  if   [ -n "$dj" ] && [ -n "$rc" ]; then echo fullstack
  elif [ -n "$dj" ];                 then echo django
  elif [ -n "$rc" ];                 then echo react
  else                                    echo unknown
  fi
}

release_default_gate() {  # $1 stack, $2 root → echoes `name: command` lines (the fallback gate)
  local stack="$1" root="$2" mp="manage.py" pyroot="." feroot="."
  [ -f "$root/backend/manage.py" ]   && { mp="backend/manage.py"; pyroot="backend"; }
  [ -f "$root/frontend/package.json" ] && feroot="frontend"
  case "$stack" in
    django)
      printf 'lint: ruff check %s\n'                              "$pyroot"
      printf 'migrate: python %s makemigrations --check --dry-run\n' "$mp"
      printf 'test: pytest %s -q\n'                               "$pyroot"
      ;;
    react)
      # No default `test:` — vitest/jest watch-mode would hang the gate. `build` runs tsc, so type
      # errors are still caught. Add an explicit `test:` line in VERIFY-GATE.yml for your runner.
      printf 'lint: npm --prefix %s run lint\n'  "$feroot"
      printf 'build: npm --prefix %s run build\n' "$feroot"
      ;;
    fullstack)
      release_default_gate django "$root"
      release_default_gate react  "$root"
      ;;
    *) : ;;  # unknown → nothing; caller decides
  esac
}

release_gate_config() {  # $1 root → path to VERIFY-GATE.yml if present, else empty
  local f="$1/.release-planning/VERIFY-GATE.yml"
  [ -f "$f" ] && printf '%s' "$f"
}

release_resolve_gate() {  # $1 root → the resolved `name: command` lines (config if present, else default)
  local root="$1" cfg; cfg="$(release_gate_config "$root")"
  if [ -n "$cfg" ]; then
    grep -vE '^[[:space:]]*(#|$)' "$cfg"   # drop comments + blank lines, preserve order
  else
    release_default_gate "$(release_detect_stack "$root")" "$root"
  fi
}

# ── public: run the gate ─────────────────────────────────────────────────────────────────────────
run_gate() {  # [root] [phase]
  local root failfast="${GATE_FAILFAST:-1}" steps line name cmd out rc verdict="" any=0 red=0 ev=""
  root="$(release_gate_root "${1:-}")"
  steps="$(release_resolve_gate "$root")"
  [ -n "$steps" ] || { echo "GATE="; return 0; }   # nothing resolved → caller decides

  while IFS= read -r line; do
    case "$line" in *:*) ;; *) continue;; esac      # skip any line without a `name:` colon
    name="${line%%:*}"; cmd="${line#*:}"
    name="$(printf '%s' "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    cmd="$(printf '%s'  "$cmd"  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$cmd" ] || continue
    any=1
    out="$( ( cd "$root" && eval "$cmd" ) </dev/null 2>&1 )"; rc=$?   # </dev/null: never block on a prompt
    if [ "$rc" = 0 ]; then
      echo "GATE_STEP=$name PASS"
    else
      echo "GATE_STEP=$name FAIL"; red=1
      if [ -z "$ev" ]; then                          # capture only the FIRST failure as feedback evidence
        ev="$(mktemp -t release-gate-XXXXXX)"
        { printf '# GATE RED — step: %s\n# command: %s\n# exit: %s\n\n' "$name" "$cmd" "$rc"
          printf '%s\n' "$out"; } > "$ev"
        echo "GATE_EVIDENCE=$ev"
      fi
      [ "$failfast" = 1 ] && break
    fi
  done <<EOF
$steps
EOF

  [ "$any" = 1 ] || { echo "GATE="; return 0; }
  [ "$red" = 1 ] && verdict=RED || verdict=GREEN
  echo "GATE=$verdict"
  return 0
}
