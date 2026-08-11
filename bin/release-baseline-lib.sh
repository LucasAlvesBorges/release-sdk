#!/usr/bin/env bash
# release-baseline-lib.sh — known pre-existing test failures, so a run can tell NEW breakage from
# the mess it inherited.
#
# SINGLE SOURCE OF TRUTH for "is this failure mine?". Sourced by:
#   - bin/release-gate-lib.sh        (run_gate: a step whose failures are ALL baseline is not RED)
#   - agents/test-runner.md          (classify each failure BASELINE vs NEW in its bucket JSON)
#   - agents/phase-verifier.md       (never report inherited failures as phase gaps)
#   - skills/baseline/SKILL.md       (`/release:baseline capture|show|clear`)
#   - bin/test-baseline-lib.sh       (the contract test SOURCES this file — no drift)
#
# WHY THIS EXISTS
# A repo with 44 long-standing failures makes every gate RED forever. Without a baseline the loop
# re-discovers and re-triages the same inherited failures on every single verification, the agent
# burns iterations "fixing" code it never touched, and a genuinely new regression hides in the
# noise. The baseline turns "is the suite green?" (unanswerable) into "did WE break anything?"
# (answerable, and the only question a phase gate should ask).
#
# THE FILE — .release-planning/test-baselines.json (committed or not, project's choice):
#   {
#     "captured_at": "2026-08-11T10:00:00Z",
#     "captured_on": "main@a1b2c3d",
#     "suites": {
#       "backend": {
#         "cmd": "pytest backend/apps -q",
#         "failures": [
#           {"id": "backend/apps/financeiro/tests/test_x.py::test_y", "error": "AssertionError"},
#           {"id": "backend/apps/frota/tests/test_z.py::TestA::test_b", "error": "IntegrityError"}
#         ]
#       }
#     }
#   }
# A SIGNATURE is `<test id>|<error type>` — the id alone would mask a test that now fails for a
# DIFFERENT reason (a new bug hiding behind an old red), and the error alone is far too coarse.
#
# Public API (all echo and ALWAYS return 0 — house style):
#   baseline_file <root>                        → path if present, else empty
#   baseline_signature <id> [error]             → the canonical `id|error` signature
#   baseline_parse_failures <stack> < output    → `id|error` per line, parsed from pytest/vitest output
#   baseline_has <root> <signature> [suite]     → `BASELINE_HIT=yes|no`
#   baseline_classify <root> [suite] < sigs     → per line `NEW=<sig>` / `BASELINE=<sig>`, then a
#                                                 terminal `BASELINE_VERDICT=<clean|baseline-only|new>`
#                                                 plus `NEW_COUNT=<n> BASELINE_COUNT=<n>`.
#                                                 No baseline file ⇒ every failure is NEW (fail-safe:
#                                                 an absent baseline must never hide a regression).
#   baseline_count <root> [suite]               → number of recorded signatures
#
# Env overrides:
#   RELEASE_BASELINE_DISABLE=1   ignore the file entirely (every failure NEW — use to audit the baseline)

release_baseline_path() { printf '%s/%s/test-baselines.json' "${1:-.}" "${RELEASE_PLANNING_DIR:-.release-planning}"; }

baseline_file() {  # $1 root → path if present and enabled, else empty
  [ "${RELEASE_BASELINE_DISABLE:-0}" = 1 ] && return 0
  local f; f="$(release_baseline_path "${1:-.}")"
  [ -f "$f" ] && printf '%s' "$f"
  return 0
}

