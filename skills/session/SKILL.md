---
name: session
description: >
  Worktree-native parallel sessions (v0.16.0). Spin up N isolated Claude Code sessions off one
  base branch — each in its own git worktree on a `session/<label>` branch — run any skill
  (quick / plan / execute / auto …) in each, then merge every session back to base with a
  SERIALIZED, conflict-safe merge (base is never left dirty; CODE conflicts STOP, never auto-resolve;
  planning docs are stripped so PRs/merges are code-only). Replaces the sustained-domain `workstreams`
  model. Use when: working multiple independent domains (financeiro / operacional / RH …) in parallel
  and folding them into one trunk.
---

# /release:session — Worktree-Native Parallel Sessions

The execution base of release-sdk. Every unit of parallel work is a **session**: an ephemeral
git worktree on a `session/<label>` branch cut from a **base branch**. Launch one Claude session
per worktree, work independently (disjoint domains ⇒ rare conflicts), and merge each back to the
base when done.

```
              ┌─ session/financeiro   (worktree ../release-worktrees/sessions/financeiro)
 base (dev) ──┼─ session/operacional  (worktree …/operacional)   ──merge──▶ base
              └─ session/rh           (worktree …/rh)
```

The worktree **is** the session. Skills (`quick`, `plan`, `execute`, `auto`, …) run *inside* it and
commit to `session/<label>` — they do **not** each spawn their own worktree. There is no
sustained per-domain branch and no shared mutable cursor to collide on.

## Usage

```
/release:session start <label> [--base <branch>]   # new worktree + session/<label> branch off base
/release:session sync  [<label>]                   # pull base INTO the session (strip planning, stop on code conflict)
/release:session finish [<label>] [--keep] [--pr]  # serialized conflict-safe merge back to base
/release:session list                              # all sessions: ahead/behind base, dirty, open PR
/release:session doctor                            # diagnose drift / planning-tracked regression / base-branch
/release:session cleanup                           # remove worktree+branch of any session already merged into base
/release:session abort <label>                     # discard worktree + branch (destructive, confirmed)
/release:session base  [<branch>]                  # show or set the default base branch
```

`<label>` matches `^[a-z][a-z0-9-]{1,39}$`. Run `sync` / `finish` from inside a session worktree to
omit `<label>` — it's auto-detected from the worktree's `.session` marker.

---

## Internal helpers (used by `sync` / `finish` / `list` / `doctor` / `cleanup`)

Resolve once, up front. **`MAIN_ROOT` is the load-bearing anchor** — every destructive git op runs
against it via `git -C "$MAIN_ROOT"` (or after `cd "$MAIN_ROOT"`), never against the worktree being
removed, so cleanup can't crash by deleting the shell's own cwd (see `finish`, step 6).

