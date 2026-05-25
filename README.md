# release-sdk

> Full-stack acceleration kit for Claude Code. Django + React TSX. No API key needed — uses your Claude subscription.

Context-aware `/release:*` commands route automatically to the right agents based on your files and ROADMAP. One SDK, two stacks.

---

## The big idea

**You define your architecture once. Every subsequent feature honors what you locked.**

1. `/release:init` — capture vision, lock backend + frontend stack, auth model, forbidden patterns → `PROJECT.md` (LOCK-01..LOCK-12)
2. `/release:roadmap` — decompose milestone into vertical-slice phases → `ROADMAP.md`
3. Per phase: `/release:discuss` → `/release:plan` → `/release:execute` → `/release:verify`
4. Decisions locked in `discuss` become D-XX in CONTEXT.md, referenced by every PLAN.md task, verified against the actual codebase

No silent assumptions. No "v1 / placeholder / will be wired later". No untraceable changes.

---

## Workflow at a glance

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ONCE PER PROJECT                                                         │
│  /release:init      →  PROJECT.md (LOCK-01..LOCK-12: backend + frontend)  │
│                     →  ROADMAP.md (phases)                                │
│                     →  REQUIREMENTS.md (REQ-XX)                           │
│                     →  STATE.md (cursor)                                  │
├──────────────────────────────────────────────────────────────────────────┤
│  PER PHASE                            backend        frontend             │
│  /release:discuss {NN}  →  CONTEXT.md (D-01..10)    (D-11..20)           │
│  /release:plan {NN}     →  PLAN.md or PLAN-BACKEND.md + PLAN-FRONTEND.md │
│  /release:execute {NN}  →  TDD: RED → GREEN → REFACTOR → SECURITY        │
│                            Django: pytest, ruff                           │
│                            React:  vitest, tsc                            │
│  /release:verify {NN}   →  VERIFICATION.md (PASS/GAPS_FOUND)             │
├──────────────────────────────────────────────────────────────────────────┤
│  QUALITY GATES (any time)                                                 │
│  /release:review        →  REVIEW.md (Django BLOCKERs + React BLOCKERs)  │
│  /release:security      →  SECURITY.md (9 categories × 2 stacks)         │
│  /release:checklist     →  CHECKLIST.md (Q1-Q7 + RC1-RC7)                │
│  /release:status        →  cursor + recent activity + next action         │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Context detection

Every `/release:*` command reads your ROADMAP phase goal and CONTEXT.md D-XX decisions, then routes to the correct pipeline:

| Phase signals | Classification | Pipeline |
|---|---|---|
| component, UI, React, page, form, screen | `frontend` | react-* agents |
| API, endpoint, model, serializer, migration | `backend` | django-* agents |
| Both signals present | `fullstack` | both pipelines, then integration check |

Override with `--backend`, `--frontend`, or `--fullstack` flags.

---

## What's inside

### Agents — Backend (Django)

| Agent | Role |
|---|---|
| `django-discuss-orchestrator` | 10-dimension questions → D-XX locked decisions |
| `django-roadmapper` | Decomposes milestone into vertical-slice phases |
| `django-feature-researcher` | Probes apps/, FK graph, migration state, patterns |
| `django-pattern-mapper` | Maps each new file to closest existing analog |
| `django-feature-planner` | Writes PLAN.md: TDD ordering + Q1-Q7 + 9 security |
| `django-plan-checker` | PLAN.md audit before execute (goal-backward + LOCK + Q1-Q7) |
| `django-tdd-executor` | RED → GREEN → REFACTOR → SECURITY, atomic commits |
| `django-phase-verifier` | Goal-backward verification — code delivers what PLAN promised? |
| `django-code-reviewer` | N+1, mass assignment, RLS bypass, .delay() vs .delay_on_commit() |
| `django-security-auditor` | 9-category audit (cross-tenant, IDOR, mass-assign, JWT, etc.) |
| `django-checklist-verifier` | Q1-Q7 grep-based PASS/FAIL/N-A |
| `django-test-auditor` | Coverage matrix: smoke + race + memray + 9 security |
| `django-debugger` | 10 Django bug shapes (N+1 lazy, migration drift, RLS thread-var, etc.) |
| `django-code-fixer` | Applies REVIEW.md fixes atomically, per-finding commits |

### Agents — Frontend (React TSX)

| Agent | Role |
|---|---|
| `react-feature-researcher` | Probes components, Zustand stores, TanStack Query keys, router |
| `react-pattern-mapper` | Maps each new file to closest existing React analog |
| `react-feature-planner` | Writes PLAN.md: TDD ordering + RC1-RC7 + 9 security categories |
| `react-tdd-executor` | RED → GREEN → REFACTOR → SECURITY, atomic commits |
| `react-phase-verifier` | Goal-backward: D-XX implemented? RC1-RC7 present? vitest + tsc clean? |
| `react-code-reviewer` | RC1-RC7 violations, stale closures, missing isLoading, any types, auth tokens |
| `react-security-auditor` | 9-category audit (XSS, auth storage, CSRF, IDOR, secrets, etc.) |
| `react-test-auditor` | Coverage map: unit + RTL + MSW + security + a11y |
| `react-debugger` | 10 React bug shapes (stale closure, infinite rerender, stale query, etc.) |
| `react-code-fixer` | Applies REVIEW.md fixes atomically, per-finding commits |

