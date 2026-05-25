---
description: >
  Retroactively audit and fill Nyquist validation gaps for a completed phase. Every requirement
  in SPEC + every UAT item must be covered by >=2 tests (Nyquist-style sampling). Audit-only mode
  reports gaps; full mode dispatches /release:add-tests to fill them.
  Use when: phase shipped but coverage suspect; before declaring milestone complete.
allowed_tools: Agent, Skill, Read, Write, Bash, Grep, Glob
---

# /release:validate-phase — Nyquist Sampling Audit

Borrowed from the Nyquist-Shannon sampling theorem: a signal cannot be reconstructed from a
single sample. Applied to coverage: a requirement covered by exactly one test is *aliased* —
the test may be asserting an artifact, a coincidence, or a tautology. Two independent
assertions per requirement is the minimum bar.

This skill audits a completed phase against that bar and, in default mode, dispatches
`/release:add-tests` to fill gaps until every requirement has >=2 covering tests.

## Relationship to /release:verify and /release:verify-work

| Skill | Mode | Question answered |
|---|---|---|
| `/release:verify` | Goal-backward STATIC code audit | "Does shipped code match PLAN.md truths?" |
| `/release:verify-work` | Conversational UAT walkthrough | "Did the human confirm each UAT item works?" |
| `/release:validate-phase` | Test coverage SAMPLING audit | "Is every requirement covered by >=2 tests?" |

`/release:verify` + `/release:verify-work` are run-once gates per phase. `/release:validate-phase`
is a *recurring* gate — runnable any time after `verified` or `shipped`, including weeks later
during milestone close-out audits.

## Usage

```
/release:validate-phase {NN}                # audit + auto-generate gap-fill tests
/release:validate-phase --audit-only {NN}   # audit only; print report; do not generate
/release:validate-phase {NN} --backend      # restrict gap-fill to backend items
/release:validate-phase {NN} --frontend     # restrict gap-fill to frontend items
```

## Pre-checks

Abort with actionable message on any failure:

1. `.release-planning/` directory exists at repo root.
2. Phase dir `.release-planning/phases/{NN}-{slug}/` exists.
3. Phase stage in `.release-planning/STATE.md` is `verified` OR `shipped`.
   - Reject `discussing`, `planning`, `executing` — too early; tests not stable.
4. `{NN}-SPEC.md` AND `{NN}-UAT.md` both exist in the phase dir.
   - If only one is present, abort with: "Need both SPEC and UAT to compute Nyquist coverage."

## Stack detection

Same precedence as other release-* skills:

1. `--backend` / `--frontend` flag → forced stack for gap-fill (audit always scans both).
2. Read `{NN}-PLAN.md` frontmatter `stack:` field.
3. Read `.release-planning/PROJECT.md` `stack:` field.
4. `fullstack` with no flag → audit both, ask user before gap-fill dispatch.

## Execution

```
1. Spawn release-nyquist-auditor with:
     stack: django | react | fullstack
     phase_number: NN
     phase_dir: .release-planning/phases/{NN}-{slug}/
2. Auditor reads SPEC.md + UAT.md + VERIFICATION.md (if present), enumerates requirements,
   globs test files, counts references per requirement.
3. Auditor writes {phase_dir}/{NN}-NYQUIST-AUDIT.md with verdict:
     SUFFICIENT (all requirements have >=2 tests)
     THIN       (>=1 requirement has exactly 1 test)
     MISSING    (>=1 requirement has 0 tests)
4. If --audit-only:
     - Print summary table inline.
     - Stop. Do not dispatch.
5. Else (default):
     - Read NYQUIST-AUDIT.md gap list.
     - For each THIN/MISSING row, build a gap descriptor (requirement id + recommended test).
     - Dispatch /release:add-tests {NN} --gap-fill via the Skill tool, passing the gap list as
       extra context so add-tests prioritises uncovered requirements first.
     - When /release:add-tests returns, re-spawn release-nyquist-auditor to recompute coverage.
6. Commit the NYQUIST-AUDIT.md artifact:
     test({stack}): nyquist gap-fill for phase {NN}
   Stack token resolves to `django`, `ui`, or `fullstack` depending on detection.
```

The skill never modifies tests itself — all writes go through the `release-nyquist-auditor`
agent (for the audit report) and `/release:add-tests` (for new tests). This keeps the test-write
discipline (one path, surfaces failing tests as `TEST-GAP.md`) intact.

## Requirement extraction

