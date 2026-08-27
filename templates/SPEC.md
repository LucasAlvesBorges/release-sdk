<!--
# SPEC.md — Phase {NN}: {phase-slug}
#
# Stack-aware source of truth between ROADMAP and PLAN.
# Produced by /release:spec, completed by /release:plan's decision preflight.
-->

---
phase: {NN}
slug: {phase-slug}
stack: {django | react | fullstack}
created: {YYYY-MM-DDTHH:MM:SSZ}
ambiguity_score: {HIGH | MED | LOW}
status: ready | blocked
---

# Phase {NN} Spec: {phase-name}

## Goal

{In one paragraph: what observable outcome does this phase deliver, for whom, and how do we know it's done?}

## Stack Detection

- **Detected:** {django | react | fullstack}
- **Signals:** {what files/keywords drove the detection — e.g., "manage.py present, ROADMAP goal mentions 'endpoint'"}
- **LOCK source:** {.release-planning/RELEASE-LOCKS.md or .release-planning/PROJECT.md}
- **Applicable LOCKs:** {LOCK-01, LOCK-02, ...}

## Scope (in)

{Bulleted list of user-observable capabilities delivered by this phase.}

- {Capability 1} — user can {do thing} in {context}
- {Capability 2}
- ...

## Scope (out) — explicit exclusions

{Bulleted list of related things this phase does NOT do. Surfaces scope-creep risk early.}

- {Thing} — deferred to Phase {YY} because {reason}
- {Thing} — not part of this product

## Acceptance Criteria

{Measurable, observable assertions a UAT tester would check to declare phase done.}

- [ ] {Specific observable behavior 1}
- [ ] {Specific observable behavior 2}
- [ ] {Specific observable behavior 3}

## Constraints (from LOCKs)

{Non-negotiable boundaries this phase operates within. Map back to LOCK-XX in RELEASE-LOCKS.md / PROJECT.md.}

- LOCK-01: {e.g., Django 5.2 + DRF 3.16}
- LOCK-02: {e.g., Multi-tenant — `empresa_id` scoping}
- {Phase-specific constraint}: {e.g., "Must export 10k rows in <30s"}

## Open Questions

Questions surfaced by `/release:spec` or the `/release:plan` preflight. Each decision-changing answer
becomes a stable D-XX in this SPEC. Mirror it to CONTEXT.md only when that legacy file already exists.

### HIGH (must resolve before the planner runs)

{Answers fundamentally shape what gets built — scope-defining.}

1. {Question} — options: A {tradeoff}, B {tradeoff}; recommendation: {A or B or "user must decide"}
2. ...

### MED (resolve before planning when architecture, contract, risk or acceptance changes)

{Answers shape UX boundaries or behavior in edge cases.}

1. {Question}
2. ...

### LOW (Claude's discretion acceptable)

{Answers can default to reasonable choice if user shrugs.}

1. {Question} — default if not addressed: {reasonable default}
2. ...

## Ambiguity Score

- **LOW** (0-3 open questions, none decision-changing) — plan can use established patterns.
- **MED** (4-6 open questions, ≤2 HIGH) — plan asks only the decision-changing subset in batches of three.
- **HIGH** (7+ open questions OR ≥3 HIGH) — spec is fuzzy. Consider splitting phase or running `/gsd-explore` first.

**This spec scores: {HIGH | MED | LOW}**

**Justification:** {Why this score — count of HIGH/MED/LOW questions, scope clarity, scope-creep risk.}

{If HIGH:} **Recommendation:** {Split phase into {NN}a/{NN}b, or let `/release:plan` settle the
decision-changing questions before spawning the planner.}

## Next

→ `/release:plan {NN}`  (settle remaining gray areas, lock D-XX, then create an executable PLAN once)

---

_Edit scope via `/release:spec {NN}`. `/release:plan` always performs the final decision preflight
before writing or revising PLAN._
