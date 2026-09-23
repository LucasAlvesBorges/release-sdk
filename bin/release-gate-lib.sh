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
#       Echoes `GATE_STEP_START=<name> TEST_TIMEOUT=<seconds>` before each uncached step, then one
#       `GATE_STEP=<name> <PASS|PASS_CACHED|PASS_BASELINE|FAIL|TIMEOUT>` verdict. On the FIRST failure a
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
if ! command -v run_test_bounded >/dev/null 2>&1; then
  _RELEASE_GATE_EXECENV_LIB="${RELEASE_LIB_DIR:-$_RELEASE_GATE_LIB_DIR}/release-execenv-lib.sh"
  [ -f "$_RELEASE_GATE_EXECENV_LIB" ] && . "$_RELEASE_GATE_EXECENV_LIB"
fi

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

release_default_quick_gate() { # $1 stack, $2 root → cheap checks + the diff-implied focused tests
  # The maker's own focused run is a claim, not evidence: the quick gate re-runs `{focused}` (the
  # test targets implied by the diff; SKIPPED when the diff touches no test-bearing surface) so a
  # quick never lands on lint alone. The broad suite still stays out of the quick profile.
  local stack="$1" root="$2" mp="manage.py" pyroot="." feroot="."
  [ -f "$root/backend/manage.py" ] && { mp="backend/manage.py"; pyroot="backend"; }
  [ -f "$root/frontend/package.json" ] && feroot="frontend"
  case "$stack" in
    django)
      printf 'lint: ruff check %s\n' "$pyroot"
      printf 'migrate: python %s makemigrations --check --dry-run\n' "$mp"
      printf 'test-focused: pytest {focused} -q --reuse-db\n'
      ;;
    react)
      printf 'lint: npm --prefix %s run lint\n' "$feroot"
      if grep -q '"typecheck"' "$root/$feroot/package.json" 2>/dev/null; then
        printf 'typecheck: npm --prefix %s run typecheck\n' "$feroot"
      fi
      if grep -q '"vitest"' "$root/$feroot/package.json" 2>/dev/null; then
        printf 'test-focused: npm --prefix %s exec -- vitest run {focused}\n' "$feroot"
      elif grep -q '"jest"' "$root/$feroot/package.json" 2>/dev/null; then
        printf 'test-focused: npm --prefix %s exec -- jest --runInBand --watchAll=false {focused}\n' "$feroot"
      fi
      ;;
    fullstack)
      release_default_quick_gate django "$root"
      release_default_quick_gate react "$root"
      ;;
    *) : ;;
  esac
}

release_gate_config() {  # $1 root → path to VERIFY-GATE.yml if present, else empty
  local root="$1" f="$1/.release-planning/VERIFY-GATE.yml"
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

release_resolve_quick_gate() { # $1 root
  local root="$1" cfg="$1/.release-planning/VERIFY-QUICK.yml"
  if [ -f "$cfg" ]; then
    grep -vE '^[[:space:]]*(#|$)' "$cfg"
  else
    release_default_quick_gate "$(release_detect_stack "$root")" "$root"
  fi
}

_release_gate_hash() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  else sha256sum | awk '{print $1}'
  fi
}

release_gate_fingerprint() { # <root> <full|quick>; empty when the tree is dirty
  local root="$1" mode="${2:-full}" tree steps env_material="" env_cfg="" focused_material=""
  git -C "$root" diff --quiet 2>/dev/null || return 0
  git -C "$root" diff --cached --quiet 2>/dev/null || return 0
  [ -z "$(git -C "$root" ls-files --others --exclude-standard 2>/dev/null | grep -v '^\.release-planning/' | head -1)" ] || return 0
  tree="$(git -C "$root" rev-parse 'HEAD^{tree}' 2>/dev/null)" || return 0
  if [ "$mode" = quick ]; then steps="$(release_resolve_quick_gate "$root")"
  else steps="$(release_resolve_gate "$root")"
  fi
  # A `{focused}` command is rendered only while running steps, so its literal command text alone
  # cannot distinguish two base refs that imply different test coverage for the same HEAD.
  focused_material="$(release_gate_base_ref "$root")|$(release_focused_test_targets "$root")"
  if command -v release_execenv_config >/dev/null 2>&1; then
    env_cfg="$(release_execenv_config "$root")"
    [ -n "$env_cfg" ] && env_material="$(command cat "$env_cfg" 2>/dev/null)"
  fi
  printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$mode" "$tree" "${RELEASE_EXEC_PREFIX:-}" \
    "$steps" "$focused_material" "$env_material" | _release_gate_hash
}

