---
name: land
description: >
  Land a held / conflicted / --no-merge unit of work back onto base — the retry path for the auto
  merge-back that /release:quick and /release:execute perform on green. Use when a quick or a phase was
  HELD (the base checkout was dirty at land time, so it was never clobbered) or you ran with --no-merge,
  and now you want it on your trunk. Serialized + conflict-safe via the shared land_branch engine.
  Trigger words: "land", "aterrissa", "merge back the quick/phase", "finish the held merge".
---

## Codex runtime contract (generated; overrides incompatible source directives)

This skill is the Codex edition of release-sdk. The source workflow below is
kept for behavioral parity, but this contract has precedence whenever the
source mentions Claude Code primitives.

### Isolation

- Never create, edit, delete, or inspect runtime state under `~/.claude`,
  `.claude/`, `.claude-plugin/`, `.claude-plugin-cache/`, or `CLAUDE.md`.
- Release planning artifacts remain under `.release-planning/`. Durable Codex
  project guidance belongs in `AGENTS.md` only when the workflow explicitly
  needs to add it.
- Resolve `RELEASE_PLUGIN_ROOT` as the directory two levels above this
  `SKILL.md`. Resolve `RELEASE_PLUGIN_DATA` from `PLUGIN_DATA` when supplied;
  otherwise use `${CODEX_HOME:-$HOME/.codex}/release-sdk`.

### Tools

- Treat `Read`, `Write`, `Edit`, `Bash`, `Grep`, and `Glob` in the source as
  conceptual operations. Use the Codex tools currently available: targeted
  file reads, `apply_patch` for edits, `exec_command` for commands, and `rg`
  or `rg --files` for search.
- A source reference to `AskUserQuestion` means: use the structured user-input
  tool when it is available to the parent agent. A subagent must instead
  return `USER_INPUT_REQUIRED` with the exact question and 2-3 choices so the
  parent can ask it. If no structured input tool is available, ask one concise
  question in the parent task.
- A source reference to a `Skill` tool means to run the installed
  `release:<skill-name>` skill. If there is no callable skill tool, delegate to
  a `default` subagent with a task that explicitly names that installed skill,
  pass the original arguments unchanged, wait for it, and surface its result.

### Subagents

- Source agent names `release:<name>` are mapped in this generated edition to
  Codex custom agents named `release-<name>`.
- Spawn agents only through Codex collaboration tools. Do not emulate a
  subagent with a shell command and do not use a nonexistent `Task` or `Agent`
  tool.
- Prefer the named `release-<name>` agent when it is available. These agents
  are installed by the `release:setup-codex` skill and become available in a
  new task.
- If a named agent is not available, use `explorer` for read-only codebase
  research, `worker` for implementation or file-producing work, and `default`
  for orchestration or judgment. Give the fallback agent the absolute path to
  `agents/release-<name>.toml` under `RELEASE_PLUGIN_ROOT` and require it to
  read and follow the `developer_instructions` before working.
- For write tasks, assign explicit file ownership and tell every worker that
  other agents may be editing the repository; it must preserve and integrate
  others' changes. Parallelize only independent scopes and respect the current
  session's concurrency limit.
- Wait for required agents, collect their final results, and keep completion
  judgment in the parent/orchestrator. A worker never declares the overall
  workflow complete.

### Models and reasoning

- Ignore source instructions that pin or derive Claude model tiers such as
  Fable, Opus, Sonnet, or Haiku. Do not pass an explicit model or reasoning
  effort unless the user requested one. Codex custom agents inherit the
  parent/session settings by default.
- Preserve maker-versus-checker independence by using distinct agent turns,
  not by assuming a particular vendor model hierarchy.

### Invocation vocabulary

- `/release:<name>` in the source is a workflow label retained for
  compatibility. In Codex Desktop the user selects the `release` plugin or its
  `release:<name>` skill from the composer.
- `claude` CLI launch examples map to `codex` in this generated edition.

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. This skill spawns no agents; it runs the shared
merge-back engine directly.

---

# /release:land — finish a deferred merge-back

`/release:quick` and `/release:execute` auto-land on green. When the base checkout was **dirty**, the
land is **held** (your uncommitted work is never clobbered); with `--no-merge` it is skipped on
purpose. `/release:land` is the retry: it lands the unit onto base through the SAME serialized,
conflict-safe `land_branch` engine that powers `/release:session finish`. A dirty base is still never
clobbered — land only proceeds when your trunk checkout is clean.

