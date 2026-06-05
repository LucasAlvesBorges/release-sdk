---
name: audit-fix
description: >
  Autonomous audit-to-fix pipeline. Runs all relevant auditors in parallel, classifies findings,
  dispatches release-code-fixer for AUTO_FIXABLE items, atomic-commits each fix, loops until clean
  or --max-iters. Read-only on findings; only the code-fixer writes code.
  Use when: phase is verified but quality auditors flag accumulated debt worth burning down.
---

# /release:audit-fix — Autonomous Audit-to-Fix Pipeline

Spawns auditors in parallel, classifies their findings, dispatches `release:release-code-fixer` for
items safe to auto-fix, commits each fix atomically, then re-runs the auditors. Loops until
findings hit zero or `--max-iters` is hit.

Use after a phase reaches stage `verified` to burn down accumulated lint / security / test /
validation debt without orchestrating each auditor by hand.

## When NOT to use

- Phase still at stage `planning` / `executing` — fix workflow gaps with `/release:execute --gaps`.
- Phase blocked on a HIGH/CRITICAL business-logic finding — that's `NEEDS_HUMAN`, not audit-fix.
- You want a one-shot review — use `/release:review` (no fix loop).
- You want a UAT pass — use `/release:verify-work`.

## Usage

```
/release:audit-fix                           # run all auditors, fix AUTO_FIXABLE, loop until clean
/release:audit-fix 01                        # constrain to phase 01 files
/release:audit-fix --max-iters 3             # cap loop iterations (default: 3)
/release:audit-fix --severity HIGH           # only AUTO_FIXABLE findings at HIGH+ severity
/release:audit-fix --dry-run                 # classify & report, do not dispatch fixer
/release:audit-fix --no-ui                   # skip release:react-ui-auditor even if frontend in scope
```

## Pre-checks (hard requirements)

1. Working tree clean — abort if `git diff --quiet` fails. Audit-fix commits per fix; dirty
   tree mixes user work with auto-fixes.
2. Current phase at stage `verified` (or later) per STATE.md — abort with guidance otherwise.
   Override with `--force` only if you understand you're auditing in-progress code.
3. `.release-planning/PROJECT.md` exists — needed for stack dispatch (`django` | `react` |
   `fullstack`).

## Auditor roster

Per iteration, dispatch in parallel via the Agent tool. Auditors are read-only; they emit
findings reports only.

| Agent | Scope | Severity outputs |
|---|---|---|
| `release:release-code-reviewer` | code quality, dead code, naming, complexity | CRITICAL / HIGH / MEDIUM / LOW |
| `release:release-security-auditor` | 9-category security matrix (stack-dispatched) | CRITICAL / HIGH / MEDIUM / LOW |
| `release:release-test-auditor` | coverage gaps, flaky tests, weak asserts | HIGH / MEDIUM / LOW |
| `release:release-nyquist-auditor` | validation surface coverage (Q1-Q7 / RC1-RC7) | HIGH / MEDIUM / LOW |
| `release:react-ui-auditor` | 6-pillar visual audit (skipped if no frontend in scope or `--no-ui`) | HIGH / MEDIUM / LOW |

Stack dispatch (django / react / fullstack) is resolved from `.release-planning/PROJECT.md`
and per-phase `{NN}-PLAN.md` frontmatter, same as every other release-* skill.

## Classification rubric

Each finding gets exactly one of:

| Class | Meaning | Action |
|---|---|---|
| `AUTO_FIXABLE` | Mechanical fix: lint, formatting, missing type hint, missing `read_only_fields`, missing `aria-label`, dead import, weak assert, missing `select_related`. | Dispatch `release:release-code-fixer`. |
| `NEEDS_HUMAN` | Business-logic / arch / threat-model / UX decision. | Log only. User must triage. |
| `SKIPPED` | Below `--severity` threshold OR filed by an auditor that's out of scope. | Log only. |

Classification rules (apply in order):
1. Severity below `--severity` flag → `SKIPPED`.
2. Auditor explicitly tagged the finding `human_required: true` → `NEEDS_HUMAN`.
3. Finding category in auto-fix allowlist (see below) → `AUTO_FIXABLE`.
4. Otherwise → `NEEDS_HUMAN`.

### Auto-fix allowlist

Backend (Django):
- `ruff` / `black` violations
- Missing `read_only_fields` on a serializer that already uses `fields = [...]` allowlist
- Missing `select_related` / `prefetch_related` on a queryset flagged by N+1 grep
- Missing `Meta.ordering`
- Test asserts on count when a stronger field-level assert is available from the model

Frontend (React/TSX):
- `eslint` / `prettier` violations
- Missing `aria-label` / `aria-describedby` on flagged interactive elements
- Missing `React.memo` on flagged hot components
- Missing Zod schema on a form already wired to react-hook-form
- `console.log` left in committed code

Cross-cutting:
- Dead imports
- Unused variables
- Missing TODO ownership

Anything outside this list → `NEEDS_HUMAN` (e.g., changing a permission class, refactoring a
viewset, rewriting a state machine, adjusting the threat model).

## Execution loop

