#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }

quote() {
  node "$HERE/release-token-worker.js" --quote-model "$1" |
    node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(String(JSON.parse(d).in)))"
}

echo "── conservative model-family pricing ──"
eq "known Sonnet remains Sonnet-priced" "3" "$(quote claude-sonnet-4-6)"
eq "future Opus does not fall back to Sonnet" "15" "$(quote claude-opus-4-8)"
eq "Fable uses conservative top-tier fallback" "15" "$(quote claude-fable-5)"
eq "unknown model keeps default price" "3" "$(quote unknown-model)"

TMP_EVENTS="$(mktemp -t release-token-events-XXXXXX)"
trap 'rm -f "$TMP_EVENTS"' EXIT
printf '%s\n' \
  '{"ts":1,"session_id":"s","model":"claude-sonnet-4-6","input":10,"workflow":"release:execute","skill":"release:execute","phase":"03","complexity":"C2","mode":"workflow","latency_ms":100,"spawns":1,"gate_runs":0}' \
  '{"ts":2,"session_id":"s","model":"claude-sonnet-4-6","output":5,"workflow":"release:execute>release-tdd-executor","skill":"release:execute","agent":"release-tdd-executor","phase":"03","complexity":"C2","mode":"agent","latency_ms":300,"spawns":0,"gate_runs":1}' > "$TMP_EVENTS"
STATS="$(node "$HERE/release-token-worker.js" --stats-file "$TMP_EVENTS")"
field() { printf '%s' "$STATS" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const x=JSON.parse(d);process.stdout.write(String($1))})"; }
eq "workflow dimension aggregates" "1" "$(field "x.by_workflow['release:execute'].turns")"
eq "agent dimension aggregates" "1" "$(field "x.by_agent['release-tdd-executor'].turns")"
eq "phase dimension aggregates" "2" "$(field "x.by_phase['03'].turns")"
eq "complexity dimension aggregates" "2" "$(field "x.by_complexity.C2.turns")"
eq "mode dimension separates agents" "1" "$(field "x.by_mode.agent.turns")"
eq "spawn count aggregates" "1" "$(field "x.all_time.spawns")"
eq "gate count aggregates" "1" "$(field "x.all_time.gate_runs")"
eq "latency aggregates" "400" "$(field "x.all_time.latency_ms")"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
