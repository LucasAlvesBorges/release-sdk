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
#   IN  — inputs the run needs to READ (plan, locks, project, state, exec-env). Overwrites freely:
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

# Inputs the run must be able to READ inside the worktree.
_planning_input_paths() {  # $1 phase_glob
  cat <<EOF
RELEASE-LOCKS.md
PROJECT.md
ROADMAP.md
REQUIREMENTS.md
STATE.md
EXEC-ENV.yml
VERIFY-GATE.yml
MODELS.yml
test-baselines.json
phases/${1:-*}
EOF
  return 0
}

planning_sync_in() {  # $1 src_root, $2 worktree, [$3 phase_glob]
  local src="${1:-}" wt="${2:-}" glob="${3:-*}" pd n=0 rel from to
  pd="$(release_planning_dir)"
  [ -n "$src" ] && [ -d "$src/$pd" ] || { echo "PLANNING_SYNC_IN=skipped"; return 0; }
  [ -n "$wt" ] && [ -d "$wt" ]       || { echo "PLANNING_SYNC_IN=failed";  return 0; }

  mkdir -p "$wt/$pd" 2>/dev/null || { echo "PLANNING_SYNC_IN=failed"; return 0; }
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    for from in "$src/$pd/"$rel; do            # unquoted: the phase glob must expand
      [ -e "$from" ] || continue
      to="$wt/$pd/${from#"$src/$pd/"}"
      mkdir -p "$(dirname "$to")" 2>/dev/null
      if cp -R "$from" "$(dirname "$to")/" 2>/dev/null; then n=$((n+1)); else
        echo "PLANNING_SYNC_IN=failed"; echo "PLANNING_SYNC_MISSING=$from"; return 0
      fi
    done
  done <<EOF
$(_planning_input_paths "$glob")
EOF
  echo "PLANNING_SYNC_IN=ok"; echo "PLANNING_SYNC_FILES=$n"
  return 0
}

planning_sync_out() {  # $1 worktree, $2 dst_root, [$3 phase_glob]
  local wt="${1:-}" dst="${2:-}" glob="${3:-*}" pd n=0 miss="" pat f to
  pd="$(release_planning_dir)"
  [ -n "$wt" ] && [ -d "$wt/$pd" ] || { echo "PLANNING_SYNC_OUT=skipped"; return 0; }
  [ -n "$dst" ] && [ -d "$dst" ]   || { echo "PLANNING_SYNC_OUT=failed"; return 0; }

  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    # phase-scoped artifacts + root-level ones (e.g. AUDIT-UAT.md written at the planning root)
    for f in "$wt/$pd/phases/"$glob/$pat "$wt/$pd/$pat"; do
      [ -f "$f" ] || continue
      to="$dst/$pd/${f#"$wt/$pd/"}"
      mkdir -p "$(dirname "$to")" 2>/dev/null
      if cp -p "$f" "$to" 2>/dev/null; then n=$((n+1)); else miss="$miss $f"; fi
    done
  done <<EOF
$(planning_artifact_globs)
EOF

  if [ -n "$miss" ]; then
    echo "PLANNING_SYNC_OUT=failed"; echo "PLANNING_SYNC_MISSING=$miss"; return 0
  fi
  echo "PLANNING_SYNC_OUT=ok"; echo "PLANNING_SYNC_FILES=$n"
  return 0
}
