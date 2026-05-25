---
description: >
  Close the current milestone. Runs the release-milestone-auditor to verify every phase is
  shipped, every UAT closed, every REQ covered, then archives phase dirs under
  `.release-planning/milestones/{name}/phases/`, generates a milestone SUMMARY.md (timeline,
  commits, LOC, key decisions, requirements matrix), moves the milestone section in ROADMAP.md
  under "Completed (archive)", and clears the active milestone in PROJECT.md.
  Use when: every phase in the current milestone is at stage `shipped` and you want to lock
  the cycle before starting the next one.
allowed_tools: Agent, Read, Write, Bash, Grep, Glob, AskUserQuestion
---

# /release:complete-milestone — Archive and Lock a Milestone

Closes the active milestone. The auditor runs first as a hard gate: any GAP (uncovered
requirement, open UAT, non-PASS verify) aborts the close. On PASS, phase directories are
moved under `.release-planning/milestones/{name}/`, a milestone-level SUMMARY.md is generated,
ROADMAP.md is compacted, and PROJECT.md's milestone field is cleared (or set to the next
planned milestone if one exists).

This is a one-way operation. The companion `/release:audit-milestone` is the safe, non-
destructive sibling for mid-cycle health checks.

## Usage

```
/release:complete-milestone                      # auto-detect current milestone from PROJECT.md
/release:complete-milestone --milestone v1.0     # explicit (must match an existing milestone)
/release:complete-milestone --dry-run            # print the close plan; no writes, no commit
/release:complete-milestone --force              # skip pre-check #4 (worktree clean) — discouraged
```

`--dry-run` still runs the milestone auditor (read-only). It just stops before any mutation.

---

## Pre-checks (hard gates)

All must pass. Any failure → abort with the listed message and do nothing.

| # | Probe | Failure message |
|---|---|---|
| 1 | `.release-planning/PROJECT.md` exists | `"PROJECT.md not found — run /release:init first."` |
| 2 | Resolved milestone has ≥1 phase in ROADMAP.md | `"Milestone {name} has no phases — nothing to complete."` |
| 3 | EVERY phase in the milestone is at stage `shipped` per STATE.md AND has `Status: complete` in ROADMAP.md | `"Phase(s) {NN[,NN…]} not shipped (stage={stage}). Ship them first or move to next milestone explicitly."` |
| 4 | `git status --short` is empty (unless `--force`) | `"Worktree dirty. Commit/stash first, or pass --force."` |

Pre-check #3 lists every offending phase — do not stop at the first. The user needs the full
list to know what's left.

---

## Execution flow

### Step 1 — Spawn the milestone auditor

Dispatch the `release-milestone-auditor` agent (defined at
`/Users/lucas/release/personal/django-sdk/agents/release-milestone-auditor.md`). Inputs:

```
milestone:    {resolved name}
milestone_dir: .release-planning/  (auditor will glob phases/{NN}-*/ matching the milestone window)
roadmap_path: .release-planning/ROADMAP.md
project_path: .release-planning/PROJECT.md
requirements_path: .release-planning/REQUIREMENTS.md
mode: complete    # signals: full audit, will be used as a gate
```

The auditor reads every phase artifact in the milestone, classifies each REQ as
COVERED / PARTIAL / GAP, every UAT item as CLOSED / OPEN, every verify verdict as PASS / FAIL,
and writes:

```
.release-planning/milestones/{name}/MILESTONE-AUDIT-{name}.md
```

Wait for the auditor to finish. Read the frontmatter `verdict:` field.

### Step 2 — Gate on the audit verdict

```
if audit.gap_count > 0 OR audit.open_uat_count > 0 OR audit.verify_fail_count > 0:
  ABORT with the auditor's summary table inline:
    "Milestone {name} has unresolved coverage gaps:
       - {N} requirement(s) classified GAP
       - {M} UAT item(s) still OPEN
       - {K} phase(s) with verify_verdict != PASS
     See {audit path} for the matrix. Fix or run /release:complete-milestone --force-skip-audit
     ONLY if you accept the gaps. Recommended: address each row, then re-run."
```

The `--force-skip-audit` escape is intentionally undocumented in the usage block above. It
exists for emergencies (e.g. auditor false positive) and only kicks in when typed exactly.