## Usage

```
/release:land                 # list landable units, pick one
/release:land <label>         # land the unit whose branch matches <label>  (quick/<label>, feat/<label>, session/<label>)
/release:land --all           # land every ready unit, serialized on the per-base lock
```

## Flow

### Step 1 — resolve base + enumerate landable units

```bash
MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"
BASE="$(git -C "$MAIN_ROOT" rev-parse --abbrev-ref HEAD)"   # land target = the branch you're testing on (main checkout's current branch)

# A landable unit = a worktree whose branch is quick/* | feat/* | session/* and is NOT yet an ancestor of base.
git worktree list --porcelain | awk '
  /^worktree /{w=substr($0,10)}
  /^branch /{b=$2; sub("refs/heads/","",b); if (b ~ /^(quick|feat|session)\//) print w "\t" b }
' | while IFS="$(printf '\t')" read -r wt br; do
  git -C "$MAIN_ROOT" merge-base --is-ancestor "$br" "$BASE" 2>/dev/null && continue   # already landed
  printf '%s\t%s\n' "$br" "$wt"   # branch <TAB> worktree
done
```

### Step 2 — pick the unit

- `<label>` given → select the unit whose branch is `quick/<label>`, `feat/<label>`, `session/<label>`,
  or whose branch basename matches `<label>`. Ambiguous or no match → list the units and ask via `AskUserQuestion`.
- no arg → if exactly one landable unit exists, use it; otherwise list them and ask (`AskUserQuestion`).
- `--all` → iterate every landable unit (Step 3 in a loop); the per-base lock serializes them safely.

### Step 3 — land via the shared engine

```bash
RELEASE_LIB="${RELEASE_PLUGIN_ROOT:+$RELEASE_PLUGIN_ROOT/bin/release-merge-lib.sh}"
[ -n "$RELEASE_LIB" ] && [ -f "$RELEASE_LIB" ] || RELEASE_LIB="$(find "${CODEX_HOME:-$HOME/.codex}" -name release-merge-lib.sh -path '*/bin/*' 2>/dev/null | head -1)"
[ -f "$RELEASE_LIB" ] || { echo "ABORT: release-merge-lib.sh not found (set RELEASE_PLUGIN_ROOT)."; exit 1; }
. "$RELEASE_LIB"

# BR + WT come from the unit picked in Step 2 (for --all, loop over each pair)
RESULT="$(land_branch "$BR" "$WT" "$BASE" | tail -1)"
cd "$MAIN_ROOT"   # land may remove $WT from under us
case "$RESULT" in
  RESULT=merged)        echo "✓ $BR landed on $BASE (live) — hot-reload has it if your app runs on $BASE." ;;
  RESULT=held-dirty)    echo "⏸ $BASE still has uncommitted work. Commit/stash on $BASE, then re-run /release:land." ;;
  RESULT=conflict)      echo "✗ code conflict vs $BASE. Resolve in $WT, commit, then re-run /release:land." ;;
  RESULT=refused)       echo "✗ merge refused (untracked-file collision in $WT). Clean it, then re-run." ;;
  RESULT=locked)        echo "⏳ another land/finish is merging into $BASE. Retry in a moment." ;;
  RESULT=planningblock) echo "✗ base '$BASE' tracks planning files a land would delete. Untrack on base first." ;;
  RESULT=baseadvanced)  echo "✗ $BASE advanced under us — aborted, base byte-identical. Re-run /release:land." ;;
  RESULT=badbase)       echo "✗ base resolved to a session branch. Pin one: /release:session base <branch>." ;;
  *)                    echo "✗ land failed ($RESULT). Unit kept at $WT." ;;
esac
```

## Notes

- **Same engine everywhere.** `session finish`, `quick`, `execute` auto-land, and `land` all call
  `land_branch` (`bin/release-merge-lib.sh`, contract-tested by `bin/test-session-merge.sh`). One
  per-base lock serializes every merge-back, so nothing corrupts your trunk.
- **Nothing is lost.** A held unit's branch + worktree are preserved until it lands.
- **`--all` is fail-soft.** A unit that conflicts or holds is left for you; the rest still land.

---

_Retry path for the deferred auto-merge. Serialized, conflict-safe, never clobbers a dirty trunk._
