<!--
# ROADMAP.md template
# List of phases ordered by execution. Each phase has goal, status, success_criteria.
# Source of truth for "what's next".
-->

# Roadmap — {Project Name}

**Milestone:** {v1.0 | v1.1 | etc}
**Updated:** {YYYY-MM-DD}

---

## Phases

### Phase 01 — {phase-slug}

**Goal:** {One-line outcome user observes when this phase ships.}

**Status:** `not-started` | `in-discuss` | `in-plan` | `in-execute` | `in-verify` | `complete`

**Success Criteria:**
- [ ] {Measurable truth #1}
- [ ] {Measurable truth #2}
- [ ] {Measurable truth #3}

**Requirements covered:** REQ-01, REQ-02, REQ-03

**Depends on:** {none | Phase XX}

**Estimated context cost:** {S | M | L} (small <30% context, medium 30-50%, large needs splitting)

---

### Phase 02 — {phase-slug}

**Goal:** ...

**Status:** `not-started`

**Success Criteria:**
- [ ] ...

**Depends on:** Phase 01

---

### Phase 03 — {phase-slug}

...

---

## Backlog (deferred — not yet scheduled)

- {Idea title} — {one-line rationale why deferred}
- ...

---

## Completed (archive)

- ✓ Phase 00 — foundation — completed {YYYY-MM-DD} — {commit-hash}

---

_Edit via `/django:phase add|insert|remove|edit` or directly in this file. Update STATE.md cursor when phase status changes._
