---
description: >
  Show project status: current phase, active stage, recent commits, next suggested action.
  Detects full-stack state — reports Django phase progress + React phase progress separately.
  Use any time to get a quick read on where things stand.
allowed_tools: Agent, Read, Bash, Grep, Glob
---

# /release:status — Project Status

Shows cursor, recent activity, next action. Full-stack aware.

## Usage

```
/release:status                      # full status
/release:status --short              # one-liner: "Phase 02 → frontend execute-complete"
```

## What it shows

1. **Current cursor** — from STATE.md: active phase, active stage (discuss/plan/execute/verify)
2. **Phase breakdown** — for active phase: backend stage + frontend stage (if fullstack)
3. **Recent commits** — `git log --oneline -10`
4. **Quality gates status** — last REVIEW.md verdict, last SECURITY.md verdict
5. **Next suggested action** — based on current stage:

| Current stage | Suggested next |
|---|---|
| `init-complete` | `/release:roadmap` |
| `discuss-complete` | `/release:plan {NN}` |
| `plan-complete (backend)` | `/release:execute {NN} --backend` |
| `plan-complete (frontend)` | `/release:execute {NN} --frontend` |
| `execute-complete (backend)` | `/release:execute {NN} --frontend` (if fullstack) |
| `execute-complete` | `/release:verify {NN}` |
| `verify-complete (PASS)` | `/release:review {NN}` or start next phase |
| `verify-complete (GAPS_FOUND)` | `/release:plan {NN} --gaps` |

## Example output

```
/release:status

━━━ release-sdk status ━━━━━━━━━━━━━━━━━━━━━━━━━━

Project:    Invoice Management SaaS
Phase:      02 — invoice-list-page
Stack:      FULLSTACK

  Backend:  ✅ execute-complete (SUMMARY.md present)
  Frontend: 🔄 execute-in-progress (T02/4 tasks done)

Recent commits (last 5):
  a1b2c3  feat(ui): implement InvoiceList component
  d4e5f6  test(ui): add failing tests for InvoiceList
  g7h8i9  feat(financeiro): implement invoice list endpoint
  j0k1l2  test(financeiro): add 9-category security tests
  m3n4o5  refactor(financeiro): apply Q1-Q7

Quality gates:
  Last review:   .planning/phases/02-invoice-list/REVIEW.md — 0 BLOCKERs, 2 WARNINGs
  Last security: .planning/phases/02-invoice-list/02-SECURITY.md (backend) — 9/9 CLOSED

Next suggested action:
  → /release:execute 02 --frontend --resume   (continue from T03)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