### Author Checklists

| Stack | Checklist | Questions |
|---|---|---|
| Django | Q1-Q7 | select_related, prefetch_related, annotate, Subquery, F()/select_for_update, delay_on_commit, iterator |
| React | RC1-RC7 | React.memo/useMemo/useCallback, isLoading/isError, TypeScript/Zod, accessibility, state discipline, auth token storage, test coverage |

### Slash commands

| Command | Stack | Purpose |
|---|---|---|
| `/release:init` | both | Initialize PROJECT.md (LOCK-01..LOCK-12) |
| `/release:spec {NN}` | both | Clarify WHAT phase delivers (SPEC.md, ambiguity score) |
| `/release:discuss {NN}` | both | Gather decisions (D-XX) for phase |
| `/release:plan {NN}` | both | Generate PLAN.md with checklists + security |
| `/release:ui-phase {NN}` | frontend | Produce UI-SPEC.md design contract (components, a11y, perf budgets) |
| `/release:ai-phase {NN}` | both | Produce AI-SPEC.md (LLM framework, prompts, eval, guardrails) |
| `/release:execute {NN}` | both | TDD-strict execution (pytest or vitest) |
| `/release:verify {NN}` | both | Goal-backward static verification |
| `/release:verify-work {NN}` | both | Conversational UAT walkthrough (UAT.md) |
| `/release:review` | both | Adversarial code review (REVIEW.md) |
| `/release:security` | both | 9-category security audit author-time (SECURITY.md) |
| `/release:secure-phase {NN}` | both | Retroactive threat-mitigation audit (scorecard) |
| `/release:checklist` | both | Q1-Q7 + RC1-RC7 verification |
| `/release:workstreams [sub]` | both | Manage parallel feature workstreams (list/create/switch/complete) |
| `/release:status` | both | Cursor + recent activity + next action |
| `/django:review` | backend | Django-only review |
| `/django:security` | backend | Django-only security audit |

### Hooks

| Hook | Event | Purpose |
|---|---|---|
| `django-validate-commit.sh` | PreToolUse:Bash | Conventional Commits enforcement (both stacks) |
| `django-workflow-guard.js` | PreToolUse:Write/Edit | TDD advisory — warns on Django core file edit without test |
| `django-tenant-scope-check.sh` | PreToolUse:Write/Edit | Warns when new Model skips TenantModel |
| `django-prompt-guard.js` | PreToolUse:Write/Edit | Scans .planning/ for prompt injection patterns |
| `react-workflow-guard.js` | PreToolUse:Write/Edit | TDD advisory — warns on React component edit without test |
| `react-security-guard.js` | PreToolUse:Write/Edit | Warns on localStorage token storage, dangerouslySetInnerHTML, eval |
| `release-read-injection-scanner.js` | PreToolUse:Read | Scans files read for prompt-injection patterns (ignore-previous, role overrides, hidden text) |
| `release-context-monitor.js` | PostToolUse:* | Tracks tool-call count; warns at 50/100/150 to summarize or `/release:pause-work` |

---

## 9 Security Categories

### Django (backend)
1. Cross-Tenant Isolation
2. Intra-Tenant IDOR
3. Vertical Privilege Escalation
4. Mass Assignment
5. JWT Lifecycle
6. Input Validation / Injection
7. Auth State Transitions
8. CSRF
9. Cookie / Token Security

### React (frontend)
1. XSS Prevention
2. Auth Token Storage (httpOnly cookies only — localStorage = BLOCKER)
3. CSRF (X-CSRFToken header)
4. Client-side IDOR
5. API Key / Secret Exposure
6. Content Injection (Markdown/rich text)
7. Prototype Pollution
8. Sensitive Data Logging
9. Input Validation (Zod schemas)

---

## Stack defaults

| Concern | Default |
|---|---|
| Backend | Django 5.2 LTS + DRF 3.16.x + Python 3.12 |
| Frontend | React 18 + Vite + TypeScript strict |
| Client state | Zustand |
| Server state | TanStack Query v5 |
| Forms | react-hook-form + zod |
| Frontend tests | Vitest + React Testing Library + MSW |
| API mocks (tests) | MSW v2 |
| Backend tests | pytest + pytest-django + factory-boy |
| Auth | JWT httpOnly cookie + X-CSRFToken header |
| Multi-tenancy | empresa_id via django-rls + TenantModel |