If `--dry-run`, print the audit summary + the move plan (no actual moves), then exit.

### Step 3 — Archive phase directories

For each phase `NN-slug` in the milestone:

```
mkdir -p .release-planning/milestones/{name}/phases/
git mv .release-planning/phases/{NN}-{slug}/ .release-planning/milestones/{name}/phases/{NN}-{slug}/
```

Use `git mv` (not raw `mv`) so the move is tracked in the commit. If `git mv` fails on a
phase directory (e.g. untracked artifacts), abort and report which phase couldn't move — do
not leave partial moves.

### Step 4 — Generate milestone SUMMARY.md

Write `.release-planning/milestones/{name}/SUMMARY.md`. Content sourced from the audit + git
history + phase SUMMARY.md files:

```markdown
---
milestone: {name}
theme: {one-liner from ROADMAP.md}
started: {first commit on first phase of milestone}
shipped: {last commit on last shipped phase}
duration_days: {N}
phase_count: {N}
commit_count: {N}
loc_delta: +{added} / -{removed}
status: complete
---

# Milestone {name} — {theme}

## Timeline

- Started:  {YYYY-MM-DD} (Phase 01 first commit {hash})
- Shipped:  {YYYY-MM-DD} (Phase NN last commit {hash})
- Duration: {N} days

## Phases shipped ({N})

| Phase | Slug | Shipped | Last commit | UATs | LOC |
|------|------|---------|-------------|------|-----|
| 01   | …    | …       | …           | …    | …   |
| …    | …    | …       | …           | …    | …   |

## Key decisions (D-XX)

Compiled from all `{NN}-CONTEXT.md` files in the milestone. Deduplicated by D-XX id.

- **D-03** ({phase 01}) — …
- **D-07** ({phase 02}) — …
- …

## Requirements coverage

| REQ | Description | Phases | Status |
|-----|-------------|--------|--------|
| REQ-01 | … | 01, 02 | COVERED |
| REQ-02 | … | 03     | COVERED |
| …      | … | …      | …       |

100% must be COVERED at this point — the auditor gated step 2. Any PARTIAL/GAP here is a bug
in this skill's audit handling.

## Notable findings

(Optional: HIGH/MEDIUM auditor findings that did NOT block completion — e.g. coverage that
is thin but passes Nyquist's >=2 bar. Surfaced here for the next milestone planning.)

## Commits

Total: {N} commits across {N} phases.

(For very large milestones, the auditor truncates to top-20 by LOC delta and links to git
log for the rest.)

---

_Generated by /release:complete-milestone on {YYYY-MM-DD}._
```

### Step 5 — Update ROADMAP.md

1. Locate the `## Milestone {name} — {theme}` section.
2. Move its entire block under `## Completed (archive)` (create section if absent).
3. Compact each phase entry to a single line: `- ✓ Phase NN — slug — shipped YYYY-MM-DD — {commit}`.
4. Drop the verbose Success Criteria / Requirements / Depends-on blocks (they live in the
   archived phase dirs and in SUMMARY.md).

### Step 6 — Update PROJECT.md

- If a "next milestone" line is present elsewhere in PROJECT.md (e.g. a `**Next milestone:** v1.1`
  field set by planning notes), set `**Milestone:**` to that value.
- Otherwise, clear the field: `**Milestone:** _none — run /release:new-milestone_`.

### Step 7 — Update STATE.md

Set cursor to idle. Append history entry:

```markdown
## {YYYY-MM-DDTHH:MM:SSZ} — milestone:{name}:complete
- phase_count: {N}
- commit_count: {N}
- duration_days: {N}
- summary: .release-planning/milestones/{name}/SUMMARY.md
- audit: .release-planning/milestones/{name}/MILESTONE-AUDIT-{name}.md
- cursor: idle
```

### Step 8 — Commit

Single atomic commit. Stage every moved phase dir, the new SUMMARY.md, the audit report, and
the three updated planning files (PROJECT, ROADMAP, STATE).

```
chore(milestone): complete {name}

Phases shipped: {N}
Duration: {N} days
Commits: {N}
LOC: +{added} / -{removed}

Auditor verdict: PASS ({REQ_total} requirements, 0 GAP, 0 OPEN UAT)
Summary: .release-planning/milestones/{name}/SUMMARY.md
Audit:   .release-planning/milestones/{name}/MILESTONE-AUDIT-{name}.md
```