_release_gate_step_fingerprint() { # <root> <name> <cmd>; empty for dirty/disabled runs
  local root="$1" name="$2" cmd="$3" tree env_material="" env_cfg=""
  [ "${RELEASE_GATE_CACHE:-1}" != 0 ] && [ "${RELEASE_GATE_STEP_CACHE:-1}" != 0 ] || return 0
  git -C "$root" diff --quiet 2>/dev/null || return 0
  git -C "$root" diff --cached --quiet 2>/dev/null || return 0
  [ -z "$(git -C "$root" ls-files --others --exclude-standard 2>/dev/null | grep -v '^\.release-planning/' | head -1)" ] || return 0
  tree="$(git -C "$root" rev-parse 'HEAD^{tree}' 2>/dev/null)" || return 0
  if command -v release_execenv_config >/dev/null 2>&1; then
    env_cfg="$(release_execenv_config "$root")"
    [ -n "$env_cfg" ] && env_material="$(command cat "$env_cfg" 2>/dev/null)"
  fi
  printf '%s\n%s\n%s\n%s\n%s\n' "$tree" "$name" "$cmd" "${RELEASE_EXEC_PREFIX:-}" \
    "$env_material" | _release_gate_hash
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
# ── impact-scoped test targets ────────────────────────────────────────────────────────────────────
# A 12k-test suite (hubus: ~50 min) never runs per loop iteration, so the gate degraded into a hand
# whitelist that silently missed every new test module. `{focused}` in a VERIFY-GATE command is
# replaced by the test targets IMPLIED BY THE DIFF against the base ref; a step with no targets is
# SKIPPED (not RED), and the broad suite stays a separate, land-time step.
release_gate_base_ref() {  # <root> → the ref the phase diff is measured against
  local root="${1:-.}" ref="${RELEASE_GATE_BASE:-}" cand
  [ -n "$ref" ] && { printf '%s' "$ref"; return 0; }
  [ -f "$root/.release-planning/.gate-base" ] && ref="$(head -1 "$root/.release-planning/.gate-base" 2>/dev/null)"
  [ -n "$ref" ] && { printf '%s' "$ref"; return 0; }
  for cand in main master dev develop; do
    git -C "$root" rev-parse --verify -q "$cand" >/dev/null 2>&1 && { printf '%s' "$cand"; return 0; }
  done
  return 0
}

release_focused_test_targets() {  # <root> [base_ref] [backend|frontend] → matching test paths implied by the diff
  local root="${1:-.}" base="${2:-}" surface="${3:-all}" head_ref f app tests dir stem sib source_root module_found out=""
  [ -n "$base" ] || base="$(release_gate_base_ref "$root")"
  [ -n "$base" ] || return 0
  head_ref="$(git -C "$root" merge-base "$base" HEAD 2>/dev/null)" || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      # Django: changed tests are exact targets. Domain modules use a same-name test when one
      # exists; models, serializers, views, tasks, signals, migrations and conftest remain
      # conservative because their behavior routinely spans the whole app.
      backend/apps/*/tests/test_*.py|apps/*/tests/test_*.py)
        if [ -f "$root/$f" ]; then
          out="$out $f"
        else
          app="${f#backend/}"; app="${app#apps/}"; app="${app%%/*}"
          for dir in "backend/apps/$app" "apps/$app"; do
            [ -d "$root/$dir/tests" ] && { out="$out $dir/tests"; break; }
            [ -f "$root/$dir/tests.py" ] && { out="$out $dir/tests.py"; break; }
            [ -d "$root/$dir" ] && { out="$out $dir"; break; }
          done
          [ -d "$root/backend" ] && [ ! -d "$root/backend/apps/$app" ] && out="$out backend"
        fi
        ;;
      backend/apps/*/migrations/*|apps/*/migrations/*)
        app="${f#backend/}"; app="${app#apps/}"; app="${app%%/*}"
        for dir in "backend/apps/$app" "apps/$app"; do
          [ -d "$root/$dir/tests" ] && { out="$out $dir/tests"; break; }
          [ -f "$root/$dir/tests.py" ] && { out="$out $dir/tests.py"; break; }
          [ -d "$root/$dir" ] && { out="$out $dir"; break; }
        done
        ;;
      backend/apps/*/*|apps/*/*)
        app="${f#backend/}"; app="${app#apps/}"; app="${app%%/*}"
        for dir in "backend/apps/$app" "apps/$app"; do
          [ -d "$root/$dir" ] || continue
          if [ -d "$root/$dir/tests" ]; then tests="$dir/tests"
          elif [ -f "$root/$dir/tests.py" ]; then tests="$dir/tests.py"
          else tests="$dir"; fi
          stem="${f##*/}"; stem="${stem%.py}"
          case "$stem" in
            models|serializers|views|tasks|signals|conftest|admin|apps|urls|migrations|__init__) stem="";;
          esac
          module_found=""
          if [ -n "$stem" ] && [ -d "$root/$dir/tests" ]; then
            while IFS= read -r sib; do
              [ -n "$sib" ] || continue
              out="$out ${sib#"$root"/}"
              module_found=1
            done <<EOF3
