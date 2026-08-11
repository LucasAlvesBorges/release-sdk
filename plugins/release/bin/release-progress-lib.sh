#!/usr/bin/env bash
# release-progress-lib.sh — the in-flight state of a running phase, on disk, readable from outside.
#
# SINGLE SOURCE OF TRUTH for "what is this build doing right now?". Sourced by:
#   - agents/wave-executor.md   (writes on every dispatch / land / checkpoint)
#   - agents/tdd-executor.md    (heartbeat when a long task produces no commit)
#   - skills/status/SKILL.md    (reads it — a build in flight instead of blind git-log greps)
#   - bin/test-progress-lib.sh  (the contract test SOURCES this file — no drift)
#
# WHY THIS EXISTS
# A phase runs for hours inside a worktree nobody is watching. From outside, the only signal was
# `git log` on a branch that may go 40 minutes between commits — indistinguishable from a hang. The
# progress file makes the run observable without interrupting it, and (with the heartbeat) makes a
# stall visible as a stall rather than as silence.
#
# ATOMICITY IS THE WHOLE POINT: a reader must never see a half-written file. Every write goes to a
# temp file in the SAME directory (so `mv` is a rename, not a cross-device copy) and is then moved
# into place. A reader either sees the previous state or the next one, never a torn one.
#
# Public API (all echo a verdict and ALWAYS return 0 — house style):
#   progress_path <phase_dir>                   → `<phase_dir>/.progress.json`
#   progress_write <phase_dir> <k=v> [k=v ...]  → atomically MERGES the given keys into the file
#                                                 (unknown keys are kept; `updated_at` is stamped).
#                                                 Echoes `PROGRESS=written` / `PROGRESS=failed`.
#   progress_get <phase_dir> <key>              → the current value, empty when absent
#   progress_stale_seconds <phase_dir>          → seconds since `updated_at` (empty when unknown)
#   progress_heartbeat <phase_dir> <note> [max] → writes a heartbeat ONLY when the file has not been
#                                                 updated for <max> seconds (default 1800 = 30 min).
#                                                 Echoes `HEARTBEAT=written|not-needed|failed`.
#   progress_clear <phase_dir>                  → removes the file (end of phase)
#
# MIRRORING (v0.24.1): the writer lives in the phase WORKTREE; the reader (`/release:status`) looks
# at the MAIN checkout. Artifacts are only synced out at the end of the run, so a heartbeat written
# during the build was invisible exactly when it mattered. Set `RELEASE_PROGRESS_MIRROR=<dir>` (the
# executor sets it to the corresponding phase dir under the main checkout) and every write lands in
# both places, atomically. Unset ⇒ single-file behaviour, unchanged.
#
# The shape (all optional — writers set what they know):
#   {"phase":"110","stage":"execute","scheduler":"readiness","wave":"W3","task":"T12",
#    "tasks_done":7,"tasks_total":19,"in_flight":"T12,T14","envs_active":2,
#    "started_at":"<iso>","updated_at":"<iso>","last_commit":"a1b2c3d","note":"..."}
#
# Values are stored as JSON strings unless they are pure integers. String values are SANITIZED
# (quote → apostrophe, backslash → slash, control chars → space) rather than backslash-escaped:
# every merge re-reads and re-encodes stored values, so escaping would double on each write until
# the file explodes. Sanitizing is idempotent, which is what a merge loop requires.

progress_path() { printf '%s/.progress.json' "${1:-.}"; return 0; }

_progress_now() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo ""; }

# Values are SANITIZED, not backslash-escaped: `"` → `'`, `\` → `/`, control chars → space.
# Escaping would not be idempotent — every merge re-reads the stored value and re-encodes it, so
# `\"` becomes `\\"` becomes `\\\\"`… doubling on each write until the file explodes. Sanitizing is a
# fixed point: sanitize(sanitize(x)) == sanitize(x). A progress note is human prose; losing a quote
# character costs nothing, and the file stays trivially parseable with `[^"]*`.
_progress_escape() {
  printf '%s' "${1:-}" | tr '"\\' "'/" | tr '\n\r\t' '   '
}

progress_get() {  # $1 phase_dir, $2 key
  local f; f="$(progress_path "${1:-.}")"
  [ -f "$f" ] || return 0
  # string value first, then bare number
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$f" | head -1 \
    | grep -q . && { sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$f" | head -1; return 0; }
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$f" | head -1
  return 0
}

