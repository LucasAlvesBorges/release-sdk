#!/usr/bin/env bash
# Contract test for hooks/release-prod-guard.js (v0.27.0).
#
# Coverage:
#   #1  non-Bash tool and harmless commands → silent
#   #2  ssh outside any SDK unit → WARN (exit 0, advisory context), never blocks a freeform session
#   #3  ssh with an active unit marker → BLOCK (exit 2, decision block, code PROD_GUARD)
#   #4  cwd under release-worktrees/ counts as an active unit
#   #5  a fresh .progress.json counts as an active unit; a stale one does not
#   #6  allow: RELEASE_ALLOW_PROD=1, `#allow-prod` marker, .allow-prod file, config allow regex
#   #7  config mode: off → silent; warn → warn even inside a unit; custom pattern blocks
#   #8  built-ins: psql -h, dokploy, DJANGO_ENV=prod, eas submit; `git push` and local psql never match
#
# Run: bash bin/test-prod-guard.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOOK="$HERE/../hooks/release-prod-guard.js"

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }

SBX="$(mktemp -d)"; trap 'rm -rf "$SBX"' EXIT
ROOT="$SBX/proj"; mkdir -p "$ROOT/.release-planning/phases/07-x" "$ROOT/.git"
UNITWT="$SBX/release-worktrees/quick/q1"; mkdir -p "$UNITWT/.git"

# run <cwd> <tool> <command> [env...] → "<exit>|<verdict>" where verdict = silent|warn|block
run() {
  local cwd="$1" tool="$2" cmd="$3"; shift 3
  local payload out rc
  payload="$(node -e 'const [c,t,m]=process.argv.slice(1);process.stdout.write(JSON.stringify({cwd:c,tool_name:t,tool_input:{command:m}}))' "$cwd" "$tool" "$cmd")"
  set +e; out="$(printf '%s' "$payload" | env "$@" node "$HOOK" 2>/dev/null)"; rc=$?; set -e
  case "$out" in
    *'"decision":"block"'*) printf '%s|block' "$rc";;
    *'PROD GUARD'*)         printf '%s|warn' "$rc";;
    '')                     printf '%s|silent' "$rc";;
    *)                      printf '%s|other:%s' "$rc" "$out";;
  esac
}

echo "── #1 silent cases ──"
eq "non-Bash tool" "0|silent" "$(run "$ROOT" Read 'ssh root@1.2.3.4' X=1)"
eq "harmless command" "0|silent" "$(run "$ROOT" Bash 'pytest -q apps/core' X=1)"
eq "git push never matches" "0|silent" "$(run "$ROOT" Bash 'git push origin main' X=1)"
eq "local psql never matches" "0|silent" "$(run "$ROOT" Bash 'psql -U app -d app_dev -c "select 1"' X=1)"

echo "── #2 no unit ⇒ warn only ──"
eq "ssh outside unit → warn" "0|warn" "$(run "$ROOT" Bash 'ssh root@72.60.56.219 docker logs api' X=1)"
eq "ssh host-only form → warn" "0|warn" "$(run "$ROOT" Bash 'ssh prod-vps "uptime"' X=1)"

echo "── #3 active unit marker ⇒ block ──"
touch "$ROOT/.release-planning/.unit-active"
R="$(run "$ROOT" Bash 'ssh root@72.60.56.219 psql -c "alter role app superuser"' X=1)"
eq "ssh inside unit → exit 2 block" "2|block" "$R"
rm -f "$ROOT/.release-planning/.unit-active"
eq "marker removed → back to warn" "0|warn" "$(run "$ROOT" Bash 'ssh root@72.60.56.219 uptime' X=1)"

echo "── #4 cwd under release-worktrees ⇒ block ──"
eq "worktree cwd → block" "2|block" "$(run "$UNITWT" Bash 'ssh root@h uptime' X=1)"

echo "── #5 progress heartbeat ⇒ block while fresh ──"
printf '{"phase":"07"}\n' > "$ROOT/.release-planning/phases/07-x/.progress.json"
eq "fresh .progress.json → block" "2|block" "$(run "$ROOT" Bash 'ssh root@h uptime' X=1)"
touch -t 202001010000 "$ROOT/.release-planning/phases/07-x/.progress.json"
eq "stale .progress.json → warn" "0|warn" "$(run "$ROOT" Bash 'ssh root@h uptime' X=1)"
rm -f "$ROOT/.release-planning/phases/07-x/.progress.json"

echo "── #6 allow paths ──"
touch "$ROOT/.release-planning/.unit-active"
eq "RELEASE_ALLOW_PROD=1 → silent" "0|silent" "$(run "$ROOT" Bash 'ssh root@h uptime' RELEASE_ALLOW_PROD=1)"
eq "#allow-prod marker → silent" "0|silent" "$(run "$ROOT" Bash 'ssh root@h uptime  #allow-prod' X=1)"
touch "$ROOT/.release-planning/.allow-prod"
eq ".allow-prod file → silent" "0|silent" "$(run "$ROOT" Bash 'ssh root@h uptime' X=1)"
rm -f "$ROOT/.release-planning/.allow-prod"
printf 'allow: ssh staging\n' > "$ROOT/.release-planning/PROD-GUARD.yml"
eq "config allow regex → silent" "0|silent" "$(run "$ROOT" Bash 'ssh staging uptime' X=1)"
eq "config allow does not leak to other hosts" "2|block" "$(run "$ROOT" Bash 'ssh prod uptime' X=1)"

echo "── #7 config modes + custom pattern ──"
printf 'mode: off\n' > "$ROOT/.release-planning/PROD-GUARD.yml"
eq "mode off → silent" "0|silent" "$(run "$ROOT" Bash 'ssh prod uptime' X=1)"
printf 'mode: warn\n' > "$ROOT/.release-planning/PROD-GUARD.yml"
eq "mode warn inside unit → warn" "0|warn" "$(run "$ROOT" Bash 'ssh prod uptime' X=1)"
printf 'mode: block\npattern: manage\\.py\\s+rls_rollout\n' > "$ROOT/.release-planning/PROD-GUARD.yml"
eq "custom pattern → block" "2|block" "$(run "$ROOT" Bash 'python manage.py rls_rollout --enable' X=1)"
rm -f "$ROOT/.release-planning/PROD-GUARD.yml"

echo "── #8 built-ins ──"
eq "psql -h remote" "2|block" "$(run "$ROOT" Bash 'psql -h db.internal -U app -c "drop table x"' X=1)"
eq "dokploy" "2|block" "$(run "$ROOT" Bash 'dokploy compose redeploy' X=1)"
eq "DJANGO_ENV=prod" "2|block" "$(run "$ROOT" Bash 'DJANGO_ENV=prod python manage.py migrate' X=1)"
eq "eas submit" "2|block" "$(run "$ROOT" Bash 'eas submit -p ios' X=1)"
eq "eas build --auto-submit" "2|block" "$(run "$ROOT" Bash 'eas build --platform ios --profile production --auto-submit' X=1)"
eq "plain eas build (no submit) stays silent" "0|silent" "$(run "$ROOT" Bash 'eas build --platform ios --profile preview' X=1)"
eq "malformed stdin fails open" "0|silent" "$(printf 'not json' | node "$HOOK" 2>/dev/null; printf '%s|%s' "$?" "silent")"
rm -f "$ROOT/.release-planning/.unit-active"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
