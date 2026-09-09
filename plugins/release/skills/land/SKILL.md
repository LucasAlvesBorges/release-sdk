---
name: land
description: >
  Land a held / conflicted / --no-merge unit of work back onto base — the retry path for the auto
  merge-back that /release:quick and /release:execute perform on green — and the one place that
  pushes, builds and coordinates a paired cross-repo phase. Use when a quick or a phase was HELD
  (the base checkout was dirty at land time) or you ran with --no-merge; add --push to publish,
  --build to trigger the app's release build after the push, --cross to land the paired phase in
  the other repo first. Trigger words: "land", "aterrissa", "merge back", "push cross repo",
  "builda ios prod com autosubmit", "finish the held merge".
---

## Codex runtime contract

This generated Codex skill preserves the source workflow with these overrides:

- Use current Codex tools: targeted reads, `rg`, `apply_patch`, and shell commands. Never look for
  Claude-only tool names or runtime state (`~/.claude`, `.claude*`, `CLAUDE.md`). Release artifacts
  stay in `.release-planning/`; project guidance comes from the applicable `AGENTS.md` chain.
- Before a write, a root `AGENTS.md` must exist. The hook returns `AGENTS_MD_REQUIRED`; in bootstrap
  mode only `release-agents-md-builder` may draft it, after which the user reruns the task.
- Score C0-C4 and apply risk floors before spawning. Default is no child. Spawn only when a bounded
  independent/specialist/noisy subtask avoids more context than it costs. C0/C1 stays inline; C2 uses
  at most one normal worker/planner; C3/C4 may use the strict fleet with disjoint ownership.
- Map source `release:<name>` agents to Codex `release-<name>` custom agents. Pass paths and task
  deltas, never the transcript, copied files, full logs, or `AGENTS.md` contents. Writers preserve
  concurrent work and own non-overlapping paths.
- Custom agents already pin their model/effort. Ignore Claude model names and `CLAUDE_EFFORT`; do not
  increase effort unless the C3/C4 risk actually requires it.
- A child returns compact `SubagentResultV1`; the parent decides completion. User input stays in the
  parent. Retry once at most, then narrow/stop instead of grinding.

`/release:<name>` is the source workflow label; in Codex select the corresponding release skill.

# /release:land — finish a deferred merge-back, then publish

`/release:quick` and `/release:execute` auto-land on green. When the base checkout was **dirty**, the
land is **held** (your uncommitted work is never clobbered); with `--no-merge` it is skipped on
purpose. `/release:land` is the retry, through the SAME serialized, conflict-safe `land_branch`
engine. A dirty base is still never clobbered. Since v0.27.0 it is also the publish step: push,
release build and paired-repo ordering live here, never as ad-hoc shell in a chat.

## Usage

```text
/release:land                       # list landable units, pick one
/release:land <label>               # land the unit whose branch matches <label>  (quick/<label>, feat/<label>)
/release:land --all                 # land every ready unit, serialized on the per-base lock
/release:land [<label>] --push      # push base to origin after landing (push == deploy in most repos)
/release:land [<label>] --build     # after --push: run the project's release build (PROJECT.md build_command)
/release:land <NN> --cross          # paired phase: land+push the OTHER repo first, wait for its deploy_check, then this one
/release:land --push --build        # nothing to land, just publish base + build (the "pusha e builda" ritual)
```

## Flow

### Step 0 — libs, base

```bash
find_lib(){ local p="${RELEASE_PLUGIN_ROOT:+$RELEASE_PLUGIN_ROOT/bin/$1}"; [ -n "$p" ]&&[ -f "$p" ]&&{ printf %s "$p"; return; }; find "${CODEX_HOME:-$HOME/.codex}" -name "$1" -path '*/bin/*' 2>/dev/null|head -1; }
. "$(find_lib release-merge-lib.sh)"
MAIN_ROOT="$(release_main_root)"
BASE="$(git -C "$MAIN_ROOT" rev-parse --abbrev-ref HEAD)"   # land target = the branch you're testing on
```

### Step 1 — enumerate landable units

