---
description: >
  Retroactive 6-pillar visual audit of implemented React code for a phase. Spawns release-ui-auditor
  to score accessibility, responsive, loading/error states, i18n, type contracts, and design-system
  adherence. Produces scored UI-REVIEW.md with remediation table per dimension.
  Use when: a phase shipped but UI quality is suspect, or for regular UI debt audits.
allowed_tools: Agent, Read, Write, Bash, Grep, Glob
---

# /release:ui-review — Retroactive 6-Pillar Visual Audit

Runs AFTER a phase is implemented and committed. Scores the shipped React code against six
quality pillars and produces a `{NN}-UI-REVIEW.md` scorecard with concrete remediation per
dimension. Distinct from `/release:ui-phase` (author-time design-contract) and from
`/release:verify` (truth-coverage, not quality-coverage).

## Difference vs sibling skills

| Axis | `/release:ui-phase` (author-time) | `/release:ui-review` (retroactive) | `/release:verify` (truth check) |
|---|---|---|---|
| When | Before implementation | After phase ships | After phase ships |
| Input | SPEC + CONTEXT + LOCKs | Shipped React source + UI-SPEC | PLAN must_haves + source |
| Output | `{NN}-UI-SPEC.md` (contract) | `{NN}-UI-REVIEW.md` (scored audit) | `{NN}-VERIFICATION.md` (truth verdict) |
| Modifies code | No | No (read-only audit) | No |
| Agents | release-ui-researcher | release-ui-auditor | release-phase-verifier |

## Usage

```
/release:ui-review 03                    # audit phase 03's shipped React code
/release:ui-review --all                 # audit every phase whose frontmatter has has_ui: true
/release:ui-review 03 --diff main..HEAD  # constrain evidence search to a diff range
/release:ui-review 03 --strict           # any pillar score <60 → BLOCK verdict
```

## Pre-checks

Abort cleanly (no auditor spawned, no commit) if:

1. `.release-planning/` does not exist → emit "Not a release-sdk project; run /release:init first."
2. `--all` mode: no phase has `has_ui: true` in its `{NN}-SUMMARY.md` frontmatter → emit
   "No UI-bearing phases detected. Nothing to audit."
3. Single-phase mode (`NN` given): `.release-planning/phases/{NN}-{slug}/{NN}-UI-SPEC.md`
   is missing → emit "Phase {NN} has no UI-SPEC.md — was this a backend-only phase? If it
   shipped UI, run `/release:ui-phase {NN}` first to author the contract retrospectively."
4. No React source files present anywhere under `src/` (`find src -name "*.tsx" | head -1`
   returns nothing) → emit "No React source detected; nothing to audit."

## Detection / Scope Resolution

For each phase being audited:

1. Locate `.release-planning/phases/{NN}-{slug}/`.
2. Read `{NN}-UI-SPEC.md` (the design contract) — captures intended UI-DEC-XX entries.
3. Read `{NN}-SUMMARY.md` frontmatter for `stack:` (must be `react` or `fullstack`).
4. Resolve in-scope files:
   - Default: union of `.tsx` / `.ts` files touched in phase commits, using
     `git log --name-only` between phase-start commit and HEAD.
   - `--diff REV..REV`: explicit diff range.
5. Bail out for a phase if the resolved set is empty (record as "no UI shipped" in summary).

## Execution

For each in-scope phase, spawn one `release-ui-auditor` with this config:

```yaml
phase_number: "{NN}"
phase_dir: ".release-planning/phases/{NN}-{slug}"
ui_spec_path: "{phase_dir}/{NN}-UI-SPEC.md"
in_scope_files: [list of .tsx/.ts paths]
mode: initial | re-audit
strict: false | true
```

When `--all`, run audits in parallel (one auditor per phase). Collect each result.

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-UI-REVIEW.md
```

The auditor produces a scorecard (see `release-ui-auditor` for full template). Frontmatter
includes `audited_at`, `score_total`, `score_per_dim` (6 numbers). The skill rolls these up
into a printed summary table.

## Verdict logic (per phase)

- `EXCELLENT` — total ≥ 85 AND no dimension < 70
- `OK`        — total ≥ 70 AND no dimension < 60
- `DEBT`      — total ≥ 50 (any dim may be < 60; remediation needed)
- `BLOCK`     — total < 50 OR (in `--strict` mode) any dimension < 60

## Commit

After all audits complete, stage and commit the produced UI-REVIEW.md files only:

```bash
git add .release-planning/phases/{NN}-{slug}/{NN}-UI-REVIEW.md
git commit -m "chore(ui-review): retroactive audit phase {NN}"
```

For `--all`, commit once with all paths in the message:

```bash
git commit -m "chore(ui-review): retroactive audit phases {01,03,07}"
```

Never auto-commits any source-code changes — the audit is read-only.

## Constraints

- Read-only: never edits React components, hooks, tests, or commits source-code changes.
- Auditors are leaf workers — they spawn no sub-agents.
- Scores must be 0-100 integers with file:line evidence in the per-dim section.
- Remediation table must list concrete fixes (no vague advice like "improve a11y").
- Skipped phases (no UI shipped, missing UI-SPEC) are reported in the run summary, never as a
  failed audit.

## Example

```
/release:ui-review 03

→ Phase: 03-invoice-list  (stack: fullstack)
→ UI-SPEC.md found: 8 UI-DECs
→ Scope: 11 .tsx files from a1b2c3..HEAD
→ Spawning release-ui-auditor...

→ Auditor results:
   Accessibility:   72 (target 80)  — 4 inputs missing aria-label
   Responsive:      88               — tailwind sm:/md:/lg: present throughout
   Loading/Error:   65 (target 80)  — error boundary missing on bulk-archive path
   i18n:            42 (BELOW 60)   — 17 hardcoded strings detected
   Type contracts:  91               — all props typed, Zod on API
   Design system:   80               — 2 ad-hoc inline styles flagged

→ Verdict: DEBT  (total 73; i18n below threshold)
→ UI-REVIEW.md written
→ chore(ui-review): retroactive audit phase 03

Next:
  • Address i18n gap before next UI-bearing phase
  • Run /release:ui-review 03 again to confirm uplift
```

```
/release:ui-review --all

→ Phases with has_ui: true: 01, 03, 07
→ Spawning 3 release-ui-auditor instances in parallel...

→ Summary:
   | Phase | Total | A11y | Resp | L/E | i18n | Types | DS  | Verdict   |
   |-------|-------|------|------|-----|------|-------|-----|-----------|
   | 01    | 88    | 90   | 92   | 85  | 80   | 95    | 86  | EXCELLENT |
   | 03    | 73    | 72   | 88   | 65  | 42   | 91    | 80  | DEBT      |
   | 07    | 81    | 78   | 82   | 80  | 75   | 90    | 81  | OK        |

→ chore(ui-review): retroactive audit phases 01,03,07
```

---

## Stack dispatch

This skill is React-only by design — `/release:ui-review` refuses Django-only phases at the
pre-check step. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field
(`react` | `fullstack`). For fullstack phases, only the React side is audited; backend code
is ignored. `django`-only projects abort with a clear message at pre-check.
