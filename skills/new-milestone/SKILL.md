---
name: new-milestone
description: >
  Initialize a new milestone cycle (e.g. v1.0 → v1.1). Bumps the `Milestone:` field in
  PROJECT.md, appends a new milestone section to ROADMAP.md (empty phases list), and optionally
  promotes selected items from the Backlog section into the new milestone as placeholder phases.
  Asks the user for milestone name, theme, backlog promotions, and estimated phase count.
  Never deletes the previous milestone — it remains in ROADMAP.md under "Completed (archive)".
  Use when: the previous milestone has shipped (or been completed via /release:complete-milestone)
  and the team is ready to define the next cycle.
allowed_tools: Read, Write, Bash, Grep, Glob, AskUserQuestion
---

# /release:new-milestone — Start a New Milestone Cycle

Bumps the project's active milestone. Updates `PROJECT.md`, appends a fresh milestone section
in `ROADMAP.md`, and optionally moves Backlog items into the new cycle as placeholder phases.
The previous milestone is preserved verbatim under "Completed (archive)".

This skill never invents phases. It only sets up the milestone frame — the user runs
`/release:phase` afterwards to flesh out each phase.

## Usage

```
/release:new-milestone                       # interactive (asks all questions)
/release:new-milestone --milestone v1.1      # pre-fill the milestone name
/release:new-milestone --force               # skip the worktree-clean check
/release:new-milestone --dry-run             # print the diff plan; do not write
```

`--force` is the only escape from pre-check #3 (clean worktree). Use it only when you
intentionally want to mix milestone setup with in-flight changes.

---

## Pre-checks (hard gates)

All must pass before any file is written. Any failure → abort with the listed message and do
nothing.

| # | Probe | Failure message |
|---|---|---|
| 1 | `test -d .release-planning` | `".release-planning/ not found — run /release:init first."` |
| 2 | `.release-planning/PROJECT.md` exists AND has a `Milestone:` field | `"PROJECT.md missing Milestone: field — cannot bump from unknown baseline."` |
| 3 | `git status --short` is empty (unless `--force`) | `"Worktree dirty. Commit/stash first, or pass --force."` |
| 4 | No phase in the current milestone is at stage `executing` or `planned` per `STATE.md` + `ROADMAP.md` | `"Phase {NN} is at stage {stage}. Complete it or use /release:complete-milestone first."` |

