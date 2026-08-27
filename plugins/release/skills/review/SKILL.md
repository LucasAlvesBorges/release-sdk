---
name: review
description: Diff-scoped adversarial review using one unified reviewer by default; strict mode may split truly independent high-risk surfaces.
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

# `/release:review`

Review a bounded diff once and report only merge-relevant defects.

## Usage

```text
/release:review [path]
/release:review --diff main..HEAD
/release:review --strict
/release:review --fix
```

## Flow

1. Resolve one canonical file list from the path/diff (default: merge base to HEAD). Exclude generated artifacts, lock files, planning output, dependencies, coverage, and unrelated files. Read active project locks once.
2. Infer `django`, `react`, `mobile`, or `fullstack` from in-scope files and call one `release-code-reviewer` with the file paths, stack, diff/range, and locks. The unified reviewer owns cross-file and API/UI seam checks; do not send the same diff to multiple reviewers.
3. Split only with `--strict` on a C3/C4 change whose independent, disjoint surfaces materially benefit from specialists. Give each reviewer non-overlapping paths and merge deduplicated results once.
4. Write `.release-planning/review/REVIEW.md` (or `--review-path`) containing blockers and warnings with exact `file:line`, impact, evidence, and smallest fix. A clean review says which surfaces were inspected.
5. With `--fix`, send only accepted finding IDs and their paths to one `release-code-fixer`. Re-run focused checks for touched behavior, then `run_gate_cached "$repo" full`; review only the resulting delta once. Never restart the entire review fleet.

Depth is evidence-driven: pattern scan for small C0/C1 diffs, per-file reasoning for C2, and cross-boundary tracing for C3/C4 or `--strict`. Do not flag style preferences, speculative performance work, or missing abstractions without demonstrated impact.
