# release-sdk

> Full-stack acceleration kit for Claude Code. Django + React TSX. No API key needed — uses your Claude subscription.

> 🇧🇷 [Versão em português](./README.md) is the primary README. This file is the English mirror.

Context-aware `/release:*` commands route automatically to the right agents based on your files and ROADMAP. One SDK, two stacks.

**Entry point:** `/release:auto <plain-language intent>` — 32-rule router that dispatches to the right `/release:*` skill, prints the chosen route + reason before invoking, falls back to `AskUserQuestion` on low confidence.

**Current version: v0.9.1** — short `/release:*` invocation, 39 skills, 38 agents (taxonomy: `release-*` merged stack-dispatched, `django-*` Django-pure, `react-*` React-pure). See [CHANGELOG.md](./CHANGELOG.md) for the full evolution.

---

## The big idea

**You define your architecture once. Every subsequent feature honors what you locked.**

1. `/release:init` — capture vision, lock backend + frontend stack, auth model, forbidden patterns → `PROJECT.md` (LOCK-01..LOCK-12)
2. `/release:roadmap` — decompose milestone into vertical-slice phases → `ROADMAP.md`
3. Per phase: `/release:discuss` → `/release:plan` → `/release:execute` → `/release:verify`
4. Decisions locked in `discuss` become D-XX in CONTEXT.md, referenced by every PLAN.md task, verified against the actual codebase

No silent assumptions. No "v1 / placeholder / will be wired later". No untraceable changes.

---

## What's new (v0.5 → v0.7)

- **v0.7.0** — 31 new files (20 agents + 11 skills) closing the gap audit vs upstream GSD. `/release:auto` routing extended from 21 to 32 rules. Highlights: `/release:autonomous` (walk-away multi-phase), `/release:audit-fix` (autonomous audit-to-fix loop), `/release:validate-phase` (Nyquist coverage), `/release:ui-review` (6-pillar visual audit), `/release:eval-review` (AI eval coverage), `/release:docs-update` (verified docs regen), `/release:forensics` (post-mortems), `release-plan-checker` (pre-execute goal-backward verifier), `release-assumptions-analyzer` (deep codebase analysis for discuss), `release-debug-session-manager` (multi-cycle debug in isolated context), `release-framework-selector` (AI framework decision matrix), and the full `release-doc-*` family.
- **v0.6.1** — `/release:init` and `/release:import` now inject a delimited `<!-- release-sdk:start --> ... <!-- release-sdk:end -->` block into repo-root `CLAUDE.md` so every future Claude Code session knows release-sdk is installed and where artifacts live. Idempotent.
- **v0.6.0** — `/release:auto` (freeform-intent router) + native `/release:debug`, `/release:fast`, `/release:quick`, `/release:ship` so routing stays inside the `/release:*` namespace.
- **v0.5.0** — BREAKING: planning directory renamed `.planning/` → `.release-planning/` to coexist with upstream GSD (which also uses `.planning/`). `/release:import` is the bridge: reads GSD `.planning/` (untouched) and writes release-sdk artifacts to a parallel `.release-planning/` tree.

See [CHANGELOG.md](./CHANGELOG.md) for the full evolution.

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

### Agents — Stack-dispatched (`release-*`)

Each `release-*` agent accepts `stack: django | react | fullstack` input and dispatches to `<django-stack>` / `<react-stack>` / `<fullstack-stack>` blocks. Single agent definition, all stack-specific expertise preserved.

| Agent | Role |
|---|---|
| `release-feature-researcher` | Probes codebase before planning — Django (apps, FK graph, migrations, patterns) OR React (components, Zustand stores, TanStack Query keys, router) |
| `release-pattern-mapper` | Maps each new file to closest existing analog — Django models/views/serializers OR React components/hooks/stores |
| `release-feature-planner` | Writes PLAN.md: TDD ordering + Q1-Q7 (Django) OR RC1-RC7 (React) + 9 security categories |
| `release-tdd-executor` | RED → GREEN → REFACTOR → SECURITY, atomic Conventional Commits. Stack-aware verification (pytest+migrations OR vitest+tsc) |
| `release-phase-verifier` | Goal-backward: D-XX implemented? Checklist evidence present? Stack-specific LOCK enforced (`.delay(` for Django, `localStorage.*token` for React)? |
| `release-code-reviewer` | Django (N+1, mass assignment, RLS bypass, `.delay()`) OR React (RC1-RC7, stale closures, missing `isLoading`, `any` types, auth tokens) |
| `release-code-fixer` | Applies REVIEW.md fixes atomically, per-finding commits, stack-specific verification after each Edit |
| `release-security-auditor` | 9-category audit per stack — Django (cross-tenant, IDOR, mass-assign, JWT, CSRF) OR React (XSS, auth storage, CSRF, IDOR, secrets) |
| `release-test-auditor` | Coverage matrix — Django (smoke/race/memray/security/celery/signal/permission) OR React (5 dimensions: unit/RTL/MSW/security/a11y) |
| `release-debugger` | 10 bug shape catalog per stack — Django (N+1, migration drift, RLS thread-var, Celery, F() lost-update) OR React (stale closure, infinite rerender, stale TanStack Query, MSW mismatch, hydration) |