$(find "$root/$dir/tests" -maxdepth 1 -type f -name "test_$stem*.py" -print 2>/dev/null)
EOF3
          fi
          [ -n "$tests" ] && { [ -n "$stem" ] || out="$out $tests"; }
          # An unmapped module still needs coverage; run the app rather than guessing a test.
          [ -n "$tests" ] && [ -n "$stem" ] && [ -z "$module_found" ] && out="$out $tests"
          break
        done
        ;;
      # Shared Django infrastructure can affect every app. A backend root is safer than silently
      # skipping coverage and remains compatible with project wrappers that own the runner.
      backend/*.py|backend/*/*.py)
        [ -d "$root/backend" ] && out="$out backend"
        ;;
      # Dependency and runner configuration can change collection or every module's behavior.
      # Keep the fallback inside the matching stack instead of letting a quick become lint-only.
      package.json|package-lock.json|yarn.lock|pnpm-lock.yaml|vite.config.*|jest.config.*|tsconfig*.json|frontend/package.json|frontend/package-lock.json|frontend/yarn.lock|frontend/pnpm-lock.yaml|frontend/vite.config.*|frontend/jest.config.*|frontend/tsconfig*.json)
        if [ -d "$root/frontend/src" ]; then out="$out frontend/src"
        elif [ -d "$root/src" ]; then out="$out src"; fi
        ;;
      pyproject.toml|backend/requirements*.txt|backend/pyproject.toml|backend/manage.py)
        [ -d "$root/backend" ] && out="$out backend"
        ;;
      # React/RN: a changed test file is a target; a changed module pulls its sibling test(s).
      src/*.test.[jt]s|src/*.test.[jt]sx|src/*.spec.[jt]s|src/*.spec.[jt]sx|src/*/__tests__/*|frontend/src/*.test.[jt]s|frontend/src/*.test.[jt]sx|frontend/src/*.spec.[jt]s|frontend/src/*.spec.[jt]sx|frontend/src/*/__tests__/*)
        [ -f "$root/$f" ] && out="$out $f" ;;
      src/*.[jt]s|src/*.[jt]sx)
        source_root="src"; dir="${f%/*}"; stem="${f##*/}"; stem="${stem%.*}"
        module_found=""
        for sib in "$dir/$stem".test.ts "$dir/$stem".test.tsx "$dir/$stem".test.js "$dir/$stem".test.jsx \
                   "$dir/$stem".spec.ts "$dir/$stem".spec.tsx "$dir/__tests__/$stem".test.ts "$dir/__tests__/$stem".test.tsx; do
          [ -f "$root/$sib" ] && { out="$out $sib"; module_found=1; }
        done
        [ -n "$module_found" ] || out="$out $source_root"
        ;;
      frontend/src/*.[jt]s|frontend/src/*.[jt]sx)
        source_root="frontend/src"; dir="${f%/*}"; stem="${f##*/}"; stem="${stem%.*}"
        module_found=""
        dir="${f%/*}"; stem="${f##*/}"; stem="${stem%.*}"
        for sib in "$dir/$stem".test.ts "$dir/$stem".test.tsx "$dir/$stem".test.js "$dir/$stem".test.jsx \
                   "$dir/$stem".spec.ts "$dir/$stem".spec.tsx "$dir/__tests__/$stem".test.ts "$dir/__tests__/$stem".test.tsx; do
          [ -f "$root/$sib" ] && { out="$out $sib"; module_found=1; }
        done
        [ -n "$module_found" ] || out="$out $source_root"
        ;;
    esac
  done <<EOF2
