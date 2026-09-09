#!/usr/bin/env bash
# release-merge-lib.sh — shared, serialized, conflict-safe merge-back engine for /release:*.
#
# SINGLE SOURCE OF TRUTH. Sourced by:
#   - skills/quick/SKILL.md                    — quick/<label>   → base   (auto-land on green)
#   - skills/execute/SKILL.md                  — feat/<NN>-<slug> → base   (auto-land at phase end)
#   - skills/land/SKILL.md                     — re-land held-dirty / --no-merge units; --push / --cross
#   - bin/release-gc-lib.sh                    — prunes what a land left behind (merged + clean units)
#   - bin/test-merge-lib.sh                    — the contract test exercises THIS file (no drift)
#
# Public API:
#   land_branch <branch> <worktree> <base> [--keep]
#       Brings <branch>'s work back onto <base>, serialized per-base + conflict-safe.
#       Echoes exactly one `RESULT=<status>` line and ALWAYS returns 0.
#       <worktree> MUST still exist (the engine syncs base INTO it first) — call BEFORE teardown.
#       --keep: land but preserve the worktree + branch (default: tear both down on success).
#
#   RESULT values:
#     merged        work landed on base; worktree + branch torn down (unless --keep)
#     conflict      CODE conflict bringing base into the unit — STOPPED, base untouched, unit kept
#     refused       merge refused before it started (e.g. untracked-file collision) — base untouched
#     held-dirty    base IS checked out live and has uncommitted tracked changes — NEVER clobbered;
#                   unit kept, retry with /release:land after you commit/stash the base checkout
#     locked        another land is merging into this base right now — retry in a moment
#     planningblock base tracks planning beyond base-branch (regression) — refused, no silent delete
#     baseadvanced  base moved under us outside the lock — merge aborted, base byte-identical, re-run
#     error         bad args, missing branch, or dirty/missing unit worktree
#
#   release_project_setting <main_root> <key>   → value of `key: value` from .release-planning/PROJECT.md
#                                                  (first match, trimmed; empty when absent)
#   release_push_policy <main_root>             → never | ask | auto   (PROJECT.md `push_after_land:`;
#                                                  default never — for this user push == deploy)
#   land_push <main_root> <base>                → pushes <base> to origin. Echoes PUSH=pushed|failed|no-remote
#   land_report <result> <base> <main_root> <push_state> [unit]
#                                               → the ONE fixed line every land-capable skill ends with:
#                                                  `LAND: merged main@abc1234 · PUSH: no (…) · UNIT: removed`
#                                                  so the user never has to ask "fez push?" again.
#
# Invariants (see test-merge-lib.sh):
#   - Lock FIRST, then sync + merge UNDER the lock — atomic fan-in, no TOCTOU window.
#   - Conflicts surface IN THE UNIT (base→unit first), so a live base checkout is never half-merged.
#   - Planning is local-only: stripped from every merge; never leaks into base.
#   - cwd-safe teardown: cd MAIN_ROOT before removing the unit worktree; branch -D gated on ancestor-of-base.
#   - Slash-safe per-base lock; a dead holder's stale lock is reclaimed.

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────
release_main_root() {  # the MAIN worktree root — first porcelain entry; stable from ANY worktree
  git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}'
}

release_base_token() {  # filename-safe token for a base name that may contain slashes (release/v2 → release_v2)
  printf '%s' "$1" | tr '/' '_'
}

release_read_base() {  # the trunk: .release-planning/base-branch (from MAIN_ROOT) > current branch of MAIN_ROOT
  local mr; mr="$(release_main_root)"
  cat "$mr/.release-planning/base-branch" 2>/dev/null \
    || git -C "$mr" rev-parse --abbrev-ref HEAD
}

release_untrack_planning() {  # $1 = worktree — strip ALL planning from the index but keep base-branch tracked
  local wt="$1"
  # If base-branch itself conflicted, resolve to the INCOMING (base) version while merge stages still exist,
  # else the re-track below would re-add a file full of conflict markers.
  if git -C "$wt" ls-files -u -- .release-planning/base-branch 2>/dev/null | grep -q .; then
    git -C "$wt" checkout --theirs -- .release-planning/base-branch 2>/dev/null || true
    git -C "$wt" add -- .release-planning/base-branch 2>/dev/null || true
  fi
  git -C "$wt" rm -r --cached --quiet --ignore-unmatch -- .release-planning/ >/dev/null 2>&1 || true
  [ -f "$wt/.release-planning/base-branch" ] && git -C "$wt" add -f -- .release-planning/base-branch || true
}

