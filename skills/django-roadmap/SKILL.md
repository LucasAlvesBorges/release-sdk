---
description: >
  Create or refresh ROADMAP.md from PROJECT.md + REQUIREMENTS.md. Decomposes milestone into vertical-slice
  phases with goal, success_criteria, requirement coverage, dependencies. Audits REQ-XX coverage gaps.
  Use when: scoping new milestone, after adding requirements, re-prioritizing phases.
allowed_tools: Agent, Read, Write, Bash
---

# /django:roadmap — Build or Refresh ROADMAP.md

Decomposes the project into executable phases. Audits coverage. Surfaces gaps.

## Usage

```
/django:roadmap                  # full rebuild from REQUIREMENTS.md
/django:roadmap --audit          # check coverage only, don't rewrite
/django:roadmap --add-phase      # add a single phase interactively (alias: /django:phase add)
```

## Arguments

- `--audit` — report-only mode
- `--add-phase` — interactive single-phase addition
- `--milestone=v1.1` — start new milestone (archives v1.0 phases to ## Completed)

## Workflow

1. Read `.release-planning/PROJECT.md` (vision + LOCKs).
2. Read `.release-planning/REQUIREMENTS.md` (REQ-XX list).
3. Spawn `django-roadmapper` agent.
4. Roadmapper:
   - Decomposes REQ-XX into vertical-slice phases (NOT horizontal layers)
   - For each phase: goal, success_criteria, requirements_covered, depends_on, estimated_size (S/M/L)
   - Audits coverage: every REQ-XX covered by ≥1 phase, no orphan phases
   - Audits LOCK compliance for each phase
   - Estimates context cost (S <30%, M 30-50%, L 50-70% — L proposes split)
5. Writes `.release-planning/ROADMAP.md` (or appends if `--add-phase`).
6. Commits.

## Output

ROADMAP.md with:
- Numbered phases in dependency order
- Each phase: status, success criteria, requirements covered, depends_on, size
- Backlog (deferred ideas)
- Completed (archived from prior milestones)

## Phase status lifecycle

```
not-started → in-discuss → in-plan → in-execute → in-verify → complete
                                       ↓
                                  in-execute-gaps  (if verify finds failures)
                                       ↓
                                  in-plan-gaps    (if execute can't fix without replanning)
```

## Coverage audit (when --audit)

Returns:
```
Coverage: {N}/{total} REQs covered
Orphan phases: {none | list}
LOCK violations: {none | list}
Oversized phases (L): {none | list — recommend split}
```

## Example

```
/django:roadmap --audit

→ Reading REQUIREMENTS.md... 8 REQs found
→ Reading current ROADMAP.md... 5 phases

Coverage: 7/8 REQs covered
Uncovered: REQ-07 (Estorno workflow)
Orphan phases: none
LOCK violations: none
Oversized phases: Phase 03 (estimated L — 12 tasks, 18 files) — recommend split

Suggested actions:
- Add Phase 06 for REQ-07
- Split Phase 03 into 03a (model + serializer) + 03b (frontend + bulk)
```