baseline_signature() {  # $1 test id, [$2 error type] → `id|error`
  local id="${1:-}" err="${2:-}"
  id="$(printf '%s' "$id" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  err="$(printf '%s' "$err" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$err" ] || err="Failure"
  printf '%s|%s' "$id" "$err"
  return 0
}

# Parse a runner's output into signatures. Deliberately tolerant: an unparseable line is skipped,
# never guessed at — a wrong signature would mark a real regression as known.
baseline_parse_failures() {  # $1 stack (django|react) → reads stdin, echoes `id|error` per line
  local stack="${1:-django}"
  case "$stack" in
    react)
      # vitest: `× src/x.test.tsx > suite > case` (or `FAIL src/x.test.tsx > case`)
      sed -n -e 's/^[[:space:]]*×[[:space:]]*\(.*\)$/\1/p' \
             -e 's/^[[:space:]]*FAIL[[:space:]]*\(.*\)$/\1/p' \
        | sed -e 's/[[:space:]]*[0-9]*ms$//' -e 's/[[:space:]]*$//' \
        | while IFS= read -r line; do [ -n "$line" ] && baseline_signature "$line" "TestFailure" && echo; done
      ;;
    *)
      # pytest short summary: `FAILED path::test - AssertionError: msg`  |  `ERROR path::test - ...`
      grep -E '^(FAILED|ERROR) ' 2>/dev/null \
        | while IFS= read -r line; do
            local id err
            id="${line#* }"; id="${id%% - *}"
            err="${line#* - }"; [ "$err" = "$line" ] && err="" || err="${err%%:*}"
            baseline_signature "$id" "$err"; echo
          done
      ;;
  esac
  return 0
}

# Extract exactly ONE suite's object by brace depth — a naive "everything after the key" would leak
# the following suites' failures into the scope, which is how a frontend signature ends up counting
# as a known backend failure.
_baseline_scope() {  # $1 suite (empty = whole file) — reads json on stdin
  awk -v s="${1:-}" '
    { buf = buf $0 "\n" }
    END {
      if (s == "") { printf "%s", buf; exit }
      key = "\"" s "\""
      i = index(buf, key); if (i == 0) exit
      rest = substr(buf, i + length(key))
      j = index(rest, "{"); if (j == 0) exit
      depth = 0
      for (k = j; k <= length(rest); k++) {
        c = substr(rest, k, 1)
        if (c == "{") depth++
        else if (c == "}") { depth--; if (depth == 0) break }
        out = out c
      }
      printf "%s", out
    }'
  return 0
}

_baseline_sigs() {  # $1 root, [$2 suite] → recorded signatures, one per line
  local f suite="${2:-}"; f="$(baseline_file "${1:-.}")"
  [ -n "$f" ] || return 0
  # Flat, dependency-free JSON scan (no jq): pair each "id" with the "error" that follows it.
  local body; body="$(_baseline_scope "$suite" < "$f")"
  printf '%s' "$body" | tr ',' '\n' \
    | sed -n -e 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/ID\1/p' \
             -e 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/ER\1/p' \
    | awk '/^ID/{id=substr($0,3); next} /^ER/{if(id!=""){print id "|" substr($0,3); id=""}} END{if(id!="")print id "|Failure"}'
  return 0
}

baseline_count() {  # $1 root, [$2 suite]
  _baseline_sigs "${1:-.}" "${2:-}" | grep -c . || true
  return 0
}

baseline_has() {  # $1 root, $2 signature, [$3 suite]
  local sig="${2:-}" found=no line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ "$line" = "$sig" ] && { found=yes; break; }
  done <<EOF
$(_baseline_sigs "${1:-.}" "${3:-}")
EOF
  echo "BASELINE_HIT=$found"
  return 0
}

baseline_classify() {  # $1 root, [$2 suite] — reads signatures on stdin
  local root="${1:-.}" suite="${2:-}" sig new=0 known=0 recorded line
  recorded="$(_baseline_sigs "$root" "$suite")"
  while IFS= read -r sig; do
    [ -n "$sig" ] || continue
    local hit=no
    while IFS= read -r line; do [ "$line" = "$sig" ] && { hit=yes; break; }; done <<EOF
$recorded
EOF
    if [ "$hit" = yes ]; then echo "BASELINE=$sig"; known=$((known+1))
    else                      echo "NEW=$sig";      new=$((new+1)); fi
  done
  echo "NEW_COUNT=$new"
  echo "BASELINE_COUNT=$known"
  if   [ "$new" -gt 0 ];   then echo "BASELINE_VERDICT=new"
  elif [ "$known" -gt 0 ]; then echo "BASELINE_VERDICT=baseline-only"
  else                          echo "BASELINE_VERDICT=clean"
  fi
  return 0
}