$(git -C "$root" diff --name-only "$head_ref" HEAD 2>/dev/null)
EOF2
  case "$surface" in
    backend) out="$(printf '%s\n' "$out" | tr ' ' '\n' | grep -E '^(backend($|/)|apps/)' || true)" ;;
    frontend) out="$(printf '%s\n' "$out" | tr ' ' '\n' | grep -E '^(src($|/)|frontend/src($|/))' || true)" ;;
  esac
  # A broad fallback subsumes its descendants. Removing them avoids duplicate collection while a
  # test-only diff, which has no selected ancestor, remains an exact target.
  printf '%s\n' "$out" | tr ' ' '\n' | sed '/^$/d' | sort -u |
    awk '{ path=$0; keep=1; while (path ~ /\//) { sub(/\/[^\/]+$/, "", path); if (seen[path]) { keep=0; break } } if (keep) { print; seen[$0]=1 } }' |
    tr '\n' ' ' | sed 's/ $//'
  return 0
}

release_focused_surface_for_command() { # <command> → backend | frontend | all
  local cmd="$1"
  case "$cmd" in
    *"{focused:backend}"*|*pytest*|*"run_test_lane.py"*) printf backend ;;
    *"{focused:frontend}"*|*vitest*|*jest*)              printf frontend ;;
    *)                                                     printf all ;;
  esac
}