The auditor enumerates requirements from three sources, deduplicated by normalised slug:

| Source | Extraction rule |
|---|---|
| `{NN}-SPEC.md` | Each row in `## Requirements` table; each bullet under `## Acceptance Criteria`. |
| `{NN}-UAT.md` | Each row in `## UAT Items` (U-XX). |
| `{NN}-VERIFICATION.md` (if present) | Each truth row from PLAN.md `must_haves.truths`. |

UAT items contribute *user-observable* requirements; SPEC contributes *system* requirements;
VERIFICATION contributes *behavioural* truths. The union is the Nyquist denominator.

## Coverage counting heuristics

For each requirement R, the auditor counts a test as "covering R" when any of the following
match the test file or function body:

1. **Name match** — requirement slug or U-XX id appears in `def test_*` / `it(...)` / `describe(...)`.
2. **Comment match** — requirement slug or U-XX id appears in a comment within the test body.
3. **Fixture match** — fixture / factory name referenced in the requirement appears in the test
   body, scoped to a fixture whose name maps to the requirement (e.g. `bulk_import_csv` fixture
   for a `bulk_import` requirement).
4. **Endpoint / symbol match** — endpoint URL, view class name, model name, component name, or
   route literal extracted from the requirement description appears in the test body.

Coincidental matches are accepted by design — the Nyquist principle is satisfied if *any* two
independent tests assert anything about the same surface; over-counting is preferable to
under-counting because the human sees the test-file list per requirement and can challenge it.

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-NYQUIST-AUDIT.md
```

Frontmatter:

```yaml
---
audited_at: {iso}
phase: {NN}
stack: django | react | fullstack
mode: full | audit-only
requirement_count: {N}
sufficient: {N}       # >=2 tests
thin: {N}             # exactly 1 test
missing: {N}          # 0 tests
verdict: SUFFICIENT | THIN | MISSING
gap_fill_dispatched: true | false
---
```

Body sections:

- `## Coverage Matrix` — one row per requirement: `| Req | Source | Tests count | Status | Test files |`
- `## Gap-Fill Recommendations` — one block per THIN/MISSING requirement: required test type
  (smoke / RTL / MSW / a11y / security / race / memray) + skeleton hint.
- `## Dispatched Tests` (full mode only) — populated by re-audit after add-tests returns; lists
  newly created test files and their target requirements.
- `## Verdict` — overall + per-stack roll-up.

## Anti-patterns

- Running on a phase still in `executing` stage → tests not stable; audit churns. Blocked at pre-check.
- Editing `{NN}-NYQUIST-AUDIT.md` by hand to mark SUFFICIENT → defeats sampling; re-run skill.
- Treating one high-quality integration test as equivalent to two unit tests → Nyquist insists
  on >=2 *independent* tests; one rich test still leaves the requirement aliased.
- Using `--audit-only` repeatedly without ever gap-filling → audit becomes wallpaper.

## What this skill does NOT do

- Does NOT modify implementation files; all writes are tests via `/release:add-tests`.
- Does NOT delete/rewrite existing tests; only adds.
- Does NOT advance STATE.md cursor — validation is post-shipping, no phase state change.
- Does NOT enforce coverage % thresholds — Nyquist is per-requirement, not per-line.
- Does NOT replace `/release:verify` or `/release:verify-work` — third gate, runs after both.
- Does NOT commit anything in `--audit-only` mode.

## Workflow integration

```
/release:execute 01 && /release:verify 01 && /release:verify-work 01
/release:validate-phase 01           # third gate — Nyquist
/release:ship 01

# Milestone audit (audit-only sweep):
for phase in 01 02 03 04 05; do /release:validate-phase --audit-only $phase; done
```

## Example

```
/release:validate-phase 03
-> Phase 03-bulk-import (stack=fullstack, stage=shipped)
-> Auditor: 14 requirements; 9 sufficient, 3 thin, 2 missing -> verdict MISSING
-> Dispatching /release:add-tests 03 --gap-fill with 5 target requirements...
-> 5 new test files committed.
-> Re-audit: 14/14 SUFFICIENT.
-> Commit: test(fullstack): nyquist gap-fill for phase 03
```


---

## Stack dispatch

This skill spawns the merged `release-nyquist-auditor` agent. Stack is inferred from
`.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack
phases, per-phase stack is read from the phase frontmatter. The auditor applies matching
stack-specific test-discovery rules (pytest globs for django; vitest + RTL globs for react).
