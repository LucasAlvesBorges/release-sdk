---
description: >
  Context-aware author checklist verification. Runs Q1-Q7 (Django) and/or RC1-RC7 (React)
  based on phase type. Grep-based PASS/FAIL/N-A per question. Produces CHECKLIST.md.
  Use when: after execute, before /release:verify, or as standalone quality gate.
allowed_tools: Agent, Read, Bash, Grep, Glob
---

# /release:checklist — Author Checklist Verification (Q1-Q7 + RC1-RC7)

Runs the correct checklist based on files in scope.

## Usage

```
/release:checklist 01                # auto-detect, run both if fullstack
/release:checklist 01 --backend      # Q1-Q7 only
/release:checklist 01 --frontend     # RC1-RC7 only
/release:checklist src/features/X/   # check specific React feature
/release:checklist backend/apps/X/   # check specific Django app
```

## Django Author Checklist (Q1-Q7)

Spawns `django-checklist-verifier` for:
- Q1: `select_related` on FK traversal
- Q2: `prefetch_related` on reverse-FK / M2M
- Q3: `.annotate(count=Count(...))` instead of Python-side count
- Q4: `Subquery`/`OuterRef` instead of N sub-queries
- Q5: `F()` or `select_for_update()` for numeric mutations
- Q6: `.delay_on_commit()` — never `.delay()` in production code
- Q7: `.iterator(chunk_size=...)` for large querysets

## React Author Checklist (RC1-RC7)

Spawns `release-test-auditor` + grep-based checks:
- RC1: `React.memo`, `useMemo`, `useCallback` where needed
- RC2: `isLoading`/`isError` guards in data-fetching components
- RC3: No `any` types; Zod schemas for API responses
- RC4: `aria-label` on interactive elements; semantic HTML
- RC5: Server state in TanStack Query, client state in Zustand
- RC6: No `localStorage`/`sessionStorage` for auth tokens
- RC7: Test files present and non-trivial (assert interactions)

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-CHECKLIST.md

---
phase: {NN}
backend_score: {N}/7
frontend_score: {N}/7
---

## Django Q1-Q7
| Q | Description | Verdict | Evidence |
|---|---|---|---|
| Q1 | select_related | ✅ PASS | views.py:34 |
| Q6 | delay_on_commit | ❌ FAIL | tasks.py:12 uses .delay() |

## React RC1-RC7
| RC | Description | Verdict | Evidence |
|----|---|---|---|
| RC1 | Render optimization | ✅ PASS | React.memo on InvoiceList |
| RC6 | Auth token storage | ✅ PASS | no localStorage.setItem(token) |
| RC7 | Test coverage | ⚠️ PARTIAL | InvoiceForm.tsx has no test file |

## Failures (require fix before merge)
Q6: .delay() used in tasks.py:12 — change to .delay_on_commit()
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
