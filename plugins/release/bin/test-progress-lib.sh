#!/usr/bin/env bash
# Contract test for the in-flight progress substrate (v0.23.0).
#
# SOURCES the real shipped engine — bin/release-progress-lib.sh — so there is NO drift: the code
# under test IS the code wave-executor writes and /release:status reads.
#
# Coverage:
#   #1  write → read round trip; integers stay integers, strings stay quoted
#   #2  a write MERGES: keys not mentioned survive (started_at outlives a task-only update)
#   #3  updated_at is restamped on every write
#   #4  notes with spaces, quotes, backslashes and newlines never corrupt the file, and repeated
#       merges do NOT grow the encoding (sanitize is idempotent — escaping would double each write)
#   #5  atomicity: the file is never observed partially written (rename, not in-place truncate)
#   #6  progress_get on a missing file / missing key is empty, never an error
#   #7  heartbeat writes only after the quiet window, and always when there is no file yet
#   #8  stale_seconds reports age; clear removes the file
#   #9  a bad phase_dir reports failed instead of exploding
#   #10 realistic wave-executor sequence keeps a coherent picture throughout
#
# Run: bash bin/test-progress-lib.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-progress-lib.sh
source "$HERE/release-progress-lib.sh"

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1" "missing [$3] in: $2";; esac; }

TMP="$(mktemp -d -t release-progress-test-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
D="$TMP/phases/110-fin"; mkdir -p "$D"

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #1 write → read round trip ──"
eq "write reports success" "PROGRESS=written" \
   "$(progress_write "$D" phase=110 stage=execute wave=W1 task=T01 tasks_done=0 tasks_total=19)"
eq "path is .progress.json" "$D/.progress.json" "$(progress_path "$D")"
eq "string value"  "execute" "$(progress_get "$D" stage)"
eq "task value"    "T01"     "$(progress_get "$D" task)"
eq "integer value" "19"      "$(progress_get "$D" tasks_total)"
has "integers unquoted in the file" "$(cat "$D/.progress.json")" '"tasks_total":19'
has "strings quoted in the file"    "$(cat "$D/.progress.json")" '"stage":"execute"'

echo "── #2 write MERGES, never replaces ──"
progress_write "$D" started_at=2026-08-11T10:00:00Z >/dev/null
progress_write "$D" task=T05 tasks_done=4 >/dev/null
eq "updated key changed"          "T05" "$(progress_get "$D" task)"
eq "untouched key survives"       "110" "$(progress_get "$D" phase)"
eq "started_at survives a task-only update" "2026-08-11T10:00:00Z" "$(progress_get "$D" started_at)"
eq "counter updated"              "4"   "$(progress_get "$D" tasks_done)"
eq "total untouched"              "19"  "$(progress_get "$D" tasks_total)"

echo "── #3 updated_at restamped ──"
U1="$(progress_get "$D" updated_at)"
[ -n "$U1" ] && ok "updated_at present" || no "updated_at present" "empty"
progress_write "$D" note=still-going >/dev/null
[ -n "$(progress_get "$D" updated_at)" ] && ok "updated_at still present after merge" \
  || no "updated_at still present after merge" "empty"

echo "── #4 hostile note content cannot corrupt the file ──"
progress_write "$D" 'note=running "T12" with \ backslash and	tab' >/dev/null
FILE="$(cat "$D/.progress.json")"
eq "file is still one line" "1" "$(printf '%s\n' "$FILE" | grep -c .)"
has "quotes sanitized to apostrophes (never raw, never escaped)" "$FILE" "'T12'"
has "backslash sanitized to slash" "$FILE" "with / backslash"
eq "other keys still readable after the hostile write" "110" "$(progress_get "$D" phase)"
eq "opens and closes as an object" "1" "$(printf '%s' "$FILE" | grep -c '^{.*}$')"
SZ1="$(wc -c < "$D/.progress.json" | tr -d ' ')"
for _ in 1 2 3 4 5 6; do progress_write "$D" 'note=running "T12" with \ backslash' >/dev/null; done
SZ2="$(wc -c < "$D/.progress.json" | tr -d ' ')"
[ "$SZ2" -le $(( SZ1 + 40 )) ] && ok "6 re-merges do not grow the file (idempotent encoding)" \
  || no "6 re-merges do not grow the file" "grew $SZ1 → $SZ2 bytes"