_release_run_gate_steps() { # <root> <steps>
  local root="$1" steps="$2" failfast="${GATE_FAILFAST:-1}" line name cmd out rc verdict="" any=0 red=0 ev="" targets
  local meta outf hung bounded elapsed timeout step_fp step_cache cache_dir surface
  [ -n "$steps" ] || { echo "GATE="; return 0; }   # nothing resolved → caller decides
  cache_dir="$root/.release-planning/.gate-cache/steps"

  while IFS= read -r line; do
    case "$line" in *:*) ;; *) continue;; esac      # skip any line without a `name:` colon
    name="${line%%:*}"; cmd="${line#*:}"
    name="$(printf '%s' "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    cmd="$(printf '%s'  "$cmd"  | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$cmd" ] || continue
    case "$cmd" in *"{focused}"*|*"{focused:backend}"*|*"{focused:frontend}"*)
      surface="$(release_focused_surface_for_command "$cmd")"
      targets="$(release_focused_test_targets "$root" "" "$surface")"
      if [ -z "$targets" ]; then
        echo "GATE_STEP=$name SKIPPED_NO_TARGETS"   # diff touches no test-bearing app/module
        any=1; continue
      fi
      cmd="${cmd//\{focused:backend\}/$targets}"
      cmd="${cmd//\{focused:frontend\}/$targets}"
      cmd="${cmd//\{focused\}/$targets}"
      ;;
    esac
    [ -z "${RELEASE_EXEC_PREFIX:-}" ] || cmd="$RELEASE_EXEC_PREFIX $cmd"
    any=1
    step_fp="$(_release_gate_step_fingerprint "$root" "$name" "$cmd")"
    step_cache="$cache_dir/${step_fp}.pass"
    if [ -n "$step_fp" ] && [ -f "$step_cache" ]; then
      echo "GATE_STEP=$name PASS_CACHED"
      continue
    fi

    timeout=0
    command -v release_test_timeout >/dev/null 2>&1 && timeout="$(release_test_timeout "$root")"
    echo "GATE_STEP_START=$name TEST_TIMEOUT=$timeout"
    if command -v run_test_bounded >/dev/null 2>&1; then
      meta="$(run_test_bounded "$root" "$cmd" "$root")"
      outf="$(printf '%s\n' "$meta" | sed -n 's/^TEST_OUTPUT=//p')"
      rc="$(printf '%s\n' "$meta" | sed -n 's/^TEST_RC=//p')"
      hung="$(printf '%s\n' "$meta" | sed -n 's/^TEST_HUNG=//p')"
      bounded="$(printf '%s\n' "$meta" | sed -n 's/^TEST_BOUNDED=//p')"
      elapsed="$(printf '%s\n' "$meta" | sed -n 's/^TEST_ELAPSED=//p')"
      [ -n "$rc" ] || rc=1
      [ -n "$outf" ] && [ -f "$outf" ] && out="$(command cat "$outf")" || out=""
      [ -n "$outf" ] && rm -f "$outf"
    else
      out="$( ( cd "$root" && eval "$cmd" ) </dev/null 2>&1 )"; rc=$?
      hung=false; bounded=false; elapsed=""
    fi

    if [ "$hung" = true ]; then
      echo "GATE_STEP=$name TIMEOUT"; red=1
      echo "GATE_TIMEOUT=$timeout GATE_BOUNDED=$bounded GATE_ELAPSED=${elapsed:-unknown}"
      if [ -z "$ev" ]; then
        ev="$(mktemp -t release-gate-XXXXXX)"
        { printf '# GATE TIMEOUT — step: %s\n# command: %s\n# timeout: %s\n# exit: %s\n\n' \
            "$name" "$cmd" "$timeout" "$rc"
          printf '%s\n' "$out"; } > "$ev"
        echo "GATE_EVIDENCE=$ev"
      fi
      [ "$failfast" = 1 ] && break
    elif [ "$rc" = 0 ]; then
      echo "GATE_STEP=$name PASS"
      if [ -n "$step_fp" ]; then
        mkdir -p "$cache_dir"
        printf 'step=%s\ncommand=%s\n' "$name" "$cmd" > "$step_cache"
      fi
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

# ── gate audit ───────────────────────────────────────────────────────────────────────────────────
# A gate is trusted at land time, so it must be able to catch what it is trusted to catch. hubus
# drifted into a hand whitelist of RLS files (no broad suite, no {focused}, per-phase copies) and
# shipped phases whose only test evidence was the maker's own run. Warnings never change the
# verdict; execute/quick print them so the drift is visible on every land.
release_gate_audit() {  # [root] → zero or more `GATE_WARN=<code> <detail>` lines
  local root steps quick_steps line name cmd broad=0 focused=0
  root="$(release_gate_root "${1:-}")"
  steps="$(release_resolve_gate "$root")"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name="${line%%:*}"; cmd="${line#*:}"
    case "$cmd" in *"{focused}"*) focused=1; continue;; esac
    case "$cmd" in
      *pytest*|*vitest*|*jest*|*"run test"*)
        case "$cmd" in *test_*.py*|*.test.*|*"::"*) ;; *) broad=1;; esac
        case "$cmd" in *--create-db*)
          echo "GATE_WARN=create-db step=$name (recreates the test DB on every run; use --reuse-db)";;
        esac
        ;;
    esac
  done <<EOF2
