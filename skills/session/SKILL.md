---
name: session
description: >
  Worktree-native parallel sessions (v0.15.0). Spin up N isolated Claude Code sessions off one
  base branch — each in its own git worktree on a `session/<label>` branch — run any skill
  (quick / plan / execute / auto …) in each, then merge every session back to base with a
  SERIALIZED, conflict-safe merge (base is never left dirty; conflicts STOP, never auto-resolve).
  Replaces the sustained-domain `workstreams` model. Use when: working multiple independent
  domains (financeiro / operacional / RH …) in parallel and folding them into one trunk.
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
/release:session finish [<label>] [--keep] [--pr]  # serialized conflict-safe merge back to base
/release:session list                              # all active sessions: base, ahead/behind, last commit
/release:session abort <label>                     # discard worktree + branch (destructive, confirmed)
/release:session base [<branch>]                   # show or set the default base branch
```

`<label>` matches `^[a-z][a-z0-9-]{1,39}$`. Run `finish` from inside a session worktree to omit `<label>`.

---

## Base branch

The trunk every session forks from and merges into (the user's "branch principal" — e.g. `dev`).

```bash
# resolution: --base flag  >  .release-planning/base-branch file  >  current branch
BASE="${BASE_FLAG:-$(cat .release-planning/base-branch 2>/dev/null || git rev-parse --abbrev-ref HEAD)}"
```

`/release:session base dev` writes `.release-planning/base-branch` (committed — it's a project-wide
decision, shared across checkouts).

---

## `start <label>`

```bash
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
# 5. session marker (local, gitignored) so skills know they're in a session → commit in-place
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

## `finish [<label>]` — serialized, conflict-safe merge-back

The load-bearing operation. **Invariants:** base is never left dirty; a conflict STOPS the merge and
is never auto-resolved; only one finish touches base at a time.

```bash
ROOT=$(git rev-parse --show-toplevel)
# label from arg, else from the .session marker in the current worktree
label="${1:-$(sed -n 's/^label: //p' .release-planning/.session 2>/dev/null)}"
[ -n "$label" ] || { echo "ABORT: no label (run inside a session worktree or pass one)."; exit 1; }
BRANCH="session/$label"
WT_DIR="$ROOT/../release-worktrees/sessions/$label"
BASE="$(sed -n 's/^base: //p' "$WT_DIR/.release-planning/.session" 2>/dev/null)"
BASE="${BASE:-$(cat .release-planning/base-branch 2>/dev/null)}"
LOCKDIR="$ROOT/../release-worktrees/.locks"; mkdir -p "$LOCKDIR"
MERGE_LOCK="$LOCKDIR/merge-$BASE.lock"

# 1. session work must be committed
[ -z "$(git -C "$WT_DIR" status --porcelain)" ] || { echo "ABORT: session '$label' has uncommitted changes. Commit them first."; exit 1; }

# 2. serialize fan-in: one finish per base at a time
if ! ( set -o noclobber; printf '%s\n' "$label $$" > "$MERGE_LOCK" ) 2>/dev/null; then
  echo "ABORT: another session is merging into '$BASE' right now. Retry in a moment."; exit 1
fi
trap 'rm -f "$MERGE_LOCK"' EXIT

# 3. locate the worktree that has BASE checked out (a branch lives in exactly ONE worktree)
BASE_WT="$(git worktree list --porcelain | awk -v b="refs/heads/$BASE" '
  /^worktree /{wt=substr($0,10)} /^branch /{if($2==b)print wt}')"
TEMP_WT=""
if [ -z "$BASE_WT" ]; then
  # base not checked out anywhere → check it out in a throwaway worktree to merge into
  TEMP_WT="$ROOT/../release-worktrees/.merge-$BASE"; git worktree add "$TEMP_WT" "$BASE"; BASE_WT="$TEMP_WT"
elif [ -n "$(git -C "$BASE_WT" status --porcelain)" ]; then
  echo "ABORT: base checkout ($BASE_WT) is dirty. Commit/stash there first."; rm -f "$MERGE_LOCK"; exit 1
fi

# 4. merge into base; --no-ff keeps the session boundary. CONFLICT ⇒ abort merge, base stays clean.
if git -C "$BASE_WT" merge --no-ff "$BRANCH" -m "merge(session): $label into $BASE"; then
  N=$(git -C "$BASE_WT" rev-list --count "$BASE@{1}..$BASE")
  echo "✓ merged session/$label into $BASE ($N commits)"
  git worktree remove --force "$WT_DIR"
  [ "${KEEP:-false}" = "true" ] || git branch -d "$BRANCH"
else
  git -C "$BASE_WT" merge --abort
  echo "✗ CONFLICT merging session/$label into $BASE — base left untouched."
  echo "  Resolve by rebasing the session on base, then retry:"
  echo "    git -C $WT_DIR rebase $BASE     # fix conflicts IN the session worktree"
  echo "    /release:session finish $label"
  CONFLICT=1
fi

[ -n "$TEMP_WT" ] && git worktree remove --force "$TEMP_WT"
git worktree prune; rm -f "$MERGE_LOCK"
[ -z "${CONFLICT:-}" ]
```

`--pr` instead of a local merge: push `session/<label>` and open a PR into `$BASE` via `gh`
(review-gated integration) rather than fast local merge. Use for higher-stakes domains.

**Why rebase-in-session on conflict (not auto-resolve):** the session author has the context to
resolve their own domain's collision; base must never contain a half-merged state. The merge is
`--abort`ed so base is byte-identical to before. Re-running `finish` after the rebase merges clean.

---

## `list`

```
━━━ Sessions ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LABEL         BASE   AHEAD  BEHIND  WORKTREE                         LAST COMMIT
financeiro    dev    4      0       …/sessions/financeiro           a1b2c3 feat(financeiro): refund flow
rh            dev    2      1       …/sessions/rh                    d4e5f6 feat(rh): payroll model
2 active session(s) on base 'dev'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

`behind > 0` ⇒ base moved since the session forked; a `finish` may conflict — rebase first.
Built from `git worktree list --porcelain` + `git rev-list --left-right --count $BASE...session/<label>`.

## `abort <label>`

Destructive. Confirm via `AskUserQuestion` ("discard worktree + branch `session/<label>`? unmerged
commits are lost"). Then `git worktree remove --force "$WT_DIR"` + `git branch -D "$BRANCH"` +
`git worktree prune`.

---

## How skills behave inside a session

A session worktree carries `.release-planning/.session`. Skills detect it and commit **in place** on
the session branch — they do not nest another worktree:

- **`/release:execute`** → sees `.session` ⇒ runs as if `--no-branch` (commits to the current
  `session/<label>` branch). Its internal wave parallelism (disjoint-file sub-worktrees) still
  applies and cherry-picks back to the session branch.
- **`/release:quick`, `/release:fast`** → commit in place (already do).
- **`/release:plan`, `/release:spec`, …** → write phase artifacts under `.release-planning/phases/`,
  committed to the session branch.
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

`STATE.md`, `.session`, and `active-workstream` are **git-ignored / local per checkout** (see
`start` step 6) — they never merge, so they never conflict. The committed source of truth is the
per-phase artifacts under `phases/`, which are naturally disjoint across domains.

## Rules

- **Base is sacred during finish.** Conflict ⇒ `merge --abort` ⇒ base byte-identical to before. Never
  auto-resolve, never force-push base.
- **One finish per base at a time** (`merge-<base>.lock`). Fan-in is serialized.
- **A branch lives in one worktree.** `finish` merges inside base's own checkout (or a throwaway one).
- **No nested session worktrees.** Skills inside a session commit in place.
