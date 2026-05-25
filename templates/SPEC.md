<!--
# SPEC.md — Phase {NN}: {phase-slug}
#
# Optional artifact between ROADMAP entry and CONTEXT.md.
# Use when WHAT the phase delivers is ambiguous and needs sharpening before /django:discuss.
# Produced by /django:spec, consumed by /django:discuss.
-->

---
phase: {NN}
slug: {phase-slug}
created: {YYYY-MM-DDTHH:MM:SSZ}
ambiguity_score: {0-10}           # higher = more clarification needed before plan
ready_for_discuss: false | true
---

# Phase {NN} Spec: {phase-name}

## Problem Statement

{In one paragraph: what observable problem does this phase solve, for whom, and how do we know it's solved?}

## Scope (what's in)

{Bulleted list of user-observable capabilities delivered by this phase.}

- {Capability 1} — user can {do thing} in {context}
- {Capability 2}
- ...

## Out of Scope (explicit exclusions)

{Bulleted list of related things this phase does NOT do. Surfaces scope-creep risk early.}

- {Thing} — deferred to Phase {YY} because {reason}
- {Thing} — not part of this product

## Acceptance Criteria

{Measurable assertions a UAT tester would check to declare phase done.}

- [ ] {Specific observable behavior 1}
- [ ] {Specific observable behavior 2}
- [ ] {Specific observable behavior 3}

## Constraints

{Non-negotiable boundaries this phase operates within. Map back to LOCK-XX in PROJECT.md.}

- LOCK-01: Backend is Django 5.2 + DRF 3.16 (cannot use different framework)
- LOCK-03: Multi-tenant — all data scoped by `empresa_id`
- LOCK-07: TDD — failing test before implementation
- {Phase-specific}: {e.g., "Must complete batch import of 10k rows in <30s"}

## Open Questions (need user decision in discuss)

{Numbered list. Each becomes a discussion topic in /django:discuss → decision D-XX in CONTEXT.md.}

1. {Question} — options: A {tradeoff}, B {tradeoff}, recommendation: {A or B}
2. {Question} — ...
3. ...

## Ambiguity Score

{0-3: spec is clear, discuss-phase is brief.}
{4-6: meaningful ambiguity, discuss covers 3-5 topics.}
{7-10: spec is fuzzy, consider splitting phase or running /django:explore first.}

**This spec scores: {N}**

**Justification:** {Why this score.}

---

_Edit via /django:spec to re-run spec clarification. Or proceed directly to /django:discuss if ambiguity_score ≤ 3._