### Agents — Singletons (release-sdk native)

#### Plan + discuss
| Agent | Role |
|---|---|
| `release-spec-clarifier` | SPEC.md ambiguity scoring before discuss-phase |
| `release-assumptions-analyzer` | Deep codebase analysis surfacing hidden assumptions + ripple analysis for discuss |
| `release-advisor-researcher` | Single gray-area D-XX decision research (5-dim comparison + falsifiable recommendation) |
| `release-feature-planner` | PLAN.md generation per stack |
| `release-plan-checker` | Pre-execute goal-backward + LOCK trace verifier (stack-aware gates) |
| `release-pattern-mapper` | Maps new files to closest existing analogs |

#### Research
| Agent | Role |
|---|---|
| `release-feature-researcher` | Phase pre-plan research |
| `release-ai-researcher` | AI/LLM framework research for `/release:ai-phase` |
| `react-ui-researcher` | UI-SPEC.md design contract author |
| `release-project-researcher` | Ecosystem research before roadmap (competitors, reference arch, pitfalls, regulatory) |
| `release-domain-researcher` | Pre-eval domain expertise for AI phases |
| `release-research-synthesizer` | Consolidates parallel researcher outputs into SUMMARY.md |
| `release-codebase-mapper` | Parallel 4-focus codebase analysis |
| `release-intel-updater` | Cached intel files at `.release-planning/intel/` |

#### Execute + verify
| Agent | Role |
|---|---|
| `release-tdd-executor` | TDD RED→GREEN→REFACTOR→SECURITY (stack-aware) |
| `release-wave-executor` | Parallel wave execution via git worktrees |
| `release-code-reviewer` | Stack-aware adversarial code review |
| `release-code-fixer` | Applies REVIEW.md findings as atomic commits |
| `release-phase-verifier` | Goal-backward post-execute verification |
| `release-uat-conductor` | Conversational UAT verification |
| `release-integration-checker` | Cross-phase E2E + data-contract probe (DRF↔Zod for fullstack) |
| `release-test-auditor` | Test coverage matrix per stack |
| `release-nyquist-auditor` | ≥2-tests-per-requirement audit |
| `release-debugger` | 10 bug-shape catalog per stack |
| `release-debug-session-manager` | Multi-cycle `/release:debug` loop manager in isolated context |

#### UI + AI
| Agent | Role |
|---|---|
| `react-ui-checker` | UI-SPEC pre-validation (PASS/FLAG/BLOCK) on 6 quality dims |
| `react-ui-auditor` | Retroactive scored 6-pillar visual audit |
| `release-framework-selector` | Interactive decision matrix for AI/LLM framework selection |
| `release-eval-planner` | Designs AI eval strategy (dims, rubrics, dataset, guardrails) |
| `release-eval-auditor` | Retroactive AI eval coverage audit |

#### Security
| Agent | Role |
|---|---|
| `release-security-auditor` | Stack-aware 9-category author-time security audit |
| `release-django-security-retro` | Retroactive Django security scorecard |
| `react-security-retro` | Retroactive React security scorecard |

#### Docs + import
| Agent | Role |
|---|---|
| `release-import-orchestrator` | One-shot GSD `.planning/` → release-sdk `.release-planning/` bridge |
| `release-doc-writer` | Writes/updates README, CONTRIBUTING, ARCHITECTURE, ONBOARDING grounded in artifacts |
| `release-doc-classifier` | Classifies a planning doc as ADR/PRD/SPEC/DOC/UNKNOWN |
| `release-doc-synthesizer` | Consolidates classified docs into INGEST-CONFLICTS.md |
| `release-doc-verifier` | Verifies factual claims in docs against live codebase |

#### Django-specific (pure Django logic)
| Agent | Role |
|---|---|
| `django-discuss-orchestrator` | 10-dim backend questionnaire (models, multi-tenancy, Celery, F(), select_for_update, etc) — spawned by `/release:discuss` |
| `django-checklist-verifier` | Q1-Q7 Django verifier — spawned by `/release:checklist` |

