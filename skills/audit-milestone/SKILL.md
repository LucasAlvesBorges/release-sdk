---
description: >
  Standalone, non-destructive milestone audit. Runs the release-milestone-auditor agent against
  the current (or a specified) milestone and writes a timestamped MILESTONE-AUDIT-{name}-{date}.md
  to `.release-planning/`. Reports requirement coverage (COVERED / PARTIAL / GAP), UAT closure,
  and verify verdicts per phase. Does NOT move phase directories, does NOT update STATE.md,
  does NOT commit (unless --commit).
  Use when: mid-milestone health check, pre-flight before /release:complete-milestone, or
  ad-hoc audit anytime to surface drift between SPEC, UAT, REQs, and shipped code.
allowed_tools: Agent, Read, Write, Bash, Grep, Glob, AskUserQuestion
---

# /release:audit-milestone — Non-Destructive Milestone Health Check

Runs the same `release-milestone-auditor` agent that gates `/release:complete-milestone`, but
read-only. Output goes to a timestamped file under `.release-planning/` (not under
`milestones/{name}/`), so re-running it leaves a trail without touching the canonical archive
location.

Safe to run anytime: mid-milestone, just before completion, or weeks after archive (audits a
past milestone by name).

## Usage

```
/release:audit-milestone                         # current milestone (from PROJECT.md)
/release:audit-milestone --milestone v1.0        # explicit milestone (current or archived)
/release:audit-milestone --hot-list              # print only uncovered REQs + open UATs (no full file)
/release:audit-milestone --commit                # commit the timestamped audit file
/release:audit-milestone --milestone v1.0 --hot-list   # combine
```

`--hot-list` skips writing a full audit file and prints just the high-signal rows to stdout.
Useful for daily standup checks.

---

## Pre-checks

| # | Probe | Failure message |
|---|---|---|
| 1 | `.release-planning/PROJECT.md` exists | `"PROJECT.md not found — run /release:init first."` |
| 2 | Resolved milestone has ≥1 phase | `"Milestone {name} has no phases — nothing to audit."` |

That's it. No worktree-clean check (read-only). No stage check (auditing mid-milestone is the
whole point).

---

## Resolution rules

1. `--milestone` flag → use it as-is. Must match either an active milestone in ROADMAP.md OR
   an archived directory at `.release-planning/milestones/{name}/`.
2. No flag → read `**Milestone:**` from PROJECT.md.
3. Neither resolvable → abort with `"No milestone to audit. Pass --milestone or set one in PROJECT.md."`.

For archived milestones, the auditor reads from `.release-planning/milestones/{name}/phases/`
instead of `.release-planning/phases/`. Same agent, different scan root.

---

## Execution flow

### Step 1 — Resolve and announce

```
milestone = resolve(--milestone, PROJECT.md)
phases    = enumerate phases_in_milestone(milestone)
scan_root = .release-planning/phases/  (active)  OR
            .release-planning/milestones/{name}/phases/  (archived)

print:
  → Auditing milestone {name} ({len(phases)} phases) — scan root: {scan_root}
```

### Step 2 — Spawn the auditor

Dispatch `release-milestone-auditor` with:

```
milestone:        {name}
scan_root:        {resolved above}
roadmap_path:     .release-planning/ROADMAP.md
project_path:     .release-planning/PROJECT.md
requirements_path: .release-planning/REQUIREMENTS.md
mode:             audit              # NOT "complete" — auditor knows not to expect 100% closure
```

Mode `audit` tells the auditor to:
- Not treat OPEN UATs or PARTIAL coverage as fatal — just report them.
- Annotate each row with phase stage (`spec`, `discussed`, `planned`, `executing`, `verified`,
  `shipped`) so the user can tell drift from work-in-flight.

### Step 3 — Write output (or print hot-list)

#### Default mode (full audit file)

```
.release-planning/MILESTONE-AUDIT-{name}-{YYYY-MM-DD}.md
```

Re-running on the same day overwrites the file (idempotent within a day). Cross-day runs leave
each timestamped audit in place.

#### `--hot-list` mode

Skip the file write. Print only:

```
→ Milestone {name} — hot list ({YYYY-MM-DD HH:MM:SSZ})

  Uncovered REQs:
    REQ-04 — invoice export PDF a11y      (target phase: 03, stage=executing)
    REQ-09 — admin audit log retention    (target phase: 06, stage=spec)

  Open UAT items:
    U-02 (phase 03) — bulk import resumes on error
    U-05 (phase 04) — search filters preserve across navigation
    U-08 (phase 04) — keyboard nav on combobox

  Verify FAIL phases:
    (none)

  Verdict: WORK_IN_PROGRESS (3 phases still executing / 6 shipped)
```

Hot-list is stdout-only — no file, no commit, no STATE entry.

### Step 4 — Optional commit

If `--commit` was passed (and not in hot-list mode), commit the audit file:

