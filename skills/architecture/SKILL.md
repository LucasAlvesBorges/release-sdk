---
name: architecture
description: >
  Context-aware clean-code + scalability review for high-demand systems. Routes .py files and
  .tsx/.ts files to release:architecture-reviewer, which scores TWO dimensions — Clean Code &
  Structure (CC1-CC6: single-responsibility, complexity, DRY, coupling/layering, naming, abstraction
  fit) and Scalability & High-Demand (Django SD1-SD7: statelessness, caching, Celery offload,
  pagination, transaction/connection scope, bulk ops, index coverage / React SR1-SR6: code-splitting,
  list virtualization, data-fetch scaling, store granularity, asset weight, backend coupling) — with
  file:line evidence and a per-risk Scale Ceiling. Produces one unified ARCH-REVIEW.md. Cross-refs
  sibling gates (N+1 → checklist, race/TOCTOU → security A7, XSS/auth → security) instead of duplicating.
  Use when: designing for scale, pre-merge on a hot-path feature, refactor triage, or an architecture health check.
---

# /release:architecture — Clean Code + Scalability Review

Judges a feature on two axes at once: is it **clean** (maintainable) and does it **scale** (high-demand ready). Unified ARCH-REVIEW.md output. This is a DESIGN gate — it prefers a few systemic findings over a pile of micro-nits, and it is deliberately NON-duplicative: anything a sibling gate owns is emitted as a one-line pointer, not re-audited.

## Usage

```
/release:architecture 01                          # review phase 01 files
/release:architecture backend/apps/financeiro/    # Django-only review
/release:architecture src/features/Invoices/      # React-only review
/release:architecture --diff main..HEAD           # review changed files
/release:architecture 01 --deep                   # deeper pass (depth=deep)
```

## Routing logic

1. Resolve scope: phase directory, explicit paths, or git diff.
2. Split `.py` → Django dimensions, `.tsx/.ts` → React dimensions.
3. Spawn `release:architecture-reviewer` over the resolved scope with the detected `stack`.
   For `fullstack` scope it runs both dimension sets and merges into ONE ARCH-REVIEW.md.
4. Anchor Scale Ceilings to any demand targets stated in the phase SPEC / PROJECT.md
   (users, RPS, row counts). If none stated, ceilings are expressed relative to current size.

## Two dimensions scored

**A — Clean Code & Structure (both stacks)**
- CC1 Single responsibility / size — thin transport layer, logic in services/hooks
- CC2 Complexity & nesting
- CC3 Duplication (rule-of-three)
- CC4 Coupling & layering — domain vs transport vs presentation seams
- CC5 Naming & dead code
- CC6 Abstraction fit — catches BOTH primitive obsession and premature abstraction

**B — Scalability & High-Demand (stack-dispatched)**

Django (SD1-SD7):
1. Statelessness / horizontal scale (no process-local mutable state)
2. Caching strategy (cache-aside on hot reads + invalidation)
3. Heavy work offloaded to Celery (not synchronous in-request)
4. Pagination / bounded responses
5. Transaction & connection scope (no locks across IO; CONN_MAX_AGE)
6. Bulk operations (no per-row save in loops)
7. Index coverage on hot filters

React (SR1-SR6):
1. Code-splitting / bundle (lazy routes, no top-level heavy libs)
2. List virtualization for large datasets
3. Data-fetch scaling (no waterfalls; TanStack Query cache + pagination)
4. Store granularity / render fan-out (Zustand slice design, stable selectors)
5. Asset & payload weight
6. Backend-shape coupling at scale (adapter/Zod boundary)

## Scale Ceiling

The differentiator vs a linter: every ⚠️ RISK / ❌ BLOCKER on Dimension B carries a **Scale Ceiling** — the concrete load at which it starts to hurt (e.g. "OOM at ~50k rows", "worker starvation at ~30 concurrent report requests", "correctness breaks at ≥2 pods"). No ceiling → it is downgraded to a note.

## Cross-gate boundaries (NOT re-audited here)

| Signal | Owned by | Run |
|--------|----------|-----|
| N+1 (`select_related`/`prefetch_related`) | django-checklist-verifier Q1-Q4 | `/release:checklist` |
| Race / TOCTOU / idempotency | advanced-threat-auditor A7 | `/release:security` |
| Injection / authz / XSS / auth storage | security-auditor | `/release:security` |
| Micro render-memo / a11y / type-`any` | checklist RC1-RC7 | `/release:checklist` |

When one of these surfaces mid-review, ARCH-REVIEW.md lists a one-line pointer under **Cross-Gate Pointers** — it never opens a category for it. Run `/release:architecture` alongside `/release:checklist` + `/release:security` for full coverage.

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-ARCH-REVIEW.md
  frontmatter: clean_code_grade, scalability_grade, blockers, risks, status
  ## Scorecard                 (grades A-F per dimension)
  ## Dimension A — Clean Code & Structure   (CC1-CC6 table)
  ## Dimension B — Scalability & High-Demand (SD1-SD7 / SR1-SR6 table + Scale Ceiling)
  ## Blockers                  (fix before high-demand deploy — mechanism + fix)
  ## Risks                     (accepted debt — ceiling/cost + suggested fix)
  ## Cross-Gate Pointers       (run these sibling gates)
```

For a non-phase scope (explicit path / diff) the file is written to `./ARCH-REVIEW.md` unless a phase is resolved.

## Example

```
/release:architecture 01

→ Scope: FULLSTACK — Django: 3 (.py) · React: 4 (.tsx/.ts)
→ Demand anchor: PROJECT.md → "500 concurrent tenants, invoices table ~2M rows"

→ Dimension A (Clean Code)...
  CC1 (SRP): ⚠️ RISK — InvoiceViewSet.create() 80 LOC mixes pricing rules + email + PDF (views.py:44)
  CC4 (Coupling): ❌ BLOCKER — pricing logic duplicated in viewset AND serializer.validate() (3 sites)

→ Dimension B / Django (Scalability)...
  SD3 (Celery offload): ❌ BLOCKER — PDF built in-request; ceiling ~30 concurrent → worker starvation (views.py:61)
  SD4 (Pagination): ❌ BLOCKER — InvoiceListView has no pagination_class; ceiling ~2M rows OOM (views.py:20)
  SD6 (Bulk ops): ⚠️ RISK — per-row .save() in import loop; O(N) queries (services.py:112)

→ Dimension B / React (Scalability)...
  SR2 (Virtualization): ❌ BLOCKER — InvoiceTable .map() over full list, no windowing; jank ~5k rows (InvoiceTable.tsx:33)
  SR3 (Data-fetch): ⚠️ RISK — useEffect waterfall fetches client then invoices sequentially (useInvoices.ts:18)

→ Cross-Gate Pointers:
  N+1 at views.py:22 → /release:checklist
  TOCTOU on invoice number at services.py:88 → /release:security (A7)

→ ARCH-REVIEW.md written
   Clean Code: B · Scalability: D · 4 BLOCKER, 3 RISK · status: AT_RISK
```

---

## Stack dispatch

This skill spawns the merged `release:architecture-reviewer` agent. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. The agent applies the matching stack's scalability catalog (Django SD1-SD7 / React SR1-SR6); Dimension A (CC1-CC6) applies to both.