### Author Checklists

| Stack | Checklist | Questions |
|---|---|---|
| Django | Q1-Q7 | select_related, prefetch_related, annotate, Subquery, F()/select_for_update, delay_on_commit, iterator |
| React | RC1-RC7 | React.memo/useMemo/useCallback, isLoading/isError, TypeScript/Zod, accessibility, state discipline, auth token storage, test coverage |

### Slash commands

#### Entry point
| Command | Stack | Purpose |
|---|---|---|
| `/release:auto {intent}` | both | **Freeform-intent router.** 32 rules map your prompt to the right `/release:*` skill. Prints chosen route + reason before invoking. |

#### Project + phase lifecycle
| Command | Stack | Purpose |
|---|---|---|
| `/release:init` | both | Initialize PROJECT.md (LOCK-01..LOCK-12). Injects delimited block into repo-root CLAUDE.md. |
| `/release:import` | both | Mass-port GSD `.planning/` → release-sdk `.release-planning/` (one-shot, all phases) |
| `/release:spec {NN}` | both | Clarify WHAT phase delivers (SPEC.md, ambiguity score) |
| `/release:discuss {NN}` | both | Gather decisions (D-XX) for phase |
| `/release:plan {NN}` | both | Generate PLAN.md with checklists + security |
| `/release:ui-phase {NN}` | frontend | Produce UI-SPEC.md design contract |
| `/release:ai-phase {NN}` | both | Produce AI-SPEC.md (LLM framework, prompts, eval, guardrails) |
| `/release:execute {NN}` | both | TDD-strict execution (pytest or vitest) |
| `/release:verify {NN}` | both | Goal-backward static verification |
| `/release:verify-work {NN}` | both | Conversational UAT walkthrough (UAT.md) |
| `/release:ship` | both | Pre-ship review → PR body grounded in SPEC/PLAN/UAT → `gh pr create` → cursor `shipped`. Never auto-merges. |
| `/release:status` | both | Cursor + recent activity + next action |
| `/release:autonomous` | both | Run all remaining ROADMAP phases sequentially (spec→discuss→plan→execute→verify-work). Aborts on first verify failure. |

#### Quality gates + audits
| Command | Stack | Purpose |
|---|---|---|
| `/release:review` | both | Adversarial code review (REVIEW.md) |
| `/release:security` | both | 9-category security audit author-time (SECURITY.md) |
| `/release:secure-phase {NN}` | both | Retroactive threat-mitigation audit (scorecard) |
| `/release:checklist` | both | Q1-Q7 + RC1-RC7 verification |
| `/release:validate-phase {NN}` | both | Nyquist coverage audit: every requirement must have ≥2 tests |
| `/release:ui-review {NN}` | frontend | Retroactive 6-pillar visual audit (a11y, responsive, loading/error, i18n, type contracts, design system) |
| `/release:eval-review {NN}` | both | Retroactive AI eval coverage audit (COVERED/PARTIAL/MISSING per dim) |
| `/release:audit-fix` | both | Autonomous audit-to-fix loop (parallel auditors → release-code-fixer → re-audit) |
| `/release:audit-uat` | both | Cross-phase outstanding-UAT sweep with priority hot-list |
| `/release:plan-review-convergence {NN}` | both | Cross-AI peer-review loop (codex/gemini) until HIGH=0 AND MED≤2 |

#### Investigation + small work
| Command | Stack | Purpose |
|---|---|---|
| `/release:debug` | both | Persistent debug session at `.release-planning/debug/{id}/`. Survives `/clear` via checkpoint. |
| `/release:fast` | both | Trivial inline edit. No agents, no state. Clean-worktree gate, atomic commit. < 30 LOC envelope. |
| `/release:quick` | both | Bounded multi-file task with TDD executor. Cursor untouched. Between fast (no envelope) and plan (full). |
| `/release:forensics` | both | Post-mortem for failed workflows. Timeline + 5-whys + recovery plan. |
| `/release:add-tests {NN}` | both | Backfill UAT coverage or regression coverage for a file. |

#### Repo intelligence
| Command | Stack | Purpose |
|---|---|---|
| `/release:map-codebase` | both | Parallel 4-focus codebase analysis (tech, arch, quality, concerns) → `.release-planning/codebase/*.md` |
| `/release:docs-update` | both | Regenerate README/CONTRIBUTING/ARCHITECTURE verified against codebase |
| `/release:workstreams [sub]` | both | Manage parallel feature workstreams |

