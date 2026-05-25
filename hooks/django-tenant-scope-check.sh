#!/usr/bin/env bash
# release-sdk-hook-version: 0.2.0
# django-tenant-scope-check.sh — PreToolUse hook (advisory)
#
# Scans Write/Edit content for new `class X(models.Model)` declarations that
# do NOT inherit TenantModel. Emits advisory — multi-tenant projects should
# almost always use TenantModel.
#
# OPT-OUT per file via comment marker: `# django-sdk: no-tenant-check`

INPUT=$(cat)

CONTENT=$(echo "$INPUT" | node -e "
let d='';
process.stdin.on('data',c=>d+=c);
process.stdin.on('end',()=>{
  try {
    const j = JSON.parse(d);
    const c = j.tool_input?.content || j.tool_input?.new_string || '';
    process.stdout.write(c);
  } catch {}
});
" 2>/dev/null)

FILE_PATH=$(echo "$INPUT" | node -e "
let d='';
process.stdin.on('data',c=>d+=c);
process.stdin.on('end',()=>{
  try { process.stdout.write(JSON.parse(d).tool_input?.file_path || '') } catch {}
});
" 2>/dev/null)

# Only scan models.py-like paths
if [[ ! "$FILE_PATH" =~ models(/[^/]+)?\.py$ ]] && [[ ! "$FILE_PATH" =~ models\.py$ ]]; then
  exit 0
fi

# Skip if file opted out
if echo "$CONTENT" | grep -q "django-sdk: no-tenant-check"; then
  exit 0
fi

# Skip migrations
if [[ "$FILE_PATH" =~ /migrations/ ]]; then
  exit 0
fi

# Find class definitions inheriting models.Model directly (not TenantModel or other base)
VIOLATIONS=$(echo "$CONTENT" | grep -nE "^class[[:space:]]+[A-Z][A-Za-z0-9_]+\([^)]*models\.Model[^)]*\)" | \
  grep -v "TenantModel" | \
  grep -v "RLSModel" | \
  grep -v "AbstractBaseUser" | \
  grep -v "AbstractUser" | \
  head -5)

if [ -z "$VIOLATIONS" ]; then
  exit 0
fi

# Emit advisory
COUNT=$(echo "$VIOLATIONS" | wc -l | tr -d ' ')
FIRST=$(echo "$VIOLATIONS" | head -1 | cut -d: -f2-)

node -e "
const out = {
  hookSpecificOutput: {
    hookEventName: 'PreToolUse',
    additionalContext:
      '⚠️ TENANT SCOPE WARNING: $COUNT class(es) in ' + ${FILE_PATH@Q} +
      ' inherit models.Model directly (not TenantModel).\n' +
      'First: $FIRST\n' +
      'Multi-tenant projects should use TenantModel to enforce empresa_id isolation. ' +
      'If this is intentional (e.g., global lookup table, system config), add comment: # django-sdk: no-tenant-check'
  }
};
process.stdout.write(JSON.stringify(out));
"

exit 0
