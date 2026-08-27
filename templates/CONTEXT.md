<!--
# CONTEXT.md — Phase {NN}: {phase-slug}
#
# Legacy compatibility mirror. Existing files are read and updated by /release:plan.
# Locked decisions (D-XX) are NON-NEGOTIABLE — planner and executor honor every one.
-->

---
phase: {NN}
slug: {phase-slug}
created: {YYYY-MM-DDTHH:MM:SSZ}
status: discussed                # legacy value: discussed | planned | executing | complete
decisions_count: {N}
deferred_count: {N}
---

# Phase {NN} Context: {phase-name}

## Goal

{Restate the phase goal from ROADMAP.md. The outcome user observes when this phase ships.}

## Source Requirements

{List REQ-XX from REQUIREMENTS.md covered by this phase.}

- REQ-01: {one-liner}
- REQ-02: ...

---

## Decisions (LOCKED — non-negotiable)

These were chosen by the user before planning. Every PLAN.md task must implement them. Reference D-XX in task action for traceability. SPEC.md remains the source of truth.

### D-01: {Decision title}

**Question:** {What was asked.}

**Choice:** {What user chose.}

**Rationale:** {Why this choice. Cites constraint, prior incident, domain knowledge.}

**Impact on plan:**
- {Forces specific model field, e.g., "Veiculo.identificador must be UUIDField unique per tenant"}
- {Forces specific endpoint behavior, e.g., "POST /veiculos/bulk-import must accept CSV multipart"}
- {Forces specific test, e.g., "Race test required because saldo is mutated"}

### D-02: {Decision title}

...

### D-03: {Decision title}

...

---

## Deferred Ideas (NOT in this phase)

Ideas explicitly scoped OUT of this phase during clarification. Must NOT appear in PLAN.md tasks. May resurface in a future phase.

- **{Idea title}** — {one-line rationale why deferred}. Candidate for: Phase {YY}.
- ...

---

## Claude's Discretion

Areas where user accepted "Claude decides reasonably". Planner documents choice in task action.

- {Topic} — {how user described "use your judgment"}
- ...

---

## Open Risks (planning-level)

Risks discovered before planning that need monitoring during execute:

| Risk | Mitigation strategy | Owner |
|------|---------------------|-------|
| {Risk title} | {strategy} | {auto-handled by planner OR user check at verify time} |

---

## Out of Scope (this phase)

{Explicit list of what is NOT included. Different from Deferred — these may never happen, not just "later".}

- {Item}
- ...

---

_Legacy file: `/release:plan` mirrors newly settled D-XX here only when this file already exists._