release_sync_base_into() {  # $1 worktree, $2 base — bring base INTO the unit. 0 synced, 2 code-conflict, 3 refused, 1 error
  local wt="$1" base="$2" mrc code
  [ -d "$wt" ] || return 1
  [ -z "$(git -C "$wt" status --porcelain --untracked-files=no)" ] || return 1
  git -C "$wt" merge "$base" --no-commit --no-ff >/dev/null 2>&1; mrc=$?
  # A REFUSED merge (e.g. an untracked unit file that base now tracks) exits non-zero with NO MERGE_HEAD
  # and NO unmerged entries — it never started. Do NOT mistake that for "already in sync".
  if [ "$mrc" -ne 0 ] && ! git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
       && [ -z "$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null)" ]; then
    return 3
  fi
  # A CODE conflict (anything outside .release-planning/) stops the whole thing — author resolves in the unit.
  code="$(git -C "$wt" diff --name-only --diff-filter=U -- ':(exclude).release-planning/' 2>/dev/null || true)"
  if [ -n "$code" ]; then git -C "$wt" merge --abort 2>/dev/null || true; return 2; fi
  # Planning-only conflicts auto-resolve by untracking (planning never belongs in a merge).
  release_untrack_planning "$wt"
  if git -C "$wt" diff --cached --quiet && ! git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then :
  else git -C "$wt" commit --no-edit -m "merge($base): sync + untrack planning (local-only)" >/dev/null; fi
  return 0
}

# ── public: land a branch's work back onto base ────────────────────────────────────────────────────
land_branch() {  # <branch> <worktree> <base> [--keep]
  local br="${1:-}" wt="${2:-}" BASE="${3:-}" keep=""
  [ "${4:-}" = "--keep" ] && keep=1
  local MAIN_ROOT LOCK_DIR lock temp="" basewt rc hp
  MAIN_ROOT="$(release_main_root)"

  [ -n "$br" ] && [ -n "$BASE" ] && [ -n "$wt" ] || { echo "RESULT=error"; return 0; }
  git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$br" || { echo "RESULT=error"; return 0; }
  git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$BASE" || { echo "RESULT=error"; return 0; }

  # data-loss guard: base tracks planning beyond base-branch? refuse before ANY op (never silent-delete).
  if [ -n "$(git -C "$MAIN_ROOT" ls-tree -r --name-only "$BASE" -- .release-planning/ 2>/dev/null | grep -v '^\.release-planning/base-branch$')" ]; then
    echo "RESULT=planningblock"; return 0
  fi

  # lock FIRST (atomic fan-in; slash-safe; stale-reclaim of a dead holder)
  LOCK_DIR="$MAIN_ROOT/../release-worktrees/.locks"; mkdir -p "$LOCK_DIR"
  lock="$LOCK_DIR/merge-$(release_base_token "$BASE").lock"
  if ! ( set -o noclobber; printf '%s\n' "$br $$" > "$lock" ) 2>/dev/null; then
    hp="$(awk 'NR==1{print $2}' "$lock" 2>/dev/null)"
    if [ -n "$hp" ] && ! kill -0 "$hp" 2>/dev/null; then
      rm -f "$lock"
      ( set -o noclobber; printf '%s\n' "$br $$" > "$lock" ) 2>/dev/null || { echo "RESULT=locked"; return 0; }
    else
      echo "RESULT=locked"; return 0
    fi
  fi

  # [1] sync base INTO the unit UNDER the lock — base cannot move under us; CODE conflict stops here.
  release_sync_base_into "$wt" "$BASE"; rc=$?
  if [ "$rc" = 3 ]; then rm -f "$lock"; echo "RESULT=refused"; return 0; fi
  if [ "$rc" = 2 ]; then rm -f "$lock"; echo "RESULT=conflict"; return 0; fi
  [ "$rc" = 0 ] || { rm -f "$lock"; echo "RESULT=error"; return 0; }

  # [2] locate base's LIVE checkout (a branch lives in ONE worktree). Throwaway if base is checked out nowhere.
  basewt="$(git worktree list --porcelain | awk -v b="refs/heads/$BASE" '/^worktree /{w=substr($0,10)} /^branch /{if($2==b)print w}')"
  if [ -z "$basewt" ]; then
    temp="$MAIN_ROOT/../release-worktrees/.merge-$(release_base_token "$BASE")"
    git -C "$MAIN_ROOT" worktree add -q "$temp" "$BASE" 2>/dev/null || { rm -f "$lock"; echo "RESULT=error"; return 0; }
    basewt="$temp"
  elif [ -n "$(git -C "$basewt" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    # base IS your live testing surface and has uncommitted tracked work → NEVER clobber it. Hold + report.
    rm -f "$lock"; echo "RESULT=held-dirty"; return 0
  fi

  # [3] merge unit → base. unit ⊇ base (step 1) ⇒ clean. GUARD: if base advanced outside our lock, --abort
  #     so base is byte-identical, then report baseadvanced (caller re-runs; the re-sync makes it clean).
  if ! git -C "$basewt" merge --no-ff "$br" -m "merge($br → $BASE)" -q 2>/dev/null; then
    git -C "$basewt" merge --abort 2>/dev/null || true
    [ -n "$temp" ] && git -C "$MAIN_ROOT" worktree remove --force "$temp" 2>/dev/null
    rm -f "$lock"; echo "RESULT=baseadvanced"; return 0
  fi

  # [4] cwd-safe teardown: cd MAIN_ROOT first (the shell's cwd may be inside $wt), then remove + gated -D.
  if [ -z "$keep" ]; then
    cd "$MAIN_ROOT" 2>/dev/null || cd / 2>/dev/null || true
    [ -d "$wt" ] && git -C "$MAIN_ROOT" worktree remove --force "$wt" 2>/dev/null
    if git -C "$MAIN_ROOT" merge-base --is-ancestor "$br" "$BASE" 2>/dev/null; then
      git -C "$MAIN_ROOT" branch -D "$br" >/dev/null 2>&1
    fi
  fi
  [ -n "$temp" ] && git -C "$MAIN_ROOT" worktree remove --force "$temp" 2>/dev/null
  git -C "$MAIN_ROOT" worktree prune 2>/dev/null
  rm -f "$lock"
  echo "RESULT=merged"; return 0
}

# ── project settings, push policy and the fixed post-land line ─────────────────────────────────────
release_project_setting() {  # <main_root> <key> → value of a `key: value` line in .release-planning/PROJECT.md
  local f="${1:-.}/.release-planning/PROJECT.md" key="${2:-}"
  [ -n "$key" ] && [ -f "$f" ] || return 0
  sed -n "s/^[[:space:]]*-*[[:space:]]*\`*${key}\`*[[:space:]]*:[[:space:]]*\(.*\)$/\1/p" "$f" \
    | head -1 | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*`*//; s/`*[[:space:]]*$//'
  return 0
}

release_push_policy() {  # <main_root> → never | ask | auto  (unknown/absent ⇒ never: push == deploy for most repos)
  local v; v="$(release_project_setting "${1:-.}" push_after_land)"
  case "$v" in auto|ask) printf '%s' "$v";; *) printf 'never';; esac
  return 0
}