#### Legacy single-stack (kept for compatibility)
| Command | Stack | Purpose |
|---|---|---|
| `/django:review` | backend | Django-only review |
| `/django:security` | backend | Django-only security audit |

### Hooks

| Hook | Event | Purpose |
|---|---|---|
| `django-validate-commit.sh` | PreToolUse:Bash | Conventional Commits enforcement (both stacks) |
| `django-workflow-guard.js` | PreToolUse:Write/Edit | TDD advisory — warns on Django core file edit without test |
| `django-tenant-scope-check.sh` | PreToolUse:Write/Edit | Warns when new Model skips TenantModel |
| `django-prompt-guard.js` | PreToolUse:Write/Edit | Scans .release-planning/ for prompt injection patterns |
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
/plugin install release@release-sdk
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
.release-planning/                          # release-sdk-owned (renamed in v0.5.0 to coexist with GSD's .planning/)
├── PROJECT.md                              # LOCK-01..LOCK-12 (immutable)
├── RELEASE-LOCKS.md                        # extracted/imported LOCK-XX table
├── ROADMAP.md                              # phase list
├── REQUIREMENTS.md                         # REQ-XX
├── STATE.md                                # cursor
├── codebase/                               # output of /release:map-codebase
│   ├── STACK.md
│   ├── ARCHITECTURE.md
│   ├── QUALITY.md
│   └── CONCERNS.md
├── intel/                                  # output of release-intel-updater (cached)
│   ├── MODELS.md
│   ├── ROUTES.md
│   ├── COMPONENTS.md
│   ├── MIGRATIONS.md
│   ├── DEPENDENCIES.md
│   └── TEST-MAP.md
├── research/                               # ecosystem + project-level research
│   ├── PROJECT-ECOSYSTEM.md
│   └── SUMMARY.md                          # release-research-synthesizer output
├── debug/{session_id}/                     # /release:debug persistent sessions
├── forensics/                              # /release:forensics post-mortems
├── AUDIT-UAT.md                            # /release:audit-uat output
├── audit-fix-log.md                        # /release:audit-fix loop log
└── phases/
    └── {NN}-{slug}/
        ├── {NN}-SPEC.md                    # spec output (ambiguity score)
        ├── {NN}-CONTEXT.md                 # discuss output (D-XX backend + frontend)
        ├── {NN}-ASSUMPTIONS.md             # release-assumptions-analyzer output
        ├── {NN}-RESEARCH.md                # researcher output (single-stack)
        ├── {NN}-DOMAIN-RESEARCH.md         # release-domain-researcher (for AI phases)
        ├── {NN}-ADVISOR-{D-XX}.md          # release-advisor-researcher (gray-area D-XX)
        ├── {NN}-PLAN.md                    # planner output (single-stack)
        ├── {NN}-PLAN-BACKEND.md            # (fullstack: Django side)
        ├── {NN}-PLAN-FRONTEND.md           # (fullstack: React side)
        ├── {NN}-PLAN-CHECK.md              # release-plan-checker pre-execute verdict
        ├── {NN}-CONVERGENCE-LOG.md         # /release:plan-review-convergence iterations
        ├── {NN}-PATTERNS.md                # pattern-mapper output
        ├── {NN}-UI-SPEC.md                 # UI design contract (frontend phases)
        ├── {NN}-UI-CHECK.md                # react-ui-checker pre-impl verdict
        ├── {NN}-UI-REVIEW.md               # react-ui-auditor scored audit
        ├── {NN}-AI-SPEC.md                 # AI design contract (AI phases)
        ├── {NN}-AI-EVAL.md                 # release-eval-planner companion (if AI-SPEC locked)
        ├── {NN}-EVAL-REVIEW.md             # release-eval-auditor coverage report
        ├── {NN}-FRAMEWORK-DECISION.md      # release-framework-selector scored matrix
        ├── {NN}-SUMMARY.md                 # execute output
        ├── {NN}-CHECKLIST.md               # Q1-Q7 + RC1-RC7
        ├── {NN}-SECURITY.md                # security audit
        ├── {NN}-TEST-AUDIT.md              # test coverage map
        ├── {NN}-NYQUIST-AUDIT.md           # ≥2-tests-per-req audit
        ├── {NN}-TEST-GAP.md                # /release:add-tests test-only mode gap report
        ├── {NN}-UAT.md                     # user-observable acceptance items
        ├── {NN}-VERIFICATION.md            # verify output
        └── {NN}-SHIP-REVIEW.md             # /release:ship pre-ship review findings
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
