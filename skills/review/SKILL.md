---
name: review
description: Diff-scoped adversarial review using one unified reviewer by default; strict mode may split truly independent high-risk surfaces.
---

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
2. Infer `django`, `react`, `mobile`, or `fullstack` from in-scope files and call one `release:code-reviewer` with the file paths, stack, diff/range, and locks. The unified reviewer owns cross-file and API/UI seam checks; do not send the same diff to multiple reviewers.
3. Split only with `--strict` on a C3/C4 change whose independent, disjoint surfaces materially benefit from specialists. Give each reviewer non-overlapping paths and merge deduplicated results once.
4. Write `.release-planning/review/REVIEW.md` (or `--review-path`) containing blockers and warnings with exact `file:line`, impact, evidence, and smallest fix. A clean review says which surfaces were inspected.
5. With `--fix`, send only accepted finding IDs and their paths to one `release:code-fixer`. Re-run focused checks for touched behavior, then `run_gate_cached "$repo" full`; review only the resulting delta once. Never restart the entire review fleet.

Depth is evidence-driven: pattern scan for small C0/C1 diffs, per-file reasoning for C2, and cross-boundary tracing for C3/C4 or `--strict`. Do not flag style preferences, speculative performance work, or missing abstractions without demonstrated impact.
