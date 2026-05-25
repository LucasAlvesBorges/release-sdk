---
description: >
  Gather context for a phase before planning. Asks targeted questions across 10 dimensions
  (data shape, tenant scope, CRUD, permissions, concurrency, side effects, performance, integration,
  frontend, edge cases). Locks user answers as D-XX decisions in CONTEXT.md.
  Use when: phase added to ROADMAP, before /django:plan. NEVER skip this step.
allowed_tools: Agent, Read, Write, Bash, AskUserQuestion
---

# /django:discuss — Phase Context Discussion

Gathers phase decisions through adaptive questioning. Locks decisions as D-XX in `{NN}-CONTEXT.md`. Foundation for /django:plan.

## Usage

```
/django:discuss 01
/django:discuss 01 --resume        # continue interrupted discussion
/django:discuss 01 --replace       # discard prior CONTEXT.md and re-discuss
```

## Arguments

- `$ARGUMENTS` — phase number (required)
- `--resume` — continue if prior discussion interrupted
- `--replace` — re-run from scratch (with confirmation)

## Workflow

1. Read `.release-planning/ROADMAP.md` — find phase NN.
2. Read `.release-planning/PROJECT.md` — load LOCK-XX (not re-decideable).
3. Read `.release-planning/REQUIREMENTS.md` — find REQ-XX covered by this phase.
4. Read `{phase_dir}/{NN}-SPEC.md` if present (ambiguity reduction).
5. Spawn `django-discuss-orchestrator` agent.
6. Orchestrator:
   - Probes 10 dimensions (data shape, tenant, CRUD, permissions, concurrency, side effects, performance, integration, frontend, edges).
   - Asks N targeted questions via AskUserQuestion (batched where related).
   - Captures user choice + rationale per dimension.
   - Translates to Decisions D-XX.
   - Captures Deferred Ideas + Claude's Discretion areas + Open Risks.
7. Writes `{phase_dir}/{NN}-CONTEXT.md`.
8. Updates STATE.md cursor.
9. Commits: `docs({NN}): capture decisions from discuss-phase`.

## The 10 dimensions

1. **Data shape** — models, fields, FKs, uniqueness
2. **Tenant scope** — multi-tenant always; cross-tenant admin?
3. **CRUD shape** — list/retrieve/create/update/delete subset
4. **Permission model** — who creates, reads, modifies
5. **Concurrency** — numeric mutation? race-prone?
6. **Side effects** — Celery tasks, signals, histórico
7. **Performance** — bulk export? hot-read? Q1/Q7 active?
8. **External integration** — APIs, webhooks, uploads
9. **Frontend integration** — page? modal? reuse components
10. **Edge cases** — partial failure, retry, audit, soft delete

## What gets LOCKED

Each user answer → D-XX in CONTEXT.md with:
- Exact question
- User's choice (verbatim)
- User's rationale
- Impact on PLAN.md tasks

D-XX are NON-NEGOTIABLE. Planner + executor honor every one.

## Adaptive depth

- Trivial CRUD on simple model: 2-3 questions
- Medium domain feature: 4-6 questions
- Complex (financial, integration, race-prone): 7-10 questions

Orchestrator stops asking when:
- All 10 dimensions covered (locked OR discretion)
- User says "that's enough"
- Remaining ambiguity is low

## Example

```
/django:discuss 01

→ Reading ROADMAP... Phase 01 = veiculo-bulk-import
→ Reading PROJECT.md... LOCK-01 to LOCK-10 loaded
→ Reading REQUIREMENTS.md... covers REQ-02 (bulk import)

Spawning django-discuss-orchestrator...

Q1: "Bulk import accepts which formats?"
[ ] CSV only       (simplest, most universal)
[ ] CSV + Excel    (more flexible, slightly more code)
[ ] CSV + JSON     (programmatic clients)
> CSV only

  Why? > "Users have Excel but always export to CSV before importing — standard workflow"
  
  → D-01 locked: CSV-only multipart upload via POST /veiculos/bulk-import/

Q2: "Max file size?"
[ ] 1 MB
[ ] 10 MB (default)
[ ] 100 MB
> 10 MB

  → D-02 locked: file size limit 10 MB enforced server-side

... [more questions] ...

→ 6 decisions locked
→ 2 ideas deferred (preview mode, async processing — Phase 02 candidate)
→ 1 discretion area (CSV column ordering — Claude chooses)

→ Wrote .release-planning/phases/01-veiculo-bulk-import/01-CONTEXT.md
→ Committed: docs(01): capture decisions from discuss-phase

→ Next: /django:plan 01
```