land_push() {  # <main_root> <base> → PUSH=pushed | failed | no-remote  (always returns 0)
  local mr="${1:-.}" base="${2:-}"
  [ -n "$base" ] || { echo "PUSH=failed"; return 0; }
  git -C "$mr" remote get-url origin >/dev/null 2>&1 || { echo "PUSH=no-remote"; return 0; }
  if git -C "$mr" push origin "$base:$base" >/dev/null 2>&1; then echo "PUSH=pushed"; else echo "PUSH=failed"; fi
  return 0
}

land_report() {  # <result> <base> <main_root> <push_state:pushed|failed|no-remote|skipped|policy-never|policy-ask> [unit]
  local result="${1#RESULT=}" base="${2:-?}" mr="${3:-.}" push="${4:-skipped}" unit="${5:-}" tip push_txt unit_txt
  tip="$(git -C "$mr" rev-parse --short "$base" 2>/dev/null || echo '?')"
  case "$push" in
    pushed)       push_txt="yes (origin/$base = $tip — deploy pipeline may be running)";;
    failed)       push_txt="FAILED (run: git -C '$mr' push origin $base)";;
    no-remote)    push_txt="no remote";;
    policy-never) push_txt="no — push == deploy here; when ready: git push origin $base  (or /release:land --push)";;
    policy-ask)   push_txt="no — answer the push question above, or: git push origin $base";;
    *)            push_txt="no (run: git push origin $base)";;
  esac
  case "$result" in
    merged)       unit_txt="removed"; [ -n "$unit" ] && unit_txt="removed ($unit)"
                  printf 'LAND: merged %s@%s · PUSH: %s · UNIT: %s\n' "$base" "$tip" "$push_txt" "$unit_txt";;
    held-dirty)   printf 'LAND: HELD — %s checkout has uncommitted work; nothing clobbered · PUSH: no · UNIT: kept%s · next: commit/stash on %s, then /release:land\n' "$base" "${unit:+ ($unit)}" "$base";;
    conflict)     printf 'LAND: CONFLICT vs %s · PUSH: no · UNIT: kept%s · next: resolve in the unit worktree, commit, /release:land\n' "$base" "${unit:+ ($unit)}";;
    locked)       printf 'LAND: LOCKED — another land is merging into %s · PUSH: no · UNIT: kept%s · next: /release:land in a moment\n' "$base" "${unit:+ ($unit)}";;
    *)            printf 'LAND: %s · PUSH: no · UNIT: kept%s · next: /release:land\n' "$result" "${unit:+ ($unit)}";;
  esac
  return 0
}
