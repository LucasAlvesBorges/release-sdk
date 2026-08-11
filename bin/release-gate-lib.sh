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
#       Echoes one `GATE_STEP=<name> <PASS|PASS_BASELINE|FAIL>` line per step run, and on the FIRST failure a
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
#
#   Baseline lookups are keyed by the STEP NAME: the `test:` step reads `suites.test` from
#   .release-planning/test-baselines.json. Keep the two in sync — a mismatch makes the baseline
#   silently inert (the gate simply stays RED with nothing to explain it).
#
#   PASS_BASELINE (v0.23.0) = the step exited non-zero but EVERY failing test is recorded in
#   .release-planning/test-baselines.json (see release-baseline-lib.sh). It does not turn the gate
#   RED — inherited failures are not this phase's regressions — but it is echoed so the run is
#   auditable. No baseline file, unparseable output, or one unknown failure ⇒ plain FAIL.

# Resolved AT SOURCE TIME, and deliberately not with `${BASH_SOURCE[0]}` alone: under zsh — which is
# what the agent harness actually sources these libs from on macOS — BASH_SOURCE does not exist, so
# the sibling-lib lookup silently failed and every inherited-red repo went RED instead of
# PASS_BASELINE. In zsh `$0` is the sourced file at top level (it is the FUNCTION name inside a
# function, which is why this must be captured here and not lazily).
_RELEASE_GATE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

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

# ── baseline bridge (v0.23.0) ────────────────────────────────────────────────────────────────────
# A failing step whose failures are ALL recorded in .release-planning/test-baselines.json is not
# THIS run's problem. Without this, a repo with long-standing reds can never reach GATE=GREEN and
# every loop iteration re-triages the same inherited failures. Fail-safe by construction: no
# baseline file, an unparseable output, or a single unrecognized failure ⇒ the step stays RED.
_gate_all_failures_are_baseline() {  # $1 root, $2 step name, $3 output → 0 when fully baseline
  local root="$1" name="$2" out="$3" lib verdict stack=django
  command -v awk >/dev/null 2>&1 || return 1
  if ! command -v baseline_classify >/dev/null 2>&1; then
    lib="${RELEASE_LIB_DIR:-$_RELEASE_GATE_LIB_DIR}/release-baseline-lib.sh"
    [ -f "$lib" ] || return 1
    # shellcheck source=release-baseline-lib.sh
    . "$lib"
  fi
  [ -n "$(baseline_file "$root")" ] || return 1          # no baseline ⇒ never soften a RED
  # Detect the runner from the OUTPUT, never from the step name: a step called `tests` matches any
  # naive `*ts*` rule and would be parsed as vitest, yielding zero signatures, a `clean` verdict and
  # a RED that should have been PASS_BASELINE.
  case "$out" in
    *"short test summary"*|*"FAILED "*|*"ERROR "*) stack=django ;;
    *"Test Files"*|*"×"*|*"FAIL src/"*|*"FAIL  "*)  stack=react  ;;
    *) return 1 ;;                                       # unrecognized output ⇒ do not soften
  esac
  verdict="$(printf '%s\n' "$out" | baseline_parse_failures "$stack" \
             | baseline_classify "$root" "$name" | sed -n 's/^BASELINE_VERDICT=//p')"
  [ "$verdict" = "baseline-only" ]
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
    elif _gate_all_failures_are_baseline "$root" "$name" "$out"; then
      # Every failing test in this step is a KNOWN pre-existing failure (release-baseline-lib.sh).
      # A repo that inherits 44 reds would otherwise be RED forever and the loop would burn its
      # iterations "fixing" code this phase never touched. Reported, never silently swallowed.
      echo "GATE_STEP=$name PASS_BASELINE"
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