---

## Install

### Marketplace (recommended)

```
/plugin marketplace add LucasAlvesBorges/release-sdk
/plugin install release-sdk@release-sdk
```

Then restart Claude Code.

### Local clone (recommended for dev)

```bash
git clone https://github.com/lucasalvesborges/release-sdk ~/.claude/plugins/release-sdk
# Restart Claude Code
```

### Symlink (live dev)

```bash
ln -s ~/release/personal/django-sdk ~/.claude/plugins/release-sdk
```

---

## Quick start — fullstack project

```bash
cd ~/my-project

# 1. Initialize
/release:init
  # → asks: backend stack, frontend stack, auth model, multi-tenant, forbidden patterns
  # → produces: PROJECT.md (LOCK-01..LOCK-12) + ROADMAP.md + STATE.md + REQUIREMENTS.md

# 2. Scope first phase
/release:phase add "Invoice list page with filter and CSV export"
  # → adds Phase 01 to ROADMAP, creates phase directory

# 3. Discuss — Django + React questions
/release:discuss 01
  # → backend: API contract, tenant scope, ORM strategy
  # → frontend: component structure, Zustand slice, TanStack Query key, Zod schema
  # → locks D-01..D-22 in CONTEXT.md

# 4. Plan both sides
/release:plan 01
  # → detects: FULLSTACK
  # → backend: PLAN-BACKEND.md (pytest TDD, Q1-Q7, 9 security)
  # → frontend: PLAN-FRONTEND.md (vitest TDD, RC1-RC7, 9 security)
  # → integration check: serializer fields ↔ Zod schema aligned?

# 5. Execute backend first (API before UI)
/release:execute 01 --backend
  # → RED → GREEN → REFACTOR → SECURITY
  # → pytest + ruff gated per commit

# 6. Execute frontend
/release:execute 01 --frontend
  # → RED → GREEN → REFACTOR → SECURITY
  # → vitest + tsc gated per commit

# 7. Verify both
/release:verify 01
  # → backend: every D-XX in code? Q1-Q7 present? 9/9 security?
  # → frontend: every D-XX in code? RC1-RC7 present? vitest/tsc clean? no localStorage?
  # → VERIFICATION.md: PASS or GAPS_FOUND

# 8. Quality gates
/release:review 01       # adversarial review — Django + React unified REVIEW.md
/release:security 01     # 9-category × 2 stacks
/release:checklist 01    # Q1-Q7 + RC1-RC7 grep
```

---

## Planning artifacts

```
.planning/
├── PROJECT.md                              # LOCK-01..LOCK-12 (immutable)
├── ROADMAP.md                              # phase list
├── REQUIREMENTS.md                         # REQ-XX
├── STATE.md                                # cursor
└── phases/
    └── {NN}-{slug}/
        ├── {NN}-CONTEXT.md                 # discuss output (D-XX backend + frontend)
        ├── {NN}-RESEARCH.md                # researcher output (single-stack)
        ├── {NN}-PLAN.md                    # planner output (single-stack)
        ├── {NN}-PLAN-BACKEND.md            # (fullstack: Django side)
        ├── {NN}-PLAN-FRONTEND.md           # (fullstack: React side)
        ├── {NN}-PLAN-CHECK.md              # plan-checker verdict (Django)
        ├── {NN}-PATTERNS.md                # pattern-mapper output
        ├── {NN}-SUMMARY.md                 # execute output
        ├── {NN}-CHECKLIST.md               # Q1-Q7 + RC1-RC7
        ├── {NN}-SECURITY.md                # security audit
        ├── {NN}-TEST-AUDIT.md              # test coverage map
        └── {NN}-VERIFICATION.md            # verify output
```

---

## Why this exists

Most AI coding tools let you ship features fast. Few let you ship features that honor what you decided yesterday.

**The problem:**
- You discuss architecture with Claude → Claude proposes solution → you say "yes"
- Next session, Claude forgets, proposes different solution, you accept again
- After 10 features: 4 auth patterns, 3 state management approaches, 2 API naming conventions

**release-sdk's solution:**
- Every architectural choice locked as LOCK-XX (project) or D-XX (phase) in Markdown
- Every planner, executor, verifier reads those locks before writing code
- Verifier confirms locks are in actual code, not just narrative
- Hooks warn on violations before they're committed

This is GSD methodology, specialized for Django + React full-stack engineering.

---

## Reference

GSD (`get-shit-done`) methodology by Brennan Hughes.

- GSD: https://github.com/brennanhughes/get-shit-done
- release-sdk: https://github.com/lucasalvesborges/release-sdk

---

## Compatibility

- Django 5.2 LTS (4.x with minor adaptation)
- DRF 3.16.x
- Python 3.12+
- React 18 + TypeScript 5.x
- Vite 5.x / Next.js 14+
- Claude Code 2.x+

---

## License

MIT