```
chore(audit): milestone {name} health check ({YYYY-MM-DD})

Verdict: {PASS | WORK_IN_PROGRESS | DRIFT}
Coverage: {COVERED}/{TOTAL} REQs, {CLOSED}/{TOTAL} UATs
```

Without `--commit`, the file is left untracked. The user can `git add` + commit manually or
discard it.

---

## Output

#### Default mode

```
.release-planning/MILESTONE-AUDIT-{name}-{YYYY-MM-DD}.md
```

Same template as `/release:complete-milestone` step 1, but with mode `audit` reflected in
frontmatter:

```yaml
---
audited_at: {iso}
milestone: {name}
mode: audit
phase_count: {N}
phases_shipped: {N}
phases_in_progress: {N}
req_total: {N}
req_covered: {N}
req_partial: {N}
req_gap: {N}
uat_total: {N}
uat_closed: {N}
uat_open: {N}
verify_pass: {N}
verify_fail: {N}
verify_pending: {N}
verdict: PASS | WORK_IN_PROGRESS | DRIFT
---
```

Verdicts in audit mode:
- `PASS` — every REQ COVERED, every UAT CLOSED, every verify PASS. Same as the completion gate.
- `WORK_IN_PROGRESS` — gaps exist but they map to phases still pre-shipped (stage ≠ shipped).
  Healthy mid-milestone state.
- `DRIFT` — gaps exist on shipped phases (REQ marked GAP/PARTIAL but the phase is `shipped`).
  This is a coverage hole; the phase shipped without closing what it claimed to deliver. Fix
  is `/release:plan {NN} --gaps` or amend SPEC.

#### `--hot-list` mode

stdout only (see Step 3).

---

## Example

```
/release:audit-milestone

→ Resolved milestone: v1.1 (6 phases — 3 shipped, 3 in-flight)
→ Scanning .release-planning/phases/

→ Spawning release-milestone-auditor (mode=audit)...
  · 6 phase dirs scanned
  · 22 requirements: 14 COVERED, 5 PARTIAL, 3 GAP
  · 28 UAT items: 19 CLOSED, 9 OPEN
  · 3 verify verdicts: 3 PASS, 0 FAIL, 3 PENDING (phases not yet verified)

→ Verdict: WORK_IN_PROGRESS
  · All 3 GAP REQs map to phases currently in stage `executing` (06) or `spec` (07)
  · No DRIFT detected (shipped phases all 100% covered)

→ Wrote .release-planning/MILESTONE-AUDIT-v1.1-2026-05-25.md
   (not committed — pass --commit to track)

Next: address GAP rows via /release:spec 07 / /release:plan 06, then re-run.
```

Hot-list variant:

```
/release:audit-milestone --hot-list

→ Milestone v1.1 — hot list (2026-05-25 09:14:02Z)

  Uncovered REQs:
    REQ-12 — admin role-based dashboard widgets   (phase 07, stage=spec)
    REQ-13 — audit log retention policy           (phase 07, stage=spec)
    REQ-15 — bulk-action confirmation modal       (phase 06, stage=executing)

  Open UAT items:
    U-04 (phase 05) — empty-state copy review
    U-06 (phase 06) — combobox keyboard nav
    ... (7 more)

  Verify FAIL phases:
    (none)

  Verdict: WORK_IN_PROGRESS
```

---

## Constraints

- **Read-only by default.** No phase dir moves, no STATE.md updates, no commits unless
  `--commit` is passed.
- **Safe to run anytime.** No phase-stage pre-checks; mid-milestone audits are first-class.
- **Same auditor as `/release:complete-milestone`.** Single source of truth for milestone
  coverage logic; differences are output path + mode flag.
- **Hot-list is stdout-only.** It never writes a file, even if `--commit` is also passed
  (`--commit` is ignored in hot-list mode with a warning).
- **Audits archived milestones too.** Pass `--milestone v0.9` to audit a milestone that's
  already under `.release-planning/milestones/`. Useful for retrospective drift checks.
- **Never touches `.planning/`.** GSD-owned.
- **Idempotent within a day.** Same milestone, same date → file overwrites. Across days →
  each timestamped audit persists for trend tracking.

---

## Notes

- GSD analog: `/gsd:audit-milestone`. Different filesystem; identical intent.
- This skill pairs well with `/release:audit-uat` (cross-phase UAT triage) and
  `/release:validate-phase` (Nyquist sampling per phase). Run sequence for a thorough
  pre-completion sweep:

  ```
  /release:audit-uat                         # surface UATs across all phases
  for nn in 01 02 03 ...; do
    /release:validate-phase --audit-only $nn # Nyquist per phase
  done
  /release:audit-milestone                   # roll up into a milestone-level matrix
  ```

- For very large milestones (>20 phases), the auditor may take 1-2 minutes. The skill prints
  progress (`scanning phase NN…`) so it's not silently hanging.

*The mirror without the move. Safe to run anytime; tells you what's left.*
