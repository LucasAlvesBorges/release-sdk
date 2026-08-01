<!--
# UI-SPEC.md — Phase {NN}: {phase-slug}
#
# Produced by /release:ui-phase (release-ui-researcher) BEFORE any test/component is written.
# Read by /release:plan --react (react-feature-planner) as the locked design contract.
# Every UI-DEC-XX below is NON-NEGOTIABLE — TDD tasks must honor each one verbatim.
#
# Edit only via `/release:ui-phase {NN} --revise`. Manual edits risk de-syncing PLAN-FRONTEND.md.
-->

---
phase: {NN}
slug: {phase-slug}
created: {YYYY-MM-DDTHH:MM:SSZ}
stack: react-tsx
generator: release-ui-researcher
locks_honored:
  - LOCK-07  # React stack
  - LOCK-08  # state management
  - LOCK-09  # auth storage
  - LOCK-10  # type safety
  - LOCK-11  # test framework
  - LOCK-12  # API contract (snake_case↔camelCase)
context_decisions_honored:
  - D-11
  - D-12
  - D-13
ui_decisions_count: {N}
open_questions_count: {N}
design_system_fingerprint:
  routing: {react-router-v6 | tanstack-router | next-app}
  styling: {tailwind | tailwind+shadcn | mui | chakra | mantine | custom}
  state_client: {zustand | redux | jotai | context}
  state_server: {tanstack-query-v5 | swr | custom}
  forms: {react-hook-form+zod | formik | native}
  tests: {vitest+rtl+msw | jest+rtl}
gsd_context: false   # true if produced under /release:ui-phase --gsd-context
---

# UI-SPEC — Phase {NN}: {phase-name}

> **Design contract.** Produced before TDD. Every component, route, state, a11y attribute,
> and perf target below is the source of truth for `react-feature-planner` and
> `react-tdd-executor`. UI-DEC-XX entries are immutable downstream.

---

## Overview

**Goal (from ROADMAP.md):**
{One-line restatement of the phase goal — the user-observable outcome.}

**User stories covered (from SPEC.md):**
- US-01: {short title}
- US-02: ...

**Decisions inherited (from CONTEXT.md):**
- D-11: {decision title} — {one-line}
- D-12: ...

**Locks honored (from RELEASE-LOCKS.md / PROJECT.md):**
- LOCK-07: {value, e.g., React 18 + Vite + TypeScript strict}
- LOCK-08: {value, e.g., Zustand + TanStack Query v5}
- LOCK-09: {value, e.g., httpOnly cookie only; localStorage tokens = BLOCKER}
- LOCK-10: {value, e.g., no `any`, Zod for API responses}
- LOCK-11: {value, e.g., Vitest + RTL + MSW}
- LOCK-12: {value, e.g., snake_case backend, camelCase frontend via Axios interceptor}

---

## Stack Detection

Detected on disk during `/release:ui-phase`. Source of truth for tokens, primitives, and forbidden imports.

| Layer | Detected | Source | Status |
|---|---|---|---|
| Routing | {value} | `package.json` / `src/router.tsx` | EXTRACTED / INFERRED / MISSING |
| Styling — utility | {tailwind / none} | `tailwind.config.ts` | EXTRACTED / MISSING |
| Styling — components | {shadcn / MUI / chakra / custom} | `components.json` / `package.json` | EXTRACTED / MISSING |
| Design tokens | {`src/theme.ts` / tailwind theme / MUI theme} | file path | EXTRACTED / MISSING |
| Client state | {zustand / ...} | `package.json` + `src/stores/` | EXTRACTED / INFERRED |
| Server state | {TanStack Query v5 / ...} | `package.json` + `src/hooks/` | EXTRACTED |
| Forms | {react-hook-form+zod / ...} | `package.json` + analog form file | EXTRACTED |
| Tests | {Vitest + RTL + MSW / ...} | `vitest.config.ts` / `package.json` | EXTRACTED |
| Animation | {framer-motion / none} | `package.json` | EXTRACTED / MISSING |
| Icons | {lucide-react / @heroicons / ...} | `package.json` | EXTRACTED / MISSING |

**Forbidden imports (LOCK-driven):**
- No `localStorage.setItem('token', ...)` — LOCK-09 violation = BLOCKER
- No `any` type — LOCK-10 violation = BLOCKER
- No untyped API response (must go through Zod schema) — LOCK-10 violation = BLOCKER

---

## Component Inventory

Components touched or created by this phase. **`react-feature-planner` must produce one TDD
task per `NEW` row.**

