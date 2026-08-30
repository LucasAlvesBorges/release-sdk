#!/usr/bin/env bash
# release-planning-sync-lib.sh — carry `.release-planning/` INTO a phase worktree and the produced
# artifacts BACK OUT before anything is torn down.
#
# SINGLE SOURCE OF TRUTH for "does the worktree have the plan, and did its outputs survive?".
# Sourced by:
#   - skills/execute/SKILL.md          (sync in at setup; sync out BEFORE land/teardown)
#   - agents/wave-executor.md          (sync out after the terminal wave, before wave-worktree cleanup)
#   - bin/test-planning-sync-lib.sh    (the contract test SOURCES this file — no drift)
#
# WHY THIS EXISTS
# `.release-planning/` is untracked (v0.15.0 made STATE local + gitignored). `git worktree add`
# only materializes TRACKED files, so a freshly created phase worktree is born WITHOUT the PLAN it
# is supposed to execute — and, worse, the SUMMARY/VERIFICATION the run produces live only inside
# that worktree. Removing the worktree then deletes them. That is not hypothetical: a real run lost
# its SUMMARY that way.
#
# THE ASYMMETRY IS DELIBERATE
#   IN  — inputs the run needs to READ (plan, locks, project, state, stable dev runner). Overwrites freely:
#         the main checkout is the source of truth for inputs.
#   OUT — outputs the run PRODUCED (SUMMARY / WAVE-SUMMARY / VERIFICATION / CHECK / AUDIT / UAT …).
#         NEVER copies scratch (PLAN-SLICE-*, .exec-start-sha, test-inventory, sweep-B*.json) and
#         NEVER deletes anything on the destination — a copy-back must not be able to destroy the
#         main checkout's planning dir.
#
# Public API (all echo a verdict and ALWAYS return 0 — house style; callers parse the echo):
#   planning_sync_in  <src_root> <worktree> [phase_glob]
#       Copies the planning INPUTS into <worktree>/.release-planning/. Echoes
#       `PLANNING_SYNC_IN=<ok|skipped|failed>` (+ `PLANNING_SYNC_FILES=<n>`). `skipped` = the source
#       has no `.release-planning/` (nothing to carry) — not an error.
#   planning_sync_out <worktree> <dst_root> [phase_glob]
#       Copies the produced ARTIFACTS back. Echoes `PLANNING_SYNC_OUT=<ok|skipped|failed>` (+
#       `PLANNING_SYNC_FILES=<n>`, and `PLANNING_SYNC_MISSING=<paths>` when a file could not be
#       copied). **A `failed` here MUST abort the caller's teardown/land** — losing the artifacts is
#       worse than leaving a worktree behind.
#   planning_artifact_globs
#       Echoes the output patterns (one per line) — the single place the "what is an artifact"
#       decision lives, so callers never hand-roll it.
#
# Env overrides:
#   RELEASE_PLANNING_DIR   planning dir name (default `.release-planning`)

release_planning_dir() { printf '%s' "${RELEASE_PLANNING_DIR:-.release-planning}"; return 0; }

# Outputs a run PRODUCES and that must survive teardown. Scratch is deliberately absent.
planning_artifact_globs() {
  cat <<'EOF'
*-SUMMARY.md
*-SUMMARY-*.md
*-WAVE-SUMMARY.md
*-WAVE-SUMMARY-*.md
*-VERIFICATION.md
*-PLAN-CHECK*.md
*-CHECKLIST.md
*-REVIEW.md
*-UI-REVIEW.md
*-ARCH-REVIEW.md
*-SECURITY.md
*-TEST-AUDIT.md
*-TEST-GAP.md
*-NYQUIST-AUDIT.md
*-EVAL-REVIEW.md
*-INTEGRATION-CHECK.md
*-DEBUG.md
*-UAT.md
.progress.json
EOF
  return 0
}

# Root-level inputs the run must be able to READ inside the worktree (phase dirs handled separately).
_planning_root_inputs() {
  cat <<'EOF'
RELEASE-LOCKS.md
PROJECT.md
ROADMAP.md
REQUIREMENTS.md
STATE.md
EXEC-ENV.yml
VERIFY-GATE.yml
MODELS.yml
test-baselines.json
EOF
  return 0
}

