#!/usr/bin/env bash
# release-sdk-hook-version: 0.2.0
# django-validate-commit.sh — PreToolUse hook: enforce Conventional Commits + Django scopes
# Blocks `git commit` with non-conforming messages (exit 2).
#
# Valid scopes:
#   - Django app labels:        feat(financeiro): ...
#   - Phase-plan (GSD style):   feat(03-02): ...
#   - Layer:                    feat(backend): ..., feat(frontend): ...
#   - Mixed:                    feat(financeiro,backend): ...
#
# OPT-OUT: Set DJANGO_SDK_DISABLE_COMMIT_HOOK=1 to skip.

if [ "${DJANGO_SDK_DISABLE_COMMIT_HOOK:-0}" = "1" ]; then
  exit 0
fi

INPUT=$(cat)

# Extract command from JSON via Node (no jq dependency)
CMD=$(echo "$INPUT" | node -e "
let d='';
process.stdin.on('data',c=>d+=c);
process.stdin.on('end',()=>{
  try { process.stdout.write(JSON.parse(d).tool_input?.command || '') } catch {}
});
" 2>/dev/null)

# Only check git commit. Walk tokens to skip env-prefix and -C path.
IS_COMMIT=$(node -e "
const cmd = process.argv[1] || '';
const tokens = cmd.split(/\s+/).filter(Boolean);
let i = 0;
while (i < tokens.length && /^[A-Z_][A-Z0-9_]*=/.test(tokens[i])) i++;
let gitIdx = -1;
for (let j = i; j < tokens.length; j++) {
  if (tokens[j] === 'git' || tokens[j].endsWith('/git')) { gitIdx = j; break; }
}
if (gitIdx === -1) { process.exit(1); }
let k = gitIdx + 1;
while (k < tokens.length) {
  if (tokens[k] === '-C' || tokens[k] === '-c' || tokens[k].startsWith('--git-dir')) { k += 2; continue; }
  break;
}
process.exit(tokens[k] === 'commit' ? 0 : 1);
" "$CMD" 2>/dev/null)

if [ $? -ne 0 ]; then
  exit 0  # Not a git commit — allow
fi

# Extract message from -m flag (single or double quoted)
MSG=""
if [[ "$CMD" =~ -m[[:space:]]+\"([^\"]+)\" ]]; then
  MSG="${BASH_REMATCH[1]}"
elif [[ "$CMD" =~ -m[[:space:]]+\'([^\']+)\' ]]; then
  MSG="${BASH_REMATCH[1]}"
fi

# Allow commits without -m (interactive editor or heredoc) — can't validate
if [ -z "$MSG" ]; then
  exit 0
fi

# Allow command substitution / heredoc passed to -m — regex captures the literal
# `$(cat <<'EOF'...EOF)` before shell expansion, so MSG isn't the real subject.
if [[ "$MSG" =~ \$\(cat || "$MSG" =~ \<\<\' || "$MSG" =~ \<\<\" || "$MSG" =~ \<\<[A-Za-z_] ]]; then
  exit 0
fi

SUBJECT=$(echo "$MSG" | head -1)

# Conventional Commits regex — scope is optional, accepts comma-separated
TYPE_RE='(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)'
SCOPE_RE='(\([a-z0-9_,-]+\))?'
PATTERN="^${TYPE_RE}${SCOPE_RE}!?: .+"

if ! [[ "$SUBJECT" =~ $PATTERN ]]; then
  cat <<'JSON'
{
  "decision": "block",
  "code": "CONVENTIONAL_COMMITS_VIOLATION",
  "reason": "Commit message must follow Conventional Commits: <type>(<scope>): <subject>. Valid types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert. Scope optional, e.g.: feat(financeiro): ..., feat(03-02): ..., feat(backend,frontend): ..."
}
JSON
  exit 2
fi

if [ ${#SUBJECT} -gt 72 ]; then
  cat <<JSON
{
  "decision": "block",
  "code": "COMMIT_SUBJECT_TOO_LONG",
  "reason": "Commit subject must be 72 characters or less. Current: ${#SUBJECT}."
}
JSON
  exit 2
fi

exit 0