Stage detection (probe #4):

```
read STATE.md → current_milestone, per-phase stage
read ROADMAP.md → status field per phase (in-plan, in-execute, complete, …)

for phase in phases_in_current_milestone:
  if stage in {planned, planning, executing} OR status in {in-plan, in-execute}:
    ABORT  → message above with {NN} and {stage}
```

`spec` and `discussed` stages are tolerated — they're cheap to carry into the next milestone
as residual work. `verified` and `shipped` are also fine.

---

## Questions asked (via AskUserQuestion)

#### 1. Milestone name / version
Free text. Examples: `v1.1`, `v2.0-beta`, `2026-Q2`. Must not match an existing milestone in
ROADMAP.md.

#### 2. Theme / goal (one-liner)
One sentence describing the outcome this milestone delivers. Becomes the milestone section
sub-header in ROADMAP.md.

Examples:
- "Multi-tenant audit log + admin dashboard"
- "Frontend perf overhaul (Core Web Vitals < 200ms)"
- "Payments v2 — Stripe Connect onboarding"

#### 3. Promote backlog items?
Multi-select. The skill reads `ROADMAP.md`'s `## Backlog (deferred — not yet scheduled)`
section, lists each item, and lets the user pick zero or more to lift into the new milestone
as placeholder phases (status `not-started`, no goal text yet — that comes from `/release:phase`).

If the Backlog section is empty or absent, this question is skipped.

#### 4. Estimated phase count
Multi-choice. Used only to size expectations in the milestone header; no enforcement.

- `3` — tight, small milestone
- `5-7` — typical
- `8+` — broad / multi-feature

---

## Execution flow

### Step 1 — Detect current milestone

```
current_milestone = grep '^**Milestone:**' .release-planning/PROJECT.md → value
current_phases    = parse ROADMAP.md "## Phases" under current_milestone section
backlog_items     = parse ROADMAP.md "## Backlog" section bullets
```

If `current_milestone` is empty (e.g. fresh init that never named one), proceed but skip the
"previous milestone archive" step.

### Step 2 — Ask the user

Run the four questions above in order via `AskUserQuestion`. Cache answers locally.

If the user provided `--milestone` on the command line, skip Q1 and use that value (still
validate against duplicates).

### Step 3 — Mutate artifacts

Order matters — do all reads first, build the new file contents in memory, then write
sequentially. If any write fails, do NOT proceed to the next; abort and tell the user the
worktree is half-updated.

#### 3a. Update PROJECT.md

Replace the existing `**Milestone:**` value with the new one. Everything else byte-for-byte
preserved.

```diff
- **Milestone:** v1.0
+ **Milestone:** v1.1
```

#### 3b. Update ROADMAP.md

Three edits, in this order:

1. **Archive the old milestone section.** If the previous milestone has a "## Milestone {old}"
   heading, move that entire block under "## Completed (archive)" (creating the Archive section
   if absent). Compact each archived phase to a single bullet: `- ✓ Phase NN — slug — shipped {YYYY-MM-DD} — {commit}` (pull dates/commits from STATE.md history or phase SUMMARY.md).
2. **Append the new milestone section.** Right after the project header, insert:

```markdown
## Milestone {new-name} — {theme}

**Estimated phases:** {3 | 5-7 | 8+}
**Started:** {YYYY-MM-DD}

### Phases

{one entry per promoted backlog item, format below; otherwise leave empty with a TODO comment}
```

3. **Promote backlog items.** For each item the user selected in Q3, insert into the Phases
   list as a placeholder:

```markdown
### Phase NN — {backlog-slug}

**Goal:** {original backlog one-liner — leave for /release:phase to refine}

**Status:** `not-started`

**Success Criteria:**
- [ ] _TBD — fill via /release:phase or /release:spec_

**Requirements covered:** _TBD_

**Depends on:** _none_

**Estimated context cost:** _TBD_

---
```

Phase numbering continues from the previous milestone's last phase. Example: prev milestone
ended at Phase 07 → new milestone starts at Phase 08.

Remove the selected items from the `## Backlog` section.

#### 3c. Update STATE.md

Append a history entry. Do not change the cursor (the cursor only advances when a phase is
actually started).

```markdown
## {YYYY-MM-DDTHH:MM:SSZ} — milestone:{new-name}:start
- previous milestone: {old-name} ({N} phases archived)
- new milestone: {new-name} ({M} placeholder phases promoted from backlog)
- estimated phase count: {3 | 5-7 | 8+}
- theme: {theme one-liner}
```

### Step 4 — Commit

Single atomic commit:

```
chore(milestone): start {new-name}

Theme: {theme}
Promoted from backlog: {N} item(s)
Archived: milestone {old-name}
```

If `--dry-run`, print the proposed diffs for all three files and exit with no writes and no
commit.

---

## Outputs

After a successful run:

```
.release-planning/PROJECT.md     # Milestone: field bumped
.release-planning/ROADMAP.md     # new milestone section appended; old archived
.release-planning/STATE.md       # history entry added
```

Single commit on the current branch.

---

## Example

```
/release:new-milestone

→ Pre-checks
  ✓ .release-planning/ exists
  ✓ PROJECT.md has Milestone: v1.0
  ✓ worktree clean
  ✓ v1.0: all 5 phases at stage shipped

→ Detected current milestone: v1.0 (5 phases, last = 05)
→ Backlog contains 4 items:
  1. bulk-pdf-export — defer until invoicing redesign settles
  2. webhooks-v2 — needs spec from partners
  3. mobile-push-onboarding — UX blocked
  4. admin-audit-log — depends on auth refactor

→ Q1: Milestone name?           → "v1.1"
→ Q2: Theme?                    → "Audit log + admin dashboard"
→ Q3: Promote which backlog?    → [4] admin-audit-log
→ Q4: Estimated phase count?    → "5-7"

→ Mutating artifacts
  · PROJECT.md   Milestone: v1.0 → v1.1
  · ROADMAP.md   archive v1.0 (5 phases) → "Completed (archive)"
  · ROADMAP.md   insert "## Milestone v1.1 — Audit log + admin dashboard"
  · ROADMAP.md   promote admin-audit-log → Phase 06 (placeholder)
  · ROADMAP.md   remove admin-audit-log from Backlog
  · STATE.md     append history entry

→ Commit: chore(milestone): start v1.1

Next: /release:phase add  (flesh out Phase 06 and define 07..)
      /release:spec 06    (start the SPEC pass on the promoted phase)
```

---

## Constraints

- **Never auto-create phases beyond promoted backlog items.** The user runs `/release:phase`
  to add new phases manually. This skill is structural only.
- **Never delete the previous milestone.** It moves verbatim under "Completed (archive)" so
  audit trails stay intact. If the user wants it gone, they edit ROADMAP.md by hand.
- **Never modify `.planning/`.** That's GSD-owned. release-sdk lives in `.release-planning/`.
- **Single atomic commit.** No partial states — either all four mutations land together or
  none do.
- **Idempotent on the same milestone name is forbidden.** If the user tries to "start" a
  milestone that already exists in ROADMAP.md, abort with `"Milestone {name} already exists.
  Pick a different name or edit ROADMAP.md manually."`.
- **No SPEC/CONTEXT/PLAN side-effects.** Phase artifact dirs (`.release-planning/phases/`)
  are untouched. Placeholder phases have ROADMAP entries only.
- **Worktree must be clean unless `--force`.** Milestone bumps mixed with feature work
  produce hard-to-revert commits.
- **STATE.md cursor is NOT advanced.** Starting a milestone is not the same as starting a
  phase. The cursor advances when `/release:spec NN` or `/release:phase` puts work into NN.

---

## Notes

- GSD analog: mirrors `/gsd:new-milestone`. Same intent (milestone cycle init), different
  filesystem (`.release-planning/` vs `.planning/`). The two coexist; this skill does not
  touch `.planning/`.
- The "Completed (archive)" section in ROADMAP.md can grow indefinitely. For very long-lived
  projects, consider `/release:complete-milestone --hard-archive` (future) to move archived
  milestone blocks into `.release-planning/milestones/{name}/ROADMAP-ARCHIVE.md`.
- This skill does NOT call `/release:complete-milestone`. Completion is a separate, deliberate
  step — it generates a summary, runs the milestone auditor, and locks the previous milestone.
  If the user runs `/release:new-milestone` without having shipped the previous one, pre-check
  #4 blocks them.

*Frames the next cycle. Doesn't presume what's in it.*