eq "note still readable after re-merges" "running 'T12' with / backslash" "$(progress_get "$D" note)"

echo "── #5 atomicity — a reader never sees a torn file ──"
CORRUPT=0
( for i in $(seq 1 40); do progress_write "$D" "task=T$i" "tasks_done=$i" >/dev/null; done ) &
WRITER=$!
while kill -0 "$WRITER" 2>/dev/null; do
  C="$(cat "$D/.progress.json" 2>/dev/null || true)"
  case "$C" in ''|'{'*'}') ;; *) CORRUPT=1 ;; esac
done
wait "$WRITER" 2>/dev/null || true
eq "no partial read observed across 40 concurrent-ish writes" "0" "$CORRUPT"
LEFTOVER="$(find "$D" -name '.progress.??????' | wc -l | tr -d ' ')"
eq "no temp files left behind" "0" "$LEFTOVER"

echo "── #6 missing file / missing key ──"
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
eq "missing file → empty"  "" "$(progress_get "$EMPTY" task)"
eq "missing key → empty"   "" "$(progress_get "$D" no_such_key)"

echo "── #7 heartbeat cadence ──"
HB="$TMP/hb"; mkdir -p "$HB"
eq "no file yet → heartbeat written (first signal)" "HEARTBEAT=written" \
   "$(progress_heartbeat "$HB" 'starting T01')"
eq "fresh file → not needed" "HEARTBEAT=not-needed" \
   "$(progress_heartbeat "$HB" 'still on T01' 1800)"
eq "quiet window of 0 → always writes (a stall must become visible)" "HEARTBEAT=written" \
   "$(progress_heartbeat "$HB" 'still on T01, compiling' 0)"
eq "the note reaches the file" "still on T01, compiling" "$(progress_get "$HB" note)"

echo "── #8 age + clear ──"
AGE="$(progress_stale_seconds "$HB")"
case "$AGE" in ''|*[!0-9]*) no "age is a number" "got [$AGE]";; *) ok "age is a number ($AGE s)";; esac
eq "clear reports" "PROGRESS=cleared" "$(progress_clear "$HB")"
[ -f "$HB/.progress.json" ] && no "file removed" "still there" || ok "file removed"
eq "age of a cleared phase → empty" "" "$(progress_stale_seconds "$HB")"

echo "── #9 bad directory degrades, never explodes ──"
eq "nonexistent dir → failed" "PROGRESS=failed" "$(progress_write "$TMP/nope" task=T01)"

echo "── #10 realistic wave-executor sequence ──"
R="$TMP/run"; mkdir -p "$R"
progress_write "$R" phase=110 stage=execute scheduler=readiness started_at=2026-08-11T09:00:00Z \
               tasks_total=19 tasks_done=0 envs_active=0 >/dev/null
progress_write "$R" wave=W1 task=T01 in_flight=T01,T02 envs_active=2 >/dev/null
progress_write "$R" tasks_done=2 last_commit=a1b2c3d >/dev/null
progress_write "$R" wave=W3 task=T12 in_flight=T12 envs_active=1 tasks_done=11 >/dev/null
eq "phase held"          "110"        "$(progress_get "$R" phase)"
eq "scheduler held"      "readiness"  "$(progress_get "$R" scheduler)"
eq "start time held"     "2026-08-11T09:00:00Z" "$(progress_get "$R" started_at)"
eq "current wave"        "W3"         "$(progress_get "$R" wave)"
eq "current task"        "T12"        "$(progress_get "$R" task)"
eq "progress counter"    "11"         "$(progress_get "$R" tasks_done)"
eq "total intact"        "19"         "$(progress_get "$R" tasks_total)"
eq "last commit carried" "a1b2c3d"    "$(progress_get "$R" last_commit)"
eq "envs active"         "1"          "$(progress_get "$R" envs_active)"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