| ID | Component | Path | Status | Source / Analog | Props (high-level) |
|---|---|---|---|---|---|
| C-01 | `InvoiceListPage` | `src/features/Invoice/InvoiceListPage.tsx` | NEW | analog: `src/features/Order/OrderListPage.tsx` | none (route component) |
| C-02 | `InvoiceTable` | `src/features/Invoice/InvoiceTable.tsx` | NEW | analog: `src/features/Order/OrderTable.tsx` | `invoices: Invoice[]`, `onRowClick` |
| C-03 | `InvoiceFilterBar` | `src/features/Invoice/InvoiceFilterBar.tsx` | NEW | analog: `OrderFilterBar` | `filters`, `onChange` |
| C-04 | `Skeleton` | `src/components/ui/Skeleton.tsx` | REUSE | shadcn primitive | n/a |
| C-05 | `EmptyState` | `src/components/EmptyState.tsx` | REUSE | existing | `title`, `cta` |
| ... | ... | ... | ... | ... | ... |

### UI-DEC-01..09 — Composition decisions

#### UI-DEC-01: {title}
**Dimension:** Component inventory
**Source:** {RESEARCH-FRONTEND.md § X / D-11 / user choice}
**Decision:** {verbatim}
**Rationale:** {one-line}
**Impact on plan:**
- {forces task to create file Y}
- {forces RTL test for prop Z}

#### UI-DEC-02: ...

---

## Routes & Navigation

| Route | Component | Auth wrapper | Status | Source |
|---|---|---|---|---|
| `/invoices` | `InvoiceListPage` | `<ProtectedRoute>` | NEW | UI-DEC-10 |
| `/invoices/:id` | `InvoiceDetailPage` | `<ProtectedRoute>` | NEW | UI-DEC-10 |

**Nav surface impact:**
- Sidebar: add link "Invoices" under group "Finance"
- Breadcrumb: `Finance / Invoices / {invoice.number}`
- Deep-link share: route `/invoices?status=overdue` must round-trip filters via URLSearchParams

### UI-DEC-10..19 — Routing & navigation decisions

#### UI-DEC-10: New routes under <ProtectedRoute>
**Dimension:** Routing
**Source:** RESEARCH-FRONTEND.md (analog `OrderListPage` uses `<ProtectedRoute>`)
**Decision:** Both `/invoices` and `/invoices/:id` wrap with `<ProtectedRoute>` (auth-required).
**Rationale:** Mirrors existing auth-gated finance routes.
**Impact on plan:**
- `src/router.tsx` update task (T-XX)
- RTL test: unauthenticated user redirects to `/login`

#### UI-DEC-11: ...

---

## State Contracts

Every async surface MUST define behavior for all four states. Missing any state = BLOCKER at
`react-code-reviewer`.

| Surface | Loading | Empty | Error | Success |
|---|---|---|---|---|
| `InvoiceTable` (initial fetch) | `<Skeleton rows={10} />` | `<EmptyState title="No invoices yet" cta="Create invoice" />` | inline error banner + retry button | render rows |
| `InvoiceTable` (filter applied → 0 rows) | (n/a — instant after cache) | `<EmptyState title="No matches" cta="Clear filters" />` | (same) | (same) |
| `bulk-archive` mutation | button spinner; row opacity 0.5 | n/a | toast.error + rollback | toast.success + invalidate query |
| `csv-export` mutation | button spinner; disable button | n/a | toast.error | toast.success("Export queued") |

### TanStack Query patterns

| Hook | Query Key | staleTime | gcTime | Notes |
|---|---|---|---|---|
| `useInvoices(filters)` | `['invoices', 'list', filters]` | 60_000 | 5*60_000 | invalidate on bulk-archive success |
| `useInvoice(id)` | `['invoices', 'detail', id]` | 60_000 | 5*60_000 | prefetch on row hover |

### Zustand slices

| Slice | New? | Path | Shape | Actions |
|---|---|---|---|---|
| `invoiceUiStore` | NEW | `src/stores/invoiceUiStore.ts` | `{ selectedIds: string[], filters: InvoiceFilters }` | `setFilters`, `toggleSelect`, `clearSelection` |

(Server state stays in TanStack Query — **never** mirror server data into Zustand.)

### UI-DEC-20..29 — State contracts

#### UI-DEC-20: Skeleton primitive for loading
**Dimension:** Loading state
**Source:** Design system probe — shadcn Skeleton present at `src/components/ui/skeleton.tsx`.
**Decision:** Use shadcn `<Skeleton />` × 10 rows for InvoiceTable loading.
**Impact on plan:**
- T-XX: RTL test for skeleton render when `isLoading === true`

#### UI-DEC-21: ...

---

## A11y Contract

Target: **WCAG 2.1 Level AA**. (Set to AAA via UI-DEC-30 if user requested.)

### Keyboard map

| Surface | Key | Behavior |
|---|---|---|
| `InvoiceTable` rows | `Tab` | move focus through rows |
| `InvoiceTable` rows | `ArrowDown` / `ArrowUp` | move row focus |
| `InvoiceTable` row | `Enter` | navigate to detail |
| `InvoiceTable` row | `Space` | toggle select (bulk mode) |
| `InvoiceFilterBar` | `Tab` | each control reachable in left-to-right reading order |
| `Modal` (any) | `Escape` | close & return focus to trigger |

