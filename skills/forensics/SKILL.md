---
name: forensics
description: >
  Post-mortem investigation for failed release-sdk workflows. Diagnoses what went wrong when a
  phase didn't complete, verify failed, autonomous run aborted. Produces timeline + 5-whys root
  cause + recovery plan in .release-planning/forensics/.
  Use when: something broke and you need a structured explanation before retrying.
---

# /release:forensics — Post-Mortem Failure Investigation

Read-only forensic pass over `.release-planning/` artifacts, STATE.md history, and git log
to explain why a phase, verify, or autonomous run aborted. Produces a timeline, 5-whys per
root cause, and a recovery plan you can act on before retrying.

## When to use

- A phase stopped mid-execute and you don't know which task / agent failed.
- `/release:verify` came back BLOCK and the SUMMARY doesn't explain why.
- An autonomous run aborted between phases — no human in the loop saw the failure.
- A reviewer flagged drift between PLAN.md and shipped code and you need the audit trail.

## What this skill does NOT do

- Does NOT modify any source file, artifact, commit, or branch.
- Does NOT re-run the failed workflow (use the recovery plan output for that).
- Does NOT replace `/release:debug` (that's interactive root-cause; this is offline reconstruction).
- Does NOT touch `.planning/` (this plugin lives in `.release-planning/`).

## Usage

```
/release:forensics                              # diagnose the most recent failure in STATE.md
/release:forensics 01                           # investigate phase 01 specifically
/release:forensics --since a1b2c3d              # investigate everything since that git SHA
/release:forensics 01 --since a1b2c3d           # combine — scope to phase AND time window
```

## Pre-checks (hard requirements)

1. `.release-planning/STATE.md` exists — abort with guidance if missing (no workflow to diagnose).
2. Current working dir is inside a git repo — abort otherwise (no commit history to walk).
3. If `{NN}` given: `.release-planning/phases/{NN}-*/` exists — abort if not.

No checks are made for clean working tree. Forensics is read-only; dirty trees are fine.

## Scope resolution

| Flag | Scope |
|---|---|
| (none) | Most recent FAIL / BLOCK / ABORT entry in STATE.md; pull its phase from the line. |
| `{NN}` | All phase `{NN}-*/` artifacts + STATE.md lines mentioning phase `{NN}`. |
| `--since {sha}` | Every phase touched by commits between `{sha}..HEAD` + STATE.md lines newer than `{sha}` timestamp. |
| `{NN} --since {sha}` | Intersection — phase `{NN}` events newer than `{sha}`. |

## Execution

1. **Load STATE.md history.** Read last 50 lines (or full file if shorter). Extract every
   `phase: NN`, `verdict: BLOCK|FAIL|ABORT`, `stage:`, and `timestamp:` field.

2. **Load phase artifacts in scope.** For each `{NN}-*/` directory:
   ```
   {NN}-SPEC.md         {NN}-PLAN.md            {NN}-PLAN-BACKEND.md
   {NN}-PLAN-FRONTEND.md {NN}-SUMMARY.md        {NN}-VERIFICATION.md
   {NN}-UAT.md          {NN}-SECURITY.md        {NN}-REVIEW.md
   {NN}-NYQUIST-AUDIT.md {NN}-EVAL-REVIEW.md    {NN}-UI-AUDIT.md
   ```
   Skip files that don't exist. Note their last-modified mtime for the timeline.

3. **Walk git history.** Within scope window, run:
   ```bash
   git log --pretty='format:%h|%ai|%s' --name-only {since}..HEAD
   ```
   Group commits by phase (parse `feat(NN):` / `test(NN):` / `refactor(NN):` prefix or
   commits on branch `feat/{NN}-{slug}`). Note: each task in PLAN.md should produce ≥1
   commit — flag any task with zero commits as a `gap` event.

4. **Identify failure surface.** Cross-reference STATE.md verdicts against artifacts:
   - `VERIFICATION.md verdict: BLOCK` → goal-backward verify failed; pull failing truths.
   - `REVIEW.md` HIGH/CRITICAL findings → reviewer caught regression.
   - `SECURITY.md` MISSING status → retroactive security audit blocked.
   - `UAT.md` items FAIL/BLOCKED → human gate failed.
   - `NYQUIST-AUDIT.md` gaps → validation coverage missing.
   - SUMMARY.md absent for a phase at stage `executing` → executor crashed mid-task.

5. **Cross-reference reviewer / auditor reports.** For each non-PASS verdict, extract the
   `evidence:` (file:line) and `remediation:` blocks verbatim — these become 5-whys seeds.

6. **Build timeline.** Sort events (STATE.md lines + commit timestamps + artifact mtimes)
   chronologically. Each row: `iso_timestamp | source | event`.

7. **5-whys per root cause.** For every distinct failure surface from step 4, write a
   5-whys chain. Stop when you hit either: an environmental cause (missing fixture, dep
   not installed), a process cause (skipped pre-check, plan never updated), or a code
   cause (specific commit introduced regression — name it).

8. **Recovery plan.** Map each root cause to a concrete next action. Prefer existing
   skills: `/release:plan {NN} --gaps`, `/release:execute {NN} --resume`,
   `/release:verify {NN}`, `/release:debug`, `/release:secure-phase {NN}`, etc. Order
   actions by dependency (fix the thing that's blocking the next thing first).

9. **Write report.** Single file:
   ```
   .release-planning/forensics/{ISO_timestamp}-report.md
   ```
   `ISO_timestamp` is `YYYY-MM-DDTHH-MM-SS` (filesystem-safe — no colons). Create the
   `forensics/` directory if it does not exist.

## Output format

```markdown
---
investigated_at: 2026-05-25T14:30:12Z
phases_in_scope: [01, 02]
since_sha: a1b2c3d
root_causes_count: 3
verdict_summary:
  fail: 1
  block: 2
  abort: 0
---

# Forensics Report — 2026-05-25T14:30:12Z

## Scope
- Phases: 01-invoices-crud, 02-invoices-list
- Time window: a1b2c3d..HEAD
- Triggered by: most recent STATE.md FAIL entry

## Timeline
| When | Source | Event |
|---|---|---|
| 2026-05-24T09:12Z | STATE.md | phase 01 stage: planning → executing |
| 2026-05-24T09:18Z | git | commit a1b2c3 test(invoices): add failing tests for create |
| 2026-05-24T09:45Z | git | commit d4e5f6 feat(invoices): implement InvoiceCreate viewset |
| 2026-05-24T10:02Z | 01-VERIFICATION.md | verdict: BLOCK (1 truth unmet) |
| 2026-05-24T10:03Z | STATE.md | phase 01 stage: executing → blocked |
| 2026-05-24T10:15Z | git | commit g7h8i9 feat(invoices): tenant scope filter (partial) |
| 2026-05-24T10:30Z | 01-REVIEW.md | HIGH finding: tenant filter only on list, not retrieve |

## Failure Surfaces
1. **VERIFICATION BLOCK** — `01-VERIFICATION.md` truth T-03 unmet
   - Evidence: `backend/apps/invoices/views.py:42` — list filtered, retrieve unfiltered.
2. **REVIEW HIGH** — `01-REVIEW.md` finding #2
   - Evidence: same file:line as above (correlated, not independent).

## Root Causes (5-whys)

### RC-1: Tenant scope filter missing on retrieve
- Why did verify fail? Truth T-03 (every endpoint scopes by empresa) was unmet.
- Why was it unmet? `retrieve()` was inherited from `ModelViewSet` without override.
- Why was it not overridden? PLAN.md task T-02 only listed `list()` — `retrieve()` not enumerated.
- Why was the task incomplete? Spec phase declared "list invoices" — retrieve was scope creep added during execute without plan amendment.
- Root cause: **PLAN.md did not enumerate every endpoint touched; executor implemented opportunistically.**

## Recovery Plan
1. `/release:plan 01 --gaps` — amend plan to enumerate retrieve, add tenant scope task.
2. `/release:execute 01 --gaps` — implement the gap-closure task only.
3. `/release:verify 01` — re-run goal-backward; expect T-03 → MET.
4. `/release:secure-phase 01` — retroactive security audit to confirm no drift.
5. `/release:ship 01` once PASS.

## Gaps & Caveats
- 02-PLAN.md exists but no commits found — phase 02 never executed; not a failure, just not-started.
- `.release-planning/STATE.md` lines older than 2026-05-23 not loaded (last-50-lines cap).
```

## Constraints

- Read-only on git, source, and `.release-planning/` (except writing the new report file).
- Never `git checkout`, `git reset`, `git revert`, or any mutating git command. `git log` /
  `git show` / `git diff` only.
- Never re-spawn auditor / reviewer agents — quote their existing reports verbatim.
- Single output file per invocation. Multiple runs accumulate in `forensics/` directory.
- If STATE.md is corrupt or unreadable, abort with a message pointing at `/release:status`.

## Example

```
/release:forensics

→ Loading STATE.md (last 50 lines)...
→ Most recent FAIL: phase 01, verdict BLOCK at 2026-05-24T10:03Z
→ Scope: phase 01-invoices-crud
→ Loading artifacts: PLAN.md, SUMMARY.md, VERIFICATION.md, REVIEW.md
→ Walking git log: 4 commits in phase window
→ Identifying failure surfaces: 2 (VERIFICATION BLOCK, REVIEW HIGH — correlated)
→ Building timeline: 7 events
→ Running 5-whys: 1 root cause (PLAN.md scope gap)
→ Drafting recovery plan: 5 steps

→ .release-planning/forensics/2026-05-25T14-30-12-report.md written

Next: review the recovery plan; start with /release:plan 01 --gaps
```
