---
description: >
  Plan a Django feature phase. Reads CONTEXT.md (locked D-XX decisions), spawns researcher + pattern-mapper
  + planner sequentially, produces PLAN.md with Q1-Q7 embedded + 9 security tests + TDD ordering, runs
  plan-checker to verify before execute. Writes to .planning/phases/{NN}-{slug}/.
  Use when: phase has been discussed (CONTEXT.md exists), ready to plan tasks.
allowed_tools: Agent, Read, Write, Bash, Grep, Glob
---

# /django:plan — Phase Planning with Q1-Q7 + Security Matrix

Plans a Django feature phase. Honors locked D-XX decisions from CONTEXT.md. TDD task ordering. Q1-Q7 per task. 9-category security coverage. Plan-checker verifies before execute.

## Usage

```
/django:plan 01                      # plan phase 01 (CONTEXT.md must exist)
/django:plan 01 --gaps               # plan fix for gaps from VERIFICATION.md
/django:plan 01 --revise             # revise existing PLAN.md after plan-checker BLOCK
/django:plan 01 --skip-research      # skip researcher (only if RESEARCH.md already current)
/django:plan 01 --skip-patterns      # skip pattern-mapper
```

## Arguments

- `$ARGUMENTS` — phase number (required)
- `--gaps` — gap-closure mode (reads VERIFICATION.md `gaps:`)
- `--revise` — revision mode (reads existing PLAN-CHECK.md `blockers`)
- `--skip-research` / `--skip-patterns` — skip optional pre-steps

## Prerequisites

- `.planning/phases/{NN}-{slug}/{NN}-CONTEXT.md` must exist (run `/django:discuss {NN}` first)
- `.planning/PROJECT.md` must exist with LOCK-XX
- `.planning/ROADMAP.md` must contain Phase NN entry

## Workflow

1. Load context:
   - `.planning/PROJECT.md` (LOCK-XX)
   - `.planning/ROADMAP.md` (phase goal + success_criteria)
   - `.planning/phases/{NN}-{slug}/{NN}-CONTEXT.md` (D-XX locked decisions)
2. **Optional pre-step:** Spawn `release-feature-researcher` → `{NN}-RESEARCH.md`
   - Probes affected apps, FK graph, existing patterns, migration state, risks
3. **Optional pre-step:** Spawn `release-pattern-mapper` → `{NN}-PATTERNS.md`
   - Maps each intended file to closest existing analog
4. Spawn `release-feature-planner` with all artifacts → `{NN}-PLAN.md`
   - TDD ordering (RED → GREEN → REFACTOR → SECURITY → conditional RACE/MEMRAY)
   - Each task: files, action (referencing D-XX), author_checklist (Q1-Q7), done_when
   - frontmatter: must_haves (truths + artifacts + key_links), threat_model (9 categories)
5. Spawn `django-plan-checker` → `{NN}-PLAN-CHECK.md`
   - Audits goal-backward coverage, decision coverage, LOCK compliance, Q1-Q7 consistency, security matrix
   - Verdict: PASS / WARN / BLOCK
6. If BLOCK: report blockers, suggest re-run `/django:plan {NN} --revise`
7. If PASS or WARN: commit all artifacts
8. Update STATE.md cursor: `active_stage: plan-complete`

## TDD task ordering enforced

```
T01 — RED:       tests/test_{feature}.py (failing)        test({app}): add failing tests
T02 — GREEN:     models.py + migration                    feat({app}): add Model
T03 — GREEN:     serializer + view + URL                  feat({app}): implement CRUD
T04 — REFACTOR:  apply Q1-Q7 optimizations                refactor({app}): apply Q1-Q7
T05 — SECURITY:  9-category test file                     test({app}): add security tests
T06 (conditional) RACE if Q5 active                       test({app}): add race test
T07 (conditional) MEMRAY if Q7 active                     test({app}): add memray test
```

## Output files

```
.planning/phases/{NN}-{slug}/
  {NN}-RESEARCH.md       # researcher (optional)
  {NN}-PATTERNS.md       # pattern-mapper (optional)
  {NN}-PLAN.md           # planner
  {NN}-PLAN-CHECK.md     # plan-checker verdict
```

## Example

```
/django:plan 01

→ Reading PROJECT.md (LOCK-01 to LOCK-10)
→ Reading ROADMAP Phase 01: veiculo-bulk-import
→ Reading CONTEXT.md (6 decisions D-01 to D-06)

→ Spawning release-feature-researcher...
  RESEARCH.md created
  Primary app: frota
  Related models: Veiculo, Garagem, Empresa
  Q5 active: NO (no numeric mutation in bulk import)
  Q7 active: YES (bulk processing >1k rows possible)

→ Spawning release-pattern-mapper...
  PATTERNS.md created
  Closest analog: backend/apps/frota/views.py::VeiculoViewSet
  Novel files: 1 (CSV parser service — first in this app)

→ Spawning release-feature-planner...
  PLAN.md created with 7 tasks (T01-T07)
  Q1: select_related ['empresa', 'garagem'] (per D-01)
  Q6: chunk processing via .delay_on_commit (per D-05)
  Q7: iterator(chunk_size=500) (per D-04, T07 memray test)
  Security matrix: 9/9 mapped to T05

→ Spawning django-plan-checker...
  PLAN-CHECK.md created
  Verdict: PASS
  Audit: 5/5 truths covered, 6/6 D-XX referenced, 9/9 security mapped, Q1-Q7 consistent

→ Committed: docs(01): plan veiculo-bulk-import (7 tasks, plan-checker PASS)

→ Next: /django:execute 01
```


---

## Stack dispatch

This skill spawns merged `release-*` agents (one agent per role, dispatched internally by `stack`). All agent spawns from this skill pass `stack: django` as input. The agents apply Django-stack rules from their `<django-stack>` blocks.