planning_sync_in() {  # $1 src_root, $2 worktree, [$3 phase_glob]
  local src="${1:-}" wt="${2:-}" glob="${3:-*}" pd n=0 rel from to
  pd="$(release_planning_dir)"
  [ -n "$src" ] && [ -d "$src/$pd" ] || { echo "PLANNING_SYNC_IN=skipped"; return 0; }
  [ -n "$wt" ] && [ -d "$wt" ]       || { echo "PLANNING_SYNC_IN=failed";  return 0; }
  mkdir -p "$wt/$pd" 2>/dev/null || { echo "PLANNING_SYNC_IN=failed"; return 0; }

  # Root-level inputs: plain existence checks, no globbing.
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    from="$src/$pd/$rel"; [ -e "$from" ] || continue
    if cp -R "$from" "$wt/$pd/" 2>/dev/null; then n=$((n+1)); else
      echo "PLANNING_SYNC_IN=failed"; echo "PLANNING_SYNC_MISSING=$from"; return 0
    fi
  done <<EOF
$(_planning_root_inputs)
EOF

  # Phase dirs: matched with `find`, never with a shell glob. An unmatched glob is an ERROR in zsh
  # (nomatch), which aborted this loop after the first pattern and left the worktree WITHOUT its
  # PLAN — the precise failure this lib exists to prevent, in the shell the harness actually uses.
  if [ -d "$src/$pd/phases" ]; then
    mkdir -p "$wt/$pd/phases" 2>/dev/null
    while IFS= read -r from; do
      [ -n "$from" ] || continue
      if cp -R "$from" "$wt/$pd/phases/" 2>/dev/null; then n=$((n+1)); else
        echo "PLANNING_SYNC_IN=failed"; echo "PLANNING_SYNC_MISSING=$from"; return 0
      fi
    done <<EOF
$(find "$src/$pd/phases" -mindepth 1 -maxdepth 1 -name "$glob" 2>/dev/null)
EOF
  fi

  echo "PLANNING_SYNC_IN=ok"; echo "PLANNING_SYNC_FILES=$n"
  return 0
}

# Candidate artifact paths for one pattern: phase-scoped hits under `phases/<glob>/` plus
# root-level hits directly under the planning dir. A separate function on purpose — an inline
# `find | while` inside a heredoc substitution is exactly the kind of construct that parses
# differently across shells.
_planning_out_candidates() {  # $1 wt, $2 pd, $3 pattern, $4 phase_glob
  local wt="$1" pd="$2" pat="$3" glob="$4" c rest dir allowed
  # The set of phase dirs the glob selects is resolved by `find`, then matched EXACTLY. Not by
  # `case "$dir" in $glob)`: bash re-parses an unquoted variable in a case pattern as a glob, zsh
  # does NOT — it compares literally, so every phase-scoped artifact was silently skipped there.
  allowed="$(find "$wt/$pd/phases" -mindepth 1 -maxdepth 1 -name "$glob" 2>/dev/null \
             | while IFS= read -r d; do printf '%s\n' "${d##*/}"; done)"
  find "$wt/$pd" -maxdepth 3 -name "$pat" -type f 2>/dev/null | while IFS= read -r c; do
    case "$c" in
      "$wt/$pd/phases/"*)
        rest="${c#"$wt/$pd/phases/"}"
        case "$rest" in */*) dir="${rest%%/*}" ;; *) continue ;; esac
        printf '%s\n' "$allowed" | grep -qxF "$dir" && printf '%s\n' "$c" ;;
      "$wt/$pd/"*)
        rest="${c#"$wt/$pd/"}"
        case "$rest" in */*) ;; *) printf '%s\n' "$c" ;; esac ;;
    esac
  done
  return 0
}

planning_sync_out() {  # $1 worktree, $2 dst_root, [$3 phase_glob]
  local wt="${1:-}" dst="${2:-}" glob="${3:-*}" pd n=0 miss="" pat f to
  pd="$(release_planning_dir)"
  [ -n "$wt" ] && [ -d "$wt/$pd" ] || { echo "PLANNING_SYNC_OUT=skipped"; return 0; }
  [ -n "$dst" ] && [ -d "$dst" ]   || { echo "PLANNING_SYNC_OUT=failed"; return 0; }

  # `find`, never a shell glob: zsh treats an unmatched pattern as an ERROR, which would abort the
  # loop and silently skip artifacts — and this function's failure mode is "the SUMMARY is gone".
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] && [ -f "$f" ] || continue
      to="$dst/$pd/${f#"$wt/$pd/"}"
      mkdir -p "$(dirname "$to")" 2>/dev/null
      if cp -p "$f" "$to" 2>/dev/null; then n=$((n+1)); else miss="$miss $f"; fi
    done <<INNER
$(_planning_out_candidates "$wt" "$pd" "$pat" "$glob")
INNER
  done <<EOF
$(planning_artifact_globs)
EOF

  if [ -n "$miss" ]; then
    echo "PLANNING_SYNC_OUT=failed"; echo "PLANNING_SYNC_MISSING=$miss"; return 0
  fi
  echo "PLANNING_SYNC_OUT=ok"; echo "PLANNING_SYNC_FILES=$n"
  return 0
}
