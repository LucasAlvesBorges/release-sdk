---
name: ui-phase
description: Adaptive frontend design contract. Reuses established design-system patterns inline and delegates research/checking only for novel or high-risk UI.
---

# `/release:ui-phase`

Produce `{phase}-UI-SPEC.md` for a frontend/fullstack phase. Refuse backend-only phases.

## Usage

```text
/release:ui-phase [phase]
/release:ui-phase [phase] --research
/release:ui-phase [phase] --strict
/release:ui-phase [phase] --revise
```

## Flow

1. Resolve the phase and read SPEC/CONTEXT, locks, any prior UI-SPEC, relevant routes/components, and dependency/style manifests. Detect the existing design system, routing, forms, client/server state, and test conventions from those files only.
2. Reuse locked and incumbent patterns. Ask at most one batch of three questions only for choices that change interaction, content hierarchy, responsive behavior, or accessibility.
3. For C1/C2 work within an established system, write UI-SPEC inline. Include only affected routes/components; data contracts; loading/empty/error/success states; key interaction and validation; keyboard/focus/semantic behavior; responsive behavior; state ownership; and targeted tests.
4. Spawn `release:react-ui-researcher` only with `--research`, or for C3/C4 novel surfaces with unresolved design-system/interaction decisions. Pass paths and open decisions, not all planning documents.
5. Run deterministic checks inline: every affected async surface has states, interactive control has semantics/focus behavior, external data has a typed boundary, and route/state ownership is explicit.
6. Spawn `release:react-ui-checker` only with `--strict` or on C3/C4 after the inline checks. It audits triggered dimensions, not a universal matrix. Fix blocking omissions once and stop.

The planner consumes UI-SPEC directly. Do not create research/check artifacts for ordinary forms, tables, modals, or pages already covered by repository patterns.