```bash
# The MAIN worktree root — first entry of the porcelain list. Stable from ANY worktree.
MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"

# Base resolution: --base flag  >  .release-planning/base-branch (read from MAIN_ROOT)  >  current branch
read_base() { cat "$MAIN_ROOT/.release-planning/base-branch" 2>/dev/null || git -C "$MAIN_ROOT" rev-parse --abbrev-ref HEAD; }
BASE="${BASE_FLAG:-$(read_base)}"

SESS_DIR="$MAIN_ROOT/../release-worktrees/sessions"
LOCK_DIR="$MAIN_ROOT/../release-worktrees/.locks"
session_wt() { echo "$SESS_DIR/$1"; }

# label: explicit arg, else from the .session marker of the current worktree
resolve_label() {
  if [ -n "${1:-}" ]; then echo "$1"; return; fi
  sed -n 's/^label: //p' "$(git rev-parse --show-toplevel)/.release-planning/.session" 2>/dev/null
}

# worktree that currently has $BASE checked out — empty string if none (a branch lives in ONE worktree)
base_wt() {
  git worktree list --porcelain | awk -v b="refs/heads/$BASE" '
    /^worktree /{wt=substr($0,10)} /^branch /{if($2==b)print wt}'
}

# Filename-safe token for a base name that may contain slashes (release/v2 → release_v2), so the per-base
# lockfile path never crosses a non-existent intermediate directory (#lock-slash).
base_token() { printf '%s' "$1" | tr '/' '_'; }

# Strip ALL planning from the index but keep base-branch tracked (idempotent; safe on unmerged paths).
# Makes PRs/merges CODE-ONLY and auto-resolves planning conflicts by untracking (#3).
untrack_planning() {  # $1 = worktree
  local wt="$1"
  # If base-branch itself conflicted in this merge, resolve it to the INCOMING (base) version FIRST, while
  # the merge stages still exist — otherwise the re-track below would re-add a file full of `<<<<<<<` (#9).
  if git -C "$wt" ls-files -u -- .release-planning/base-branch 2>/dev/null | grep -q .; then
    git -C "$wt" checkout --theirs -- .release-planning/base-branch 2>/dev/null || true
    git -C "$wt" add -- .release-planning/base-branch 2>/dev/null || true
  fi
  git -C "$wt" rm -r --cached --quiet --ignore-unmatch -- .release-planning/ >/dev/null 2>&1 || true
  [ -f "$wt/.release-planning/base-branch" ] && git -C "$wt" add -f -- .release-planning/base-branch || true
}

# Core merge direction (#2): bring BASE *into* the SESSION so conflicts surface where the author has
# context — never in the live base checkout. Strip planning (#3). Return 0 = synced, 2 = STOP (conflict/refused).
sync_into_session() {  # $1 = session worktree
  local wt="$1" merge_out merge_rc
  [ -d "$wt" ] || { echo "ABORT: session worktree missing: $wt"; exit 1; }
  if [ -n "$(git -C "$wt" status --porcelain --untracked-files=no)" ]; then
    echo "ABORT: session has uncommitted changes. Commit them first."; exit 1
  fi
  # stage the merge but don't commit yet — inspect conflicts + strip planning first
  merge_out="$(git -C "$wt" merge "$BASE" --no-commit --no-ff 2>&1)"; merge_rc=$?
  # A REFUSED merge (e.g. an untracked session file that base now tracks) exits non-zero with NO MERGE_HEAD
  # and NO unmerged entries — it never started. Do NOT mistake that for "already in sync" (#2-refused).
  if [ "$merge_rc" -ne 0 ] \
     && ! git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
     && [ -z "$(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null)" ]; then
    echo "✗ cannot bring $BASE into the session — merge was refused before it started:"
    printf '%s\n' "$merge_out" | sed 's/^/    /'
    echo "  Usually an untracked file collides with one base now tracks. Commit/remove it, then re-run."
    return 2
  fi
  # CODE conflicts only — anything under .release-planning/ is excluded (it's auto-resolved by untracking)
  local code_conflicts
  code_conflicts="$(git -C "$wt" diff --name-only --diff-filter=U -- ':(exclude).release-planning/' 2>/dev/null || true)"
  if [ -n "$code_conflicts" ]; then
    git -C "$wt" merge --abort 2>/dev/null || true        # leave the session exactly as it was
    echo "✗ CODE CONFLICT bringing $BASE into the session:"
    echo "$code_conflicts" | sed 's/^/    /'
    echo "  Resolve IN this session worktree (you have the domain context), commit, then re-run."
    return 2
  fi
  untrack_planning "$wt"                                   # drop planning from the index (+ planning conflicts)
  if git -C "$wt" diff --cached --quiet && ! git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    echo "  already in sync with $BASE (nothing to do)"
  else
    git -C "$wt" commit --no-edit -m "merge($BASE): sync + untrack planning (local-only)" >/dev/null
    echo "  ✓ $BASE synced into session (planning untracked → PR will be code-only)"
  fi
  return 0
}
```

---

## Base branch

