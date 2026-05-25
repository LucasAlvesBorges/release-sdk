#!/usr/bin/env bash
# django-sdk-hook-version: 0.1.0
# django-pre-commit-gates.sh — Manual pre-commit gate runner.
#
# Not wired to Claude Code PreToolUse by default (too slow). Use as:
#   - A git pre-commit hook: ln -s <this> .git/hooks/pre-commit
#   - A CI step: bash hooks/django-pre-commit-gates.sh
#   - Manually before pushing: ./hooks/django-pre-commit-gates.sh
#
# Exit codes:
#   0 — all gates passed
#   1 — at least one gate failed (see output)
#   2 — environment issue (Python/Django not found)

set -e

# Locate backend dir — try common patterns
BACKEND_DIR=""
for candidate in backend . src; do
  if [ -f "$candidate/manage.py" ]; then
    BACKEND_DIR="$candidate"
    break
  fi
done

if [ -z "$BACKEND_DIR" ]; then
  echo "✗ No manage.py found in backend/, ., or src/ — skipping gates."
  exit 0
fi

PYTHON_BIN="${PYTHON_BIN:-python}"
if ! command -v "$PYTHON_BIN" &>/dev/null; then
  echo "✗ Python not found at \$PYTHON_BIN=$PYTHON_BIN — install or set env var."
  exit 2
fi

FAILED=0

run_gate() {
  local label="$1"
  shift
  echo "→ $label"
  if "$@"; then
    echo "  ✓ pass"
  else
    echo "  ✗ FAIL"
    FAILED=1
  fi
}

# Gate 1: ruff format + lint
if command -v ruff &>/dev/null; then
  run_gate "ruff check" ruff check "$BACKEND_DIR"
  run_gate "ruff format check" ruff format --check "$BACKEND_DIR"
else
  echo "→ ruff: skipped (not installed; pip install ruff)"
fi

# Gate 2: mypy --strict (optional, slow)
if [ "${DJANGO_SDK_MYPY:-0}" = "1" ] && command -v mypy &>/dev/null; then
  run_gate "mypy --strict" mypy --strict "$BACKEND_DIR"
fi

# Gate 3: makemigrations --check --dry-run
run_gate "makemigrations drift check" \
  "$PYTHON_BIN" "$BACKEND_DIR/manage.py" makemigrations --check --dry-run

# Gate 4: smoke tests (N+1, race, memray)
if [ "${DJANGO_SDK_SMOKE:-1}" = "1" ]; then
  if command -v pytest &>/dev/null; then
    SMOKE_PATHS=$(find "$BACKEND_DIR" -path '*/tests/test_*smoke*.py' 2>/dev/null | head -20)
    RACE_PATHS=$(find "$BACKEND_DIR" -path '*/tests/test_*race*.py' 2>/dev/null | head -20)
    if [ -n "$SMOKE_PATHS$RACE_PATHS" ]; then
      run_gate "smoke + race tests" \
        pytest $SMOKE_PATHS $RACE_PATHS -q --tb=short -x
    else
      echo "→ smoke/race tests: none found"
    fi
  fi
fi

# Gate 5: tenant scope check — every TenantModel subclass has empresa field
echo "→ TenantModel empresa-field defense check"
TENANT_VIOLATIONS=$(grep -rn "class.*TenantModel" "$BACKEND_DIR" --include="*.py" 2>/dev/null | \
  grep -v "/tests/" | grep -v "/migrations/" | \
  while IFS=: read -r file lineno match; do
    # Extract class name from match line
    classname=$(echo "$match" | sed -nE 's/^[[:space:]]*class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*$/\1/p')
    [ -z "$classname" ] && continue
    # Search file for `empresa = ` or `empresa: ` in class body (rough heuristic)
    if ! grep -qE "empresa[[:space:]]*[=:]" "$file"; then
      echo "  ✗ $file:$lineno — class $classname (TenantModel) missing 'empresa' field"
    fi
  done)

if [ -n "$TENANT_VIOLATIONS" ]; then
  echo "$TENANT_VIOLATIONS"
  FAILED=1
else
  echo "  ✓ pass"
fi

echo
if [ $FAILED -eq 0 ]; then
  echo "✓ All gates passed."
  exit 0
else
  echo "✗ One or more gates failed. Fix issues before committing."
  exit 1
fi