_progress_keys() {  # $1 file → existing keys, one per line
  [ -f "$1" ] || return 0
  tr ',' '\n' < "$1" | sed -n 's/.*"\([a-z_][a-z_0-9]*\)"[[:space:]]*:.*/\1/p'
  return 0
}

progress_write() {  # $1 phase_dir, $2.. k=v pairs
  local dir="${1:-.}" f tmp k v pair now out first=1
  shift || true
  [ -d "$dir" ] || { echo "PROGRESS=failed"; return 0; }
  f="$(progress_path "$dir")"; now="$(_progress_now)"

  # collect existing keys that are not being overwritten (a merge, not a replace: the reader relies
  # on started_at surviving a write that only touches `task`)
  local carry="" existing ek
  existing="$(_progress_keys "$f")"
  while IFS= read -r ek; do
    [ -n "$ek" ] || continue
    case " $* " in *" $ek="*) continue;; esac      # being overwritten now
    [ "$ek" = "updated_at" ] && continue           # always restamped
    v="$(progress_get "$dir" "$ek")"
    carry="$carry$ek=$v
"
  done <<EOF
$existing
EOF

  out="{"
  emit() {  # $1 key, $2 value
    case "$2" in
      # A leading zero ("07") is NOT valid JSON as a bare number — phase ids are routinely written
      # that way, so anything with one stays a string.
      ''|*[!0-9]*|0?*) out="$out$( [ "$first" = 1 ] || printf ',' )\"$1\":\"$(_progress_escape "$2")\"" ;;
      *)               out="$out$( [ "$first" = 1 ] || printf ',' )\"$1\":$2" ;;
    esac
    first=0
  }
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    emit "${pair%%=*}" "${pair#*=}"
  done <<EOF
$carry
EOF
  for pair in "$@"; do
    case "$pair" in *=*) ;; *) continue;; esac
    emit "${pair%%=*}" "${pair#*=}"
  done
  emit updated_at "$now"
  out="$out}"

  # ATOMIC: temp file in the SAME dir, then rename. A reader never sees a partial write.
  tmp="$(mktemp "$dir/.progress.XXXXXX" 2>/dev/null)" || { echo "PROGRESS=failed"; return 0; }
  printf '%s\n' "$out" > "$tmp" 2>/dev/null || { rm -f "$tmp"; echo "PROGRESS=failed"; return 0; }
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; echo "PROGRESS=failed"; return 0; }

  # Mirror into the main checkout so the run is observable WHILE it runs, not only after the
  # end-of-phase artifact sync. Same atomic dance; a mirror failure is reported but never fatal —
  # losing observability must not stop the build.
  local mdir="${RELEASE_PROGRESS_MIRROR:-}" mtmp
  if [ -n "$mdir" ] && [ -d "$mdir" ] && [ "$mdir" != "$dir" ]; then
    mtmp="$(mktemp "$mdir/.progress.XXXXXX" 2>/dev/null)" \
      && printf '%s\n' "$out" > "$mtmp" 2>/dev/null \
      && mv -f "$mtmp" "$(progress_path "$mdir")" 2>/dev/null \
      || { rm -f "$mtmp" 2>/dev/null; echo "PROGRESS=mirror-failed"; }
  fi
  echo "PROGRESS=written"
  return 0
}

progress_stale_seconds() {  # $1 phase_dir → seconds since updated_at (empty when unknown)
  local f mt now; f="$(progress_path "${1:-.}")"
  [ -f "$f" ] || return 0
  mt="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)" || return 0
  now="$(date +%s 2>/dev/null)"; [ -n "$now" ] && [ -n "$mt" ] || return 0
  printf '%s' "$(( now - mt ))"
  return 0
}

progress_heartbeat() {  # $1 phase_dir, $2 note, [$3 max_quiet_seconds]
  local dir="${1:-.}" note="${2:-working}" max="${3:-1800}" age
  age="$(progress_stale_seconds "$dir")"
  local w
  if [ -z "$age" ] || { [ "$age" -ge "$max" ] 2>/dev/null; }; then
    # no file yet ⇒ this IS the first signal; otherwise the quiet window has elapsed
    w="$(progress_write "$dir" "note=$note" "heartbeat=1")"
    case "$w" in *PROGRESS=written*) echo "HEARTBEAT=written" ;; *) echo "HEARTBEAT=failed" ;; esac
  else
    echo "HEARTBEAT=not-needed"
  fi
  return 0
}

progress_clear() {  # $1 phase_dir
  rm -f "$(progress_path "${1:-.}")" 2>/dev/null
  echo "PROGRESS=cleared"
  return 0
}