The trunk every session forks from and merges into (the user's "branch principal" — e.g. `dev`).

```bash
/release:session base            # prints the resolved base
/release:session base dev        # sets it
```

```bash
cmd_base() {
  if [ -n "${1:-}" ]; then
    git show-ref --verify --quiet "refs/heads/$1" || { echo "ABORT: branch '$1' not found."; exit 1; }
    printf '%s\n' "$1" > "$MAIN_ROOT/.release-planning/base-branch"
    # (#5) Many projects git-ignore .release-planning/ wholesale, so a plain `git add` silently no-ops
    # and the base never persists across checkouts. FORCE-track just this one file.
    git -C "$MAIN_ROOT" add -f -- .release-planning/base-branch
    echo "base → $1  (force-tracked .release-planning/base-branch — commit it to share project-wide)"
    if git -C "$MAIN_ROOT" check-ignore -q .release-planning/base-branch 2>/dev/null; then
      echo "  ⚠ .release-planning/base-branch is git-ignored. To keep ONLY this file tracked, your .gitignore"
      echo "    must re-include it with a negation — which is impossible under a blanket dir-ignore."
      echo "    Use the /* form so a child can be re-included:"
      echo "        .release-planning/*"
      echo "        !.release-planning/base-branch"
    fi
  else
    echo "base: $BASE"
  fi
}
```

> A blanket `.release-planning/` directory-ignore makes the `!` negation impossible — git won't
> descend into an ignored directory to re-include a child. The `.release-planning/*` form (ignore the
> directory's *contents*, not the directory itself) is required so `!.release-planning/base-branch`
> can take effect.

---

## `start <label>`

```bash
# 0. parse args: `start <label> [--base <branch>]`. The flag is the highest-precedence base source.
label=""; BASE_FLAG=""
while [ $# -gt 0 ]; do case "$1" in
  --base) BASE_FLAG="$2"; shift 2;;
  --*) shift;;
  *) label="${label:-$1}"; shift;;
esac; done
BASE="${BASE_FLAG:-$(read_base)}"     # --base flag > base-branch file > current branch (helpers above)

ROOT=$(git rev-parse --show-toplevel)
WT_DIR="$ROOT/../release-worktrees/sessions/$label"
BRANCH="session/$label"

# 1. validate
echo "$label" | grep -qE '^[a-z][a-z0-9-]{1,39}$' || { echo "ABORT: bad label."; exit 1; }
# 2. uniqueness
git show-ref --verify --quiet "refs/heads/$BRANCH" && { echo "ABORT: $BRANCH exists."; exit 1; }
[ -e "$WT_DIR" ] && { echo "ABORT: $WT_DIR exists."; exit 1; }
# 3. resolve base, make sure it exists
git show-ref --verify --quiet "refs/heads/$BASE" || { echo "ABORT: base '$BASE' not found."; exit 1; }
# 4. cut the worktree + branch off base's tip (read-only on base)
mkdir -p "$(dirname "$WT_DIR")"
git worktree prune
git worktree add -b "$BRANCH" "$WT_DIR" "$BASE"
# 5. session marker (local, gitignored) so skills know they're in a session → commit in-place.
#    A freshly-cut worktree off base has NO .release-planning/ dir in the local-only model → mkdir first,
#    otherwise the printf fails and the marker is never written (#start-mkdir).
mkdir -p "$WT_DIR/.release-planning"
printf 'label: %s\nbase: %s\nstarted: <stamp>\n' "$label" "$BASE" > "$WT_DIR/.release-planning/.session"
# 6. ensure local-only planning files are git-ignored in the worktree
for ig in '.release-planning/.session' '.release-planning/STATE.md' '.release-planning/active-workstream'; do
  grep -qxF "$ig" "$WT_DIR/.gitignore" 2>/dev/null || printf '%s\n' "$ig" >> "$WT_DIR/.gitignore"
done
```

Output:

```
✓ Session 'financeiro' started
  Base:    dev (@ a1b2c3)
  Branch:  session/financeiro
  Worktree: ../release-worktrees/sessions/financeiro

Open a Claude session there and work normally:
  cd ../release-worktrees/sessions/financeiro && claude
  /release:plan 03   →   /release:execute 03   (commits land on session/financeiro)

When done:  /release:session finish        (run from inside the worktree)
```

`start` never switches the caller's branch — it only adds a worktree. Launch a *separate* Claude
session in `$WT_DIR`; that session's commits land on `session/<label>` automatically.

---

## `sync [<label>]` — pull base into the session

The drift fix (#4). With N sessions and a moving base, sessions fall behind. `sync` brings the base
into the session **before** any conflict can reach the live base checkout, strips planning, and
**STOPS on a code conflict** (handing it back to the author who has the context). `finish` runs this
as its mandatory first step, so you rarely call it directly — but it's exposed for mid-flight rebasing.

```bash
ROOT=$(git rev-parse --show-toplevel)
MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"
# … (helpers above: read_base / BASE / session_wt / resolve_label / untrack_planning / sync_into_session) …

label="$(resolve_label "${1:-}")"
[ -n "$label" ] || { echo "ABORT: no label (run inside a session worktree or pass one)."; exit 1; }
WT_DIR="$(session_wt "$label")"
# base from THIS session's marker (its fork point) > base-branch file > current branch
BASE="$(sed -n 's/^base: //p' "$WT_DIR/.release-planning/.session" 2>/dev/null)"; BASE="${BASE:-$(read_base)}"
echo "━━━ sync $label ← $BASE ━━━"
sync_into_session "$WT_DIR"
```

A code conflict prints the conflicting paths and returns non-zero; nothing about the base changes.
Resolve in the worktree, commit, re-run. Planning-only conflicts are silently auto-resolved by
untracking (planning is local-only — it never belongs in a merge).

---

## `finish [<label>]` — serialized, conflict-safe merge-back

The load-bearing operation. **Invariants:**

- Base is never left dirty and a **CODE** conflict STOPS the merge — never auto-resolved, never force-pushed.
- Conflicts surface **in the session** (base→session first), so a live base checkout is never mutated by a half-merge.
- Lock **first**, then sync+merge **under** it — atomic fan-in, no TOCTOU window where base advances between the two.
- Planning never leaks: the PR/merge is code-only by construction. If base *tracks* planning, finish hard-stops (never deletes it silently).
- Cleanup can't crash on its own cwd: we `cd "$MAIN_ROOT"` before removing the worktree, and the branch delete is gated on a proven ancestor-of-base check.
- Only one finish touches a given base at a time (slash-safe per-base lock; a dead holder's stale lock is reclaimed).

```bash
ROOT=$(git rev-parse --show-toplevel)
MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"
# … helpers above (base_token/read_base/SESS_DIR/LOCK_DIR/session_wt/resolve_label/base_wt/
#     untrack_planning/sync_into_session) …

# flags + label
PR=false; KEEP=false; ARGLABEL=""
for a in "$@"; do case "$a" in
  --pr) PR=true;; --keep) KEEP=true;; --*) ;; *) ARGLABEL="${ARGLABEL:-$a}";; esac; done
label="$(resolve_label "$ARGLABEL")"
[ -n "$label" ] || { echo "ABORT: no label (run inside a session worktree or pass one)."; exit 1; }
BRANCH="session/$label"; WT_DIR="$(session_wt "$label")"
git show-ref --verify --quiet "refs/heads/$BRANCH" || { echo "ABORT: $BRANCH does not exist."; exit 1; }

# Resolve BASE for THIS session from its marker (records the fork point); fall back to base-branch file /
# current branch. NEVER let base resolve to a session/* branch (#base-resolve).
BASE="$(sed -n 's/^base: //p' "$WT_DIR/.release-planning/.session" 2>/dev/null)"; BASE="${BASE:-$(read_base)}"
case "$BASE" in session/*) echo "ABORT: base resolved to a session branch ('$BASE'). Pin one: /release:session base <branch>."; exit 1;; esac
git show-ref --verify --quiet "refs/heads/$BASE" || { echo "ABORT: base '$BASE' not found."; exit 1; }

echo "━━━ finish $label → $BASE  (pr=$PR) ━━━"

# GUARD (#planning-data-loss): finish STRIPS planning. If base legitimately TRACKS planning beyond
# base-branch (a regression — planning is meant to be local-only), the strip would propagate a DELETE into
# base. Refuse loudly instead of silently losing it. (`doctor` reports this; here we hard-stop before any op.)
BASE_PLANNING="$(git -C "$MAIN_ROOT" ls-tree -r --name-only "$BASE" -- .release-planning/ 2>/dev/null | grep -v '^\.release-planning/base-branch$' || true)"
if [ -n "$BASE_PLANNING" ]; then
  echo "ABORT: base '$BASE' tracks planning files that finish would delete (planning must be local-only):"
  echo "$BASE_PLANNING" | sed 's/^/    /'
  echo "  Untrack them on the base checkout first, then retry:"
  echo "    git rm -r --cached .release-planning && git add -f .release-planning/base-branch && git commit -m 'untrack planning'"
  exit 1
fi

# --pr path: push a CODE-ONLY branch + open PR. No local base merge ⇒ no base lock needed. Worktree is KEPT
# (the merge happens on GitHub; run `cleanup` afterwards). sync still runs to strip planning + carry base.
if $PR; then
  echo "[1/3] sync $BASE → session (strip planning, carry base)…"
  sync_into_session "$WT_DIR" || { echo "→ resolve the code conflict in the session, commit, re-run."; exit 2; }
  echo "[2/3] push branch (code-only) + PR…"
  git -C "$WT_DIR" push -u origin "$BRANCH"
  URL="$(gh pr create --base "$BASE" --head "$BRANCH" \
      --title "$(git -C "$WT_DIR" log -1 --pretty=%s "$BRANCH")" \
      --body "Session \`$label\` → \`$BASE\`. Planning is local-only (not included). 🤖 release-session" 2>/dev/null \
      || gh pr view "$BRANCH" --json url -q .url 2>/dev/null)"
  echo "[3/3] ✓ PR: ${URL:-see 'gh pr list'}  (worktree kept — after the GitHub merge run /release:session cleanup)"
  exit 0
fi

# ── LOCAL MERGE: lock FIRST, then sync + merge atomically UNDER the lock ───────────────────────────────
# Acquiring the lock AFTER sync would open a TOCTOU window: a concurrent finish could advance base between
# our sync and our merge, so "session ⊇ base" goes stale and the base merge conflicts — dirtying base.
# Lock → sync → merge keeps the whole fan-in atomic (#toctou). The lock name is slash-safe (#lock-slash).
mkdir -p "$LOCK_DIR"; MERGE_LOCK="$LOCK_DIR/merge-$(base_token "$BASE").lock"
if ! ( set -o noclobber; printf '%s\n' "$label $$" > "$MERGE_LOCK" ) 2>/dev/null; then
  # Possibly a stale lock from a hard-killed finish (its EXIT trap never fired). Reclaim if the holder PID is dead.
  HOLDER_PID="$(awk 'NR==1{print $2}' "$MERGE_LOCK" 2>/dev/null)"
  if [ -n "$HOLDER_PID" ] && ! kill -0 "$HOLDER_PID" 2>/dev/null; then
    rm -f "$MERGE_LOCK"
    ( set -o noclobber; printf '%s\n' "$label $$" > "$MERGE_LOCK" ) 2>/dev/null \
      || { echo "ABORT: could not reclaim stale lock $MERGE_LOCK — rm it manually if no finish is running."; exit 1; }
    echo "  (reclaimed stale lock from dead PID $HOLDER_PID)"
  else
    echo "ABORT: another finish is merging into '$BASE' (lock $MERGE_LOCK). Retry in a moment."; exit 1
  fi
fi
TEMP_WT=""
# Single EXIT trap tears down BOTH the lock and any throwaway worktree, on every exit path (#temp-trap).
trap 'rm -f "$MERGE_LOCK"; [ -n "$TEMP_WT" ] && git -C "$MAIN_ROOT" worktree remove --force "$TEMP_WT" 2>/dev/null; git -C "$MAIN_ROOT" worktree prune 2>/dev/null' EXIT

# [1] sync base INTO session — UNDER the lock, so base cannot move under us. CODE conflict ⇒ stop, base untouched.
echo "[1/4] sync $BASE → session (conflicts surface here, not in base)…"
sync_into_session "$WT_DIR" || { echo "→ resolve the code conflict in the session, commit, re-run finish."; exit 2; }

# [2] locate base's checkout (a branch lives in ONE worktree): merge in that checkout, or a throwaway one.
echo "[2/4] locate $BASE checkout…"
BASE_WT="$(base_wt)"
if [ -z "$BASE_WT" ]; then
  TEMP_WT="$MAIN_ROOT/../release-worktrees/.merge-$(base_token "$BASE")"
  git -C "$MAIN_ROOT" worktree add "$TEMP_WT" "$BASE" >/dev/null; BASE_WT="$TEMP_WT"
elif [ -n "$(git -C "$BASE_WT" status --porcelain --untracked-files=no)" ]; then
  echo "ABORT: base checkout ($BASE_WT) is dirty. Commit/stash there first."; exit 1
fi

# [3] merge session → base. Session ⊇ base (step 1) ⇒ should be a clean fast-forward. GUARD anyway: if it
#     conflicts (e.g. base advanced via an external push outside our lock), --abort so base is byte-identical.
echo "[3/4] merge session/$label → $BASE (in $BASE_WT)…"
if ! git -C "$BASE_WT" merge --no-ff "$BRANCH" -m "merge(session): $label into $BASE" >/dev/null 2>&1; then
  git -C "$BASE_WT" merge --abort 2>/dev/null || true
  echo "✗ '$BASE' advanced under us — merge aborted, base byte-identical. Re-run finish (it re-syncs)."
  exit 2
fi
N="$(git -C "$BASE_WT" rev-list --count "$BASE@{1}..$BASE" 2>/dev/null || echo '?')"
echo "  ✓ $N commit(s) on $BASE"

# [4] CWD-DRIFT FIX (#1): finish is run FROM INSIDE $WT_DIR. Removing it would yank the shell's own cwd →
#     `fatal: Unable to read current working directory`, and the branch delete would silently NOT run. cd to
#     MAIN_ROOT first, AND drive every op via `git -C "$MAIN_ROOT"`. Delete the branch only once it's proven
#     an ancestor of base (merge landed); -D is safe behind that gate even when the merge used a throwaway.
echo "[4/4] cleanup worktree + branch…"
cd "$MAIN_ROOT" || cd / || true
git -C "$MAIN_ROOT" worktree remove --force "$WT_DIR"
if $KEEP; then
  echo "  worktree removed; branch $BRANCH kept (--keep)"
elif git -C "$MAIN_ROOT" merge-base --is-ancestor "$BRANCH" "$BASE"; then
  git -C "$MAIN_ROOT" branch -D "$BRANCH" && echo "  ✓ worktree + branch $BRANCH removed"
else
  echo "  ⚠ worktree removed but $BRANCH is not an ancestor of $BASE — branch kept for inspection."
fi
# TEMP_WT + lock are torn down by the EXIT trap.
echo "✓ finish $label complete."
```

**Why base→session first (the whole point):** the session author has the context to resolve their
own domain's collision, so a **code** conflict must surface *in the session* — never in the base
checkout (which may carry a live orchestrator session reasoning about stale state). After the session
absorbs base, the session→base merge is a clean fast-forward: a conflict there is impossible. Base is
only ever advanced by clean merges.

`--pr` instead of a local merge: push `session/<label>` (already code-only) and open a PR into `$BASE`
via `gh` (review-gated integration). Use for higher-stakes domains.

---

## `list`

Per session: ahead/behind base, dirty (uncommitted), and open PR number.

```bash
cmd_list() {
  printf '━━━ Sessions (base: %s) ━━━\n' "$BASE"
  printf '%-16s %-7s %-7s %-7s %-6s %s\n' LABEL AHEAD BEHIND DIRTY PR LASTCOMMIT
  git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while read -r wt; do
    case "$wt" in *"/sessions/"*) ;; *) continue;; esac
    lbl="$(sed -n 's/^label: //p' "$wt/.release-planning/.session" 2>/dev/null)"; [ -n "$lbl" ] || lbl="$(basename "$wt")"
    br="session/$lbl"; git show-ref --verify --quiet "refs/heads/$br" || continue
    counts="$(git rev-list --left-right --count "$BASE...$br" 2>/dev/null || echo '? ?')"
    behind="$(echo "$counts" | awk '{print $1}')"; ahead="$(echo "$counts" | awk '{print $2}')"
    dirty=$([ -n "$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null)" ] && echo yes || echo no)
    pr="$(gh pr list --head "$br" --json number -q '.[0].number' 2>/dev/null || true)"; pr="${pr:+#$pr}"; pr="${pr:--}"
    last="$(git -C "$wt" log --oneline -1 2>/dev/null | cut -c1-46)"
    printf '%-16s %-7s %-7s %-7s %-6s %s\n' "$lbl" "$ahead" "$behind" "$dirty" "$pr" "$last"
  done
}
```

```
━━━ Sessions (base: dev) ━━━
LABEL            AHEAD   BEHIND  DIRTY   PR     LASTCOMMIT
financeiro       4       0       no      #182   a1b2c3 feat(financeiro): refund flow
rh               2       1       yes     -      d4e5f6 feat(rh): payroll model
```

`behind > 0` ⇒ base moved since the session forked; `finish` will pull it in (and may stop on a code
conflict). `dirty = yes` ⇒ uncommitted work that blocks `sync`/`finish` until committed.

---

## `doctor` — diagnose drift / regressions

```bash
cmd_doctor() {
  echo "━━━ doctor (base: $BASE) ━━━"
  # (a) planning-tracked regression: anything under .release-planning/ except base-branch
  n="$(git -C "$MAIN_ROOT" ls-files .release-planning/ | grep -vc '^\.release-planning/base-branch$' || true)"
  if [ "${n:-0}" -gt 0 ]; then
    echo "⚠ REGRESSION: $n planning file(s) tracked (should be local-only). Fix:"
    echo "    git rm -r --cached .release-planning && git add -f .release-planning/base-branch && git commit -m 'untrack planning'"
  else
    echo "✓ planning is local-only (nothing tracked but base-branch)"
  fi
  # (b) base-branch tracking
  if git -C "$MAIN_ROOT" ls-files .release-planning/ | grep -qx '\.release-planning/base-branch'; then
    echo "✓ base-branch tracked"
  else
    echo "⚠ base-branch NOT tracked → git add -f .release-planning/base-branch  (see /release:session base)"
  fi
  # (c) drift: sessions behind base
  echo "— drift (sessions behind base):"
  git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while read -r wt; do
    case "$wt" in *"/sessions/"*) ;; *) continue;; esac
    lbl="$(sed -n 's/^label: //p' "$wt/.release-planning/.session" 2>/dev/null)"; [ -n "$lbl" ] || lbl="$(basename "$wt")"
    br="session/$lbl"; git show-ref --verify --quiet "refs/heads/$br" || continue
    behind="$(git rev-list --left-right --count "$BASE...$br" 2>/dev/null | awk '{print $1}')"
    [ "${behind:-0}" -gt 0 ] && echo "  ⚠ $lbl: $behind behind → /release:session sync $lbl (inside the worktree)" \
                             || echo "  ✓ $lbl: up to date"
  done
}
```

---

## `cleanup` — remove merged leftovers

Removes worktree + branch for any session already fully merged into base (ancestor check). Merged
sessions that are still dirty are skipped (manual review). Reliable companion to `finish` for the
`--pr` path (where the GitHub merge leaves a local worktree+branch behind).

```bash
cmd_cleanup() {
  echo "━━━ cleanup (remove sessions already merged into $BASE) ━━━"
  cd "$MAIN_ROOT" || true
  git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while read -r wt; do
    case "$wt" in *"/sessions/"*) ;; *) continue;; esac
    lbl="$(sed -n 's/^label: //p' "$wt/.release-planning/.session" 2>/dev/null)"; [ -n "$lbl" ] || lbl="$(basename "$wt")"
    br="session/$lbl"; git show-ref --verify --quiet "refs/heads/$br" || continue
    if git merge-base --is-ancestor "$br" "$BASE" 2>/dev/null; then
      if [ -n "$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        echo "  $lbl: merged but DIRTY — skipped (review manually)"; continue; fi
      # -D (not -d): the ancestor check above is the real merged-into-BASE gate; -d would wrongly refuse
      # when MAIN_ROOT's HEAD (e.g. main) isn't the base (e.g. dev). Same reasoning as finish's cleanup.
      git -C "$MAIN_ROOT" worktree remove --force "$wt" && git -C "$MAIN_ROOT" branch -D "$br" \
        && echo "  ✓ $lbl: worktree + branch removed (merged)"
    else
      echo "  $lbl: not yet merged — kept"
    fi
  done
  git -C "$MAIN_ROOT" worktree prune
}
```

---

## `abort <label>`

Destructive. Confirm via `AskUserQuestion` ("discard worktree + branch `session/<label>`? unmerged
commits are lost"). Then `cd "$MAIN_ROOT"`, `git -C "$MAIN_ROOT" worktree remove --force "$WT_DIR"` +
`git -C "$MAIN_ROOT" branch -D "$BRANCH"` + `git -C "$MAIN_ROOT" worktree prune`. (Same cwd-drift
discipline as `finish` — never remove the worktree the shell is standing in without `cd`-ing out first.)

---

## How skills behave inside a session

A session worktree carries `.release-planning/.session`. Skills detect it and commit **in place** on
the session branch — they do not nest another worktree:

- **`/release:execute`** → sees `.session` ⇒ runs as if `--no-branch` (commits to the current
  `session/<label>` branch). Its internal wave parallelism (disjoint-file sub-worktrees) still
  applies and cherry-picks back to the session branch.
- **`/release:quick`, `/release:fast`** → commit in place (already do).
- **`/release:plan`, `/release:spec`, …** → write phase artifacts under `.release-planning/phases/`.
  These are committed to the session branch **as you work**, but `sync`/`finish` untrack them so they
  never reach the base merge or a PR — the integration is code-only by construction.
- **`/release:auto`** → routes normally; the routed skill inherits the session.

No active session (no `.session` marker) ⇒ skills behave exactly as before, on whatever branch the
checkout is on. There is no separate "legacy mode" to reason about — a lone checkout is just a
session of one.

## Conflict surface (be honest about it)

Disjoint domains rarely collide on **app code** (Django keeps migrations per-app: `financeiro/migrations/`
≠ `rh/migrations/` — no graph collision unless two sessions touch the *same* app). The collisions
that *will* happen are in **shared project wiring**, and are small + known:

| File | Why | Mitigation |
|---|---|---|
| `settings.INSTALLED_APPS` | each domain registers its app | pre-register all app stubs on base before fan-out |
| root `urls.py` | each domain `include()`s its urls | pre-wire includes on base, or auto-discover |
| `requirements*.txt` | parallel dep adds | add shared deps on base first |
| `ROADMAP.md` | parallel phase appends | give each domain a phase-number range |

When such a collision *does* happen, `finish`'s sync step surfaces it **in the session** as a code
conflict and STOPS — the session author resolves it with full domain context, commits, and re-runs.
Base is never touched until the merge is clean.

`STATE.md`, `.session`, and `active-workstream` are **git-ignored / local per checkout** (see
`start` step 6) — they never merge, so they never conflict. **Planning artifacts under `phases/`** are
stripped from the index by `sync`/`finish` (`untrack_planning`), so even a planning *modify/delete*
collision is auto-resolved by untracking — only a genuine **code** conflict ever stops the operation.

## Rules

- **Base is sacred.** A CODE conflict ⇒ surfaced in the session, never in base; base stays
  byte-identical until a clean merge. Never auto-resolve code, never force-push base.
- **Conflicts surface in the session, not the base checkout.** `finish` merges base→session first
  (the author has the context); the session→base merge is then a conflict-free fast-forward.
- **Planning is local-only.** `sync`/`finish` untrack `.release-planning/` (keeping only `base-branch`)
  so every merge/PR is code-only. Planning conflicts are auto-resolved by untracking.
- **One finish per base at a time** (`merge-<token>.lock`, slashes in the base name flattened to `_`).
  The lock is taken **before** sync and held through the merge, so fan-in is atomic — no window where
  base advances between a session's sync and its merge. A `kill -9`'d finish leaves a stale lock; the
  next finish reclaims it automatically if the holder PID is dead (else manually `rm` the lockfile).
- **A branch lives in one worktree.** `finish` merges inside base's own checkout (or a throwaway one
  when base isn't checked out). Base = integration point: don't hand-edit there — you can't advance a
  checked-out branch without its working tree moving under you.
- **Never delete the cwd you're standing in.** `finish`/`abort`/`cleanup` `cd "$MAIN_ROOT"` before
  removing a worktree, and run removals via `git -C "$MAIN_ROOT"` — so cleanup can't crash on its own cwd.
- **finish/abort discard uncommitted work.** The session must be committed (sync gate); `worktree remove
  --force` then deletes the worktree, including any **untracked** WIP. Commit anything you want to keep first.
- **Integrate only via `finish` / `finish --pr`.** Planning is stripped at sync/finish time, so a *manual*
  `git push` of a `session/<label>` branch WOULD carry the planning commits — always fold in through finish.
- **finish refuses to delete base-tracked planning.** If base tracks anything under `.release-planning/`
  beyond `base-branch` (a regression `doctor` flags), finish hard-stops rather than silently dropping it.
- **No nested session worktrees.** Skills inside a session commit in place.