```
iter = 0
while iter < max_iters:
  iter += 1

  # 1. Audit (parallel)
  findings = parallel_dispatch([
    release:release-code-reviewer,
    release:release-security-auditor,    # stack-aware
    release:release-test-auditor,
    release:release-nyquist-auditor,
    release:react-ui-auditor,          # only if frontend in scope and not --no-ui
  ])

  # 2. Classify
  classified = [classify(f) for f in findings]
  auto = [f for f in classified if f.class == AUTO_FIXABLE]
  human = [f for f in classified if f.class == NEEDS_HUMAN]

  log_iteration(iter, findings, classified)

  # 3. Exit conditions
  if len(findings) == 0:
    verdict = CLEAN; break
  if len(auto) == 0:
    verdict = HUMAN_ONLY; break
  if dry_run:
    verdict = DRY_RUN; break

  # 4. Fix
  for finding in auto:
    spawn release:release-code-fixer(finding)
    # fixer commits atomically: fix(NN): <category> — <one-line summary>
    # if fixer reports cannot_fix → reclassify as NEEDS_HUMAN, continue

  # next iter re-audits to confirm fixes landed
```

After the loop, write the run log.

## Atomic commit shape

Each fix is one commit. Format:
```
fix({NN}): <category> — <one-line summary>

Auditor: release-{code-reviewer|security-auditor|test-auditor|nyquist-auditor|ui-auditor}
Finding: F-{NN}.{auditor}.{idx}
Class: AUTO_FIXABLE
Severity: {LOW|MEDIUM|HIGH|CRITICAL}
Evidence: {file}:{line}
```

The fixer must NOT batch multiple findings into one commit, even when touching the same file.
One finding → one commit. This keeps `/release:undo` per-fix surgical.

## Output

```
.release-planning/audit-fix-log.md
```

Appended (not overwritten) on each run. Each invocation gets a dated section.

```markdown
---
last_run_at: 2026-05-25T15:00:00Z
total_runs: 4
last_verdict: CLEAN
---

# Audit-Fix Log

## Run 2026-05-25T15:00:00Z (phase 01, --max-iters 3)

### Iteration 1
- Findings: 12 (4 CRITICAL, 3 HIGH, 5 MEDIUM)
- Classified: 7 AUTO_FIXABLE, 4 NEEDS_HUMAN, 1 SKIPPED
- Fixes applied: 7
  - fix(01): lint — ruff E501 in views.py (commit a1b2c3)
  - fix(01): n+1 — prefetch_related on InvoiceList (commit d4e5f6)
  - fix(01): aria — aria-label on icon button (commit g7h8i9)
  - ... (4 more)

### Iteration 2
- Findings: 4 (4 NEEDS_HUMAN from iter 1, unchanged)
- Classified: 0 AUTO_FIXABLE → exit (HUMAN_ONLY)

### Verdict: HUMAN_ONLY
- 7 fixes applied across 7 commits
- 4 findings still require human triage:
  - F-01.security-auditor.3 (HIGH): permission class on retrieve missing tenant guard
  - F-01.code-reviewer.7 (HIGH): InvoiceList viewset doing serializer work
  - F-01.test-auditor.2 (HIGH): no race-condition test on bulk-import
  - F-01.nyquist-auditor.1 (MEDIUM): Q5 coverage gap on concurrent edit

### Recommended next steps
1. Triage 4 NEEDS_HUMAN findings (see above).
2. `/release:plan 01 --gaps` if any require code changes.
3. Re-run `/release:audit-fix 01` after human fixes land.
```

## Constraints

- This skill is read-only on source; ONLY the `release:release-code-fixer` agent writes code.
- Never `git push`, never `gh pr ...`. Audit-fix lands local commits only.
- Never fixes a CRITICAL finding without explicit confirmation in the log of which rule
  matched the auto-fix allowlist.
- `--max-iters` is a hard cap; default 3. Above 5 the skill warns "thrashing — investigate".
- Two consecutive iterations with identical finding sets → exit with `verdict: NO_PROGRESS`
  (the fixer is regressing or the auditor is non-deterministic; human triage).
- If `release:release-code-fixer` reports `cannot_fix`, reclassify as `NEEDS_HUMAN` and continue.
  Never retry the same fixer twice on the same finding within one run.
- `.planning/` is untouched — this plugin owns `.release-planning/` only.

## Stack dispatch

`release:release-security-auditor` and `release:release-code-fixer` dispatch by stack at agent level (django
vs react retro variants). This skill does not duplicate that logic — it just passes the phase
number and lets agents resolve stack from `PROJECT.md` / phase frontmatter.

## Example

```
/release:audit-fix 01 --max-iters 3

→ Pre-checks: working tree clean ✓, phase 01 stage=verified ✓
→ Stack: fullstack (django + react-tsx)

→ Iter 1: spawning 5 auditors in parallel...
  release:release-code-reviewer       → 4 findings
  release:release-security-auditor    → 3 findings (stack-dispatched)
  release:release-test-auditor        → 2 findings
  release:release-nyquist-auditor     → 2 findings
  release:react-ui-auditor          → 1 finding
  Total: 12 findings

→ Classified: 7 AUTO_FIXABLE, 4 NEEDS_HUMAN, 1 SKIPPED (LOW)
→ Dispatching release:release-code-fixer ×7...
  fix(01): lint — ruff E501 views.py (commit a1b2c3)
  fix(01): n+1 — prefetch_related InvoiceList (commit d4e5f6)
  fix(01): aria — aria-label on icon button (commit g7h8i9)
  fix(01): unused — drop dead import (commit j0k1l2)
  fix(01): meta — add Meta.ordering (commit m3n4o5)
  fix(01): logging — drop console.log (commit p6q7r8)
  fix(01): zod — add schema to invoice form (commit s9t0u1)

→ Iter 2: re-auditing...
  4 findings remain (all NEEDS_HUMAN from iter 1)
  0 AUTO_FIXABLE → exit

→ Verdict: HUMAN_ONLY
→ .release-planning/audit-fix-log.md updated

Next: triage 4 NEEDS_HUMAN findings, then re-run /release:audit-fix 01
```
