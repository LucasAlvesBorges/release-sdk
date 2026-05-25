<!--
# SPEC.md — Phase {NN}: {phase-slug}
#
# Stack-aware artifact between ROADMAP entry and CONTEXT.md.
# Use when WHAT the phase delivers is ambiguous and needs sharpening before /release:discuss.
# Produced by /release:spec, consumed by /release:discuss.
-->

---
phase: {NN}
slug: {phase-slug}
stack: {django | react | fullstack}
created: {YYYY-MM-DDTHH:MM:SSZ}
ambiguity_score: {HIGH | MED | LOW}
ready_for_discuss: false | true
---

# Phase {NN} Spec: {phase-name}

## Goal

{In one paragraph: what observable outcome does this phase deliver, for whom, and how do we know it's done?}

## Stack Detection

- **Detected:** {django | react | fullstack}
- **Signals:** {what files/keywords drove the detection — e.g., "manage.py present, ROADMAP goal mentions 'endpoint'"}
- **LOCK source:** {.planning/RELEASE-LOCKS.md or .planning/PROJECT.md}
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

Questions surfaced during `/release:spec`. Each becomes a discussion topic in `/release:discuss` → locked Decision D-XX in CONTEXT.md.

### HIGH (must resolve in /release:discuss)

{Answers fundamentally shape what gets built — scope-defining.}

1. {Question} — options: A {tradeoff}, B {tradeoff}; recommendation: {A or B or "user must decide"}
2. ...

### MED (should resolve in /release:discuss)

{Answers shape UX boundaries or behavior in edge cases.}

1. {Question}
2. ...

### LOW (Claude's discretion acceptable)

{Answers can default to reasonable choice if user shrugs.}

1. {Question} — default if not addressed: {reasonable default}
2. ...

## Ambiguity Score

- **LOW** (0-3 open questions, none HIGH) — spec is clear, `/release:discuss` will be brief.
- **MED** (4-6 open questions, ≤2 HIGH) — meaningful ambiguity, discuss covers 3-5 topics.
- **HIGH** (7+ open questions OR ≥3 HIGH) — spec is fuzzy. Consider splitting phase or running `/gsd-explore` first.

**This spec scores: {HIGH | MED | LOW}**

**Justification:** {Why this score — count of HIGH/MED/LOW questions, scope clarity, scope-creep risk.}

{If HIGH:} **Recommendation:** {Split phase into {NN}a/{NN}b, or run `/gsd-explore` before `/release:discuss`.}

## Next

→ `/release:discuss {NN}`  (lock D-XX decisions for HOW)

---

_Edit via `/release:spec {NN}` to re-run spec clarification. Proceed directly to `/release:discuss` if `ambiguity_score` is LOW._