---

## Outputs

```
.release-planning/milestones/{name}/MILESTONE-AUDIT-{name}.md   # from the auditor (Step 1)
.release-planning/milestones/{name}/SUMMARY.md                  # from Step 4
.release-planning/milestones/{name}/phases/{NN}-{slug}/...      # moved from phases/ (Step 3)

.release-planning/PROJECT.md      # milestone field cleared or advanced
.release-planning/ROADMAP.md      # milestone moved under "Completed (archive)"
.release-planning/STATE.md        # cursor = idle, history entry appended
```

Single git commit (`chore(milestone): complete {name}`) on the current branch.

---

## Example

```
/release:complete-milestone

→ Pre-checks
  ✓ PROJECT.md found (Milestone: v1.0)
  ✓ v1.0 has 5 phases in ROADMAP.md
  ✓ All 5 phases at stage shipped
  ✓ worktree clean

→ Resolved milestone: v1.0

→ Spawning release-milestone-auditor...
  · 5 phases scanned
  · 18 requirements: 18 COVERED, 0 PARTIAL, 0 GAP
  · 22 UAT items: 22 CLOSED, 0 OPEN
  · 5 phase verify verdicts: 5 PASS
  · 3 HIGH non-blocking findings (carried forward as notes)
  · verdict: PASS

→ Archiving phase directories...
  · git mv phases/01-invoice-pdf → milestones/v1.0/phases/01-invoice-pdf
  · git mv phases/02-invoice-archive → milestones/v1.0/phases/02-invoice-archive
  · ...

→ Generating SUMMARY.md
  · timeline: 2026-03-04 → 2026-05-20 (77 days)
  · commits: 124
  · LOC: +8,412 / -1,205

→ Updating ROADMAP.md (v1.0 → Completed archive)
→ Updating PROJECT.md (Milestone: v1.0 → _none_)
→ Updating STATE.md (cursor: idle)

→ Commit: chore(milestone): complete v1.0

Next: /release:new-milestone   (start v1.1)
```

---

## Constraints

- **Auditor gate is non-negotiable.** Any GAP, open UAT, or non-PASS verify aborts the close.
  `--force-skip-audit` exists as a documented escape but is intentionally not in the usage
  block — the user must know to type it.
- **Atomic move + commit.** Either all phase dirs move and all four planning files update, or
  none do. Half-archived milestones are worse than not-archived ones.
- **`git mv`, never raw `mv`.** Preserves rename detection in `git log --follow`.
- **Never delete phase artifacts.** Everything moves under `.release-planning/milestones/`.
  The directory structure is the audit trail.
- **Never touch `.planning/`.** GSD-owned. release-sdk lives in `.release-planning/`.
- **No PR creation, no push.** Completion is a local milestone-locking commit. Pushing
  is the user's call (or `/release:ship` for the final phase).
- **One milestone at a time.** Do not allow `--milestone v1.0 --milestone v0.9` chaining. The
  auditor + move logic is stateful; running it once per milestone is the contract.
- **Dry-run runs the auditor.** It must — the user wants to see the gate verdict before
  committing to the close. Dry-run just stops before moves/writes/commit.

---

## Notes

- GSD analog: mirrors `/gsd:complete-milestone`. Different filesystem; same intent.
- The auditor agent (`release-milestone-auditor`) is also reusable standalone via
  `/release:audit-milestone` for mid-cycle health checks. The only difference is the output
  path (timestamped under `.release-planning/` vs. canonical under `milestones/{name}/`).
- "Notable findings" in SUMMARY.md is a deliberate carry-over. The next milestone planning
  benefits from seeing what was thin-but-acceptable in the closed milestone (e.g. tests at
  exactly the Nyquist bar of 2, security audit MEDIUM findings deferred).
- This skill does NOT run `/release:audit-uat` or `/release:audit-fix` automatically. Those
  are separate close-out steps; the user is expected to have run them before invoking
  `/release:complete-milestone`. If they didn't, the auditor catches the gaps.

*One way out of a milestone. Audited, archived, committed.*