### ARIA / semantics

| Element | Role / attribute | Notes |
|---|---|---|
| `<table>` for invoices | native `<table>` with `<caption>` | screen reader friendly |
| Selectable rows | `aria-selected` | mirrors Zustand `selectedIds` |
| Filter section | `<section aria-labelledby="filters-heading">` | landmark |
| Live region (toast) | `role="status"` `aria-live="polite"` | success messages |
| Live region (error) | `role="alert"` `aria-live="assertive"` | error messages |

### Contrast

- Body text vs background: AA (4.5:1) — verify via design tokens, NOT eyeballed.
- Disabled state contrast: AA (3:1) for non-text UI components.

### UI-DEC-30..39 — A11y decisions

#### UI-DEC-30: WCAG 2.1 AA target
**Source:** {global standard / user choice}
**Impact on plan:**
- T-XX: axe-core test wired into Vitest config
- T-XX: every interactive element receives accessible name

#### UI-DEC-31: ...

---

## Performance Budgets

Enforced via Lighthouse CI (`@lhci/cli`) in `pnpm run perf` AND `vite-bundle-visualizer` for
bundle delta. Misses = WARN at planner, BLOCKER at `react-phase-verifier`.

| Metric | Target | Measured at |
|---|---|---|
| LCP (Largest Contentful Paint) | ≤ {1500}ms on 3G Fast | Lighthouse `/invoices` |
| TTI (Time to Interactive) | ≤ {3000}ms on 3G Fast | Lighthouse `/invoices` |
| INP (Interaction to Next Paint) | ≤ {200}ms | Lighthouse |
| Bundle delta (gzipped) | ≤ {30}kb on this phase | `vite-bundle-visualizer` diff |
| TanStack staleTime | {60_000}ms | runtime contract |
| Image strategy | lazy + `<img loading="lazy">` | code review |
| Code-split route | YES — `React.lazy(() => import('./InvoiceListPage'))` | router |

### UI-DEC-40..49 — Performance decisions

#### UI-DEC-40: Code-split InvoiceListPage
**Source:** Bundle delta budget UI-DEC-43 forces split.
**Impact on plan:** router task uses `React.lazy` + `<Suspense fallback={<Skeleton />}>`.

#### UI-DEC-41: ...

---

## Optimistic UI Plan

Per-mutation: declare optimistic behavior or explicitly opt out.

| Mutation | Optimistic? | Strategy | Rollback |
|---|---|---|---|
| `bulk-archive` | YES | `onMutate`: snapshot query data, remove archived rows from cache | `onError`: restore snapshot + toast.error |
| `csv-export` | NO | server returns task ID; client polls | n/a (long-running) |
| `update-status` (inline cell edit) | YES | `onMutate`: patch row in cache | `onError`: restore + inline cell flash red |

### UI-DEC-50..59 — Optimistic decisions

#### UI-DEC-50: Optimistic bulk-archive with rollback toast
**Source:** User choice via AskUserQuestion.
**Decision:** `onMutate` removes rows immediately. `onError` restores + `toast.error("Couldn't archive. Restored.")`.
**Impact on plan:**
- T-XX: TanStack `useMutation({ onMutate, onError, onSettled })` wired correctly
- T-XX: RTL test simulates 500 response → rows restored + toast asserted

#### UI-DEC-51: ...

---

## Open Questions

Items still ambiguous after AskUserQuestion. These BLOCK `/release:plan --react` if any are
critical-path. Re-run `/release:ui-phase {NN} --revise` once answered.

| ID | Question | Why open | Impact if unresolved |
|---|---|---|---|
| OQ-01 | {Should bulk-archive emit a desktop notification on success?} | not addressed in SPEC.md, user said "decide later" | minor UX gap |
| OQ-02 | ... | ... | ... |

---

## Out of Scope (this phase)

Explicit non-goals. **`react-feature-planner` must NOT add tasks for these.**

- Inline editing of multiple cells (single-cell edit only — UI-DEC-XX)
- Mobile breakpoint optimization (desktop-first this phase; mobile in Phase {YY})
- Real-time updates via WebSocket (poll-on-focus only)

---

## Verification map (for `react-phase-verifier`)

Every UI-DEC-XX above is verifiable. The verifier should grep for:

- Each NEW component path exists and has a co-located `.test.tsx`
- Each state in the State Contracts table has an RTL assertion
- Each ARIA attribute appears in markup
- Each performance metric has a CI gate or budget assertion
- Each optimistic mutation has `onMutate` + `onError` in the hook source

---

## Next

```
/release:plan {NN} --react
```

This will spawn `react-feature-planner` with `UI-SPEC.md` as a required reading. Every TDD
task in `{NN}-PLAN-FRONTEND.md` must cite the UI-DEC-XX it implements.

---

_Generated by `release-ui-researcher` (release-sdk). Edit only via `/release:ui-phase {NN} --revise`._