$steps
EOF2
  if [ "$focused" = 0 ]; then
    quick_steps="$(release_resolve_quick_gate "$root")"
    case "$quick_steps" in *"{focused}"*|*"{focused:backend}"*|*"{focused:frontend}"*) focused=1;; esac
  fi
  [ "$broad" = 1 ] || echo "GATE_WARN=no-broad-step (no pytest/vitest step runs the full suite: land trusts a hand whitelist; add a broad step and keep {focused} for loops)"
  [ "$focused" = 1 ] || echo "GATE_WARN=no-focused-step (no {focused} step: every iteration pays the whitelist instead of the diff-implied tests)"
  # A per-phase gate copy in a phase still in flight (no SUMMARY yet) means the project gate was
  # swapped for this phase; archived copies of finished phases are history, not drift.
  # `find`, not shell globs: this lib is sourced by zsh (nomatch aborts the command) and bash alike.
  # Copies older than a week or in a phase that already has SUMMARY/VERIFICATION are history.
  find "$root/.release-planning/phases" -mindepth 2 -maxdepth 2 -name '*VERIFY-GATE*' -mtime -7 2>/dev/null |
    while IFS= read -r copy; do
      [ -n "$copy" ] || continue
      if find "${copy%/*}" -maxdepth 1 \( -name '*SUMMARY.md' -o -name '*VERIFICATION.md' \) 2>/dev/null | grep -q .; then
        continue
      fi
      echo "GATE_WARN=phase-local-gate (${copy#"$root"/}: the project gate is never swapped per phase; land runs the root VERIFY-GATE.yml)"
      break
    done
  return 0
}

run_gate() {  # [root] [phase]
  local root steps
  root="$(release_gate_root "${1:-}")"
  steps="$(release_resolve_gate "$root")"
  release_gate_audit "$root"
  _release_run_gate_steps "$root" "$steps"
}

run_quick_gate() { # [root] — no broad suite; maker already ran focused tests
  local root steps
  root="$(release_gate_root "${1:-}")"
  steps="$(release_resolve_quick_gate "$root")"
  _release_run_gate_steps "$root" "$steps"
}

run_gate_cached() { # [root] [full|quick] — reuses GREEN evidence for an unchanged committed tree
  local root mode fingerprint cache_dir cache_file out tmp
  root="$(release_gate_root "${1:-}")"; mode="${2:-full}"
  if [ "${RELEASE_GATE_CACHE:-1}" = 0 ]; then
    [ "$mode" = quick ] && run_quick_gate "$root" || run_gate "$root"
    return 0
  fi
  fingerprint="$(release_gate_fingerprint "$root" "$mode")"
  cache_dir="$root/.release-planning/.gate-cache"
  cache_file="$cache_dir/${fingerprint}.out"
  if [ -n "$fingerprint" ] && [ -f "$cache_file" ]; then
    echo "GATE_CACHE=hit"
    command cat "$cache_file"
    return 0
  fi
  tmp="$(mktemp -t release-gate-run-XXXXXX)"
  if [ "$mode" = quick ]; then run_quick_gate "$root" | command tee "$tmp"
  else run_gate "$root" | command tee "$tmp"
  fi
  out="$(command cat "$tmp")"; rm -f "$tmp"
  case "$out" in
    *GATE=GREEN*)
      if [ -n "$fingerprint" ]; then
        mkdir -p "$cache_dir"
        printf '%s\n' "$out" > "$cache_file"
      fi
      ;;
  esac
}