```bash
# A landable unit = a worktree whose branch is quick/* | feat/* and is NOT yet an ancestor of base.
git worktree list --porcelain | awk '
  /^worktree /{w=substr($0,10)}
  /^branch /{b=$2; sub("refs/heads/","",b); if (b ~ /^(quick|feat)\//) print w "\t" b }
' | while IFS="$(printf '\t')" read -r wt br; do
  git -C "$MAIN_ROOT" merge-base --is-ancestor "$br" "$BASE" 2>/dev/null && continue   # already landed
  printf '%s\t%s\n' "$br" "$wt"
done
```

### Step 2 — pick the unit

- `<label>` given → the unit whose branch is `quick/<label>`, `feat/<label>`, or whose branch basename
  matches `<label>`. A bare phase number `NN` matches `feat/NN-*`. Ambiguous or no match → list and ask
  via `AskUserQuestion`.
- no arg → exactly one landable unit → use it; otherwise list and ask. With `--push`/`--build` and
  nothing to land, skip to Step 4.
- `--all` → iterate every landable unit; the per-base lock serializes them safely.

### Step 3 — land via the shared engine

```bash
RESULT="$(land_branch "$BR" "$WT" "$BASE" | tail -1)"
cd "$MAIN_ROOT"   # land may remove $WT from under us
rm -f "$MAIN_ROOT/.release-planning/.unit-active" "$MAIN_ROOT/.release-planning/.allow-prod"
```

Any result other than `RESULT=merged` ends here: print `land_report "$RESULT" "$BASE" "$MAIN_ROOT" skipped "$BR"`
and stop. Never push or build on top of a held/conflicted land.

### Step 4 — push (only after merged, or with nothing to land)

```bash
POLICY="$(release_push_policy "$MAIN_ROOT")"        # never | ask | auto
# --push  ⇒ push. policy auto ⇒ push. policy ask ⇒ AskUserQuestion once. never ⇒ PUSH_STATE=policy-never
PUSH_STATE="$(land_push "$MAIN_ROOT" "$BASE" | sed 's/^PUSH=//')"   # pushed | failed | no-remote
```

### Step 5 — `--build` (after a successful push only)

```bash
BUILD="$(release_project_setting "$MAIN_ROOT" build_command)"
[ -z "$BUILD" ] && [ -f "$MAIN_ROOT/eas.json" ] && BUILD='eas build --platform ios --profile production --auto-submit --non-interactive'
```

Run `BUILD` from `MAIN_ROOT` on the pushed tip. It is the user's ritual, so it is allowed here even
though the prod guard blocks `eas … --auto-submit` inside a unit. Report the build id/URL. If there is
no build command and no `eas.json`, say so and stop; never invent one.

### Step 6 — `--cross` (paired phase)

Read `paired:` from `{NN}-SPEC.md` (`<abs-repo-path>:<NN>`; written by `/release:spec --paired`).
Order is always **provider first**: the repo whose stack is `django`/backend lands and pushes first,
then its `deploy_check` (PROJECT.md, e.g. `gh run watch --exit-status`) must succeed within 15 min,
then the consumer repo (React / React Native) lands, pushes and — with `--build` — builds. Run the
same Steps 1-5 inside the paired repo with `git -C <path>` / `cd <path>`; each repo keeps its own
`.release-planning/`. If the paired phase is not landable yet, stop before touching this repo and
say which phase is missing.

## Report — the fixed last line

Every invocation ends with exactly one `land_report` line per repo touched:

```bash
land_report "$RESULT" "$BASE" "$MAIN_ROOT" "$PUSH_STATE" "$BR"
```

`PUSH_STATE` ∈ `pushed | failed | no-remote | policy-never | policy-ask | skipped`. Add one extra line
for a build (`BUILD: <id/url>`) or a deploy check (`DEPLOY: ok|failed|timeout`). Nothing else after it.

## Notes

- **Same engine everywhere.** `quick`, `execute` auto-land and `land` all call `land_branch`
  (`bin/release-merge-lib.sh`, contract-tested by `bin/test-merge-lib.sh`). One per-base lock
  serializes every merge-back.
- **Nothing is lost.** A held unit's branch + worktree are preserved until it lands; `/release:gc`
  prunes only after the branch is on base and the tree is clean.
- **`--all` is fail-soft.** A unit that conflicts or holds is left for you; the rest still land.
- **Push is the deploy button.** Default policy is `never`; set `push_after_land: auto|ask` in
  PROJECT.md → Delivery settings when a repo has no auto-deploy on push.
