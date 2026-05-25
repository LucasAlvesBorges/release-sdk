---
description: >
  Goal-backward verification of a completed phase. Verifies every must_have truth from PLAN.md observable
  in the codebase + tests pass + every Decision D-XX implemented. Does NOT trust SUMMARY.md — checks
  actual code. Produces VERIFICATION.md with PASS/GAPS_FOUND/CRITICAL verdict.
  Use when: phase executed, before marking complete. Required before /django:phase next.
allowed_tools: Agent, Read, Write, Bash
---

# /django:verify — Goal-Backward Phase Verification

Verifies a phase actually delivered its goal — adversarially. Does NOT trust executor's claims.

## Usage

```
/django:verify 01
/django:verify 01 --re-run         # if prior verification had gaps, re-check failed items
```

## Arguments

- `$ARGUMENTS` — phase number (required)
- `--re-run` — re-verification mode (focuses on previously failed items)

## Workflow

1. Read `.planning/phases/{NN}-*/{NN}-PLAN.md` — extract `must_haves`, `threat_model`.
2. Read `{NN}-CONTEXT.md` — extract D-XX decisions.
3. Read `{NN}-SUMMARY.md` — note executor's claims (but don't trust).
4. Read `.planning/PROJECT.md` — LOCK-XX.
5. Read `.planning/ROADMAP.md` — phase `success_criteria`.
6. Spawn `django-phase-verifier` agent.
7. Verifier performs 3-level audit per truth:
   - **L1 Artifact** — file/symbol exists
   - **L2 Substantive** — not stub (`pass`, `TODO`)
   - **L3 Wired** — corresponding test passes
8. Verifies each D-XX implemented (grep evidence).
9. Verifies LOCK-XX compliance.
10. Runs full app test suite, makemigrations check, Q6 grep, ruff.
11. Writes `{NN}-VERIFICATION.md` with verdict.
12. If PASS: updates ROADMAP phase status → `complete`, advances STATE cursor.
13. Commits.

## Verdicts

| Status | Meaning | Next |
|--------|---------|------|
| PASS | All truths VERIFIED, all tests pass | Phase complete; advance to next |
| PASS_WITH_WARNINGS | All truths VERIFIED, some non-truth concerns | User reviews, decides |
| GAPS_FOUND | ≥1 truth FAILED or UNCERTAIN | Run `/django:plan {NN} --gaps` to plan fix |
| CRITICAL | LOCK violation (e.g., `.delay()` in production) | Block phase advancement; fix immediately |

## What's verified

For each truth in PLAN.md `must_haves.truths`:
- Does file declared in `must_haves.artifacts` exist?
- Is artifact substantive (not stub)?
- Does test asserting that truth pass?

For each D-XX in CONTEXT.md:
- Grep evidence the decision is implemented in code?

For LOCK-XX from PROJECT.md:
- Any forbidden pattern in the new code? (`fields='__all__'`, `.delay()`, raw SQL with f-string, etc.)

For the 9 security categories:
- Each category has corresponding test? Test passes?

## Output

`{NN}-VERIFICATION.md` with matrix:

```yaml
truths_total: 5
truths_verified: 4
truths_failed: 1
tests_passing: 47/48
lock_violations: 0
status: GAPS_FOUND
```

## Example

```
/django:verify 01

→ Reading PLAN.md must_haves... 5 truths declared
→ Reading CONTEXT.md... 6 D-XX decisions
→ Reading SUMMARY.md... executor reports 5/5 tasks done

→ Spawning django-phase-verifier (adversarial mode)

→ Auditing truth T-01: "User can bulk-import CSV"
  L1 file exists ✓  L2 substantive ✓  L3 test_bulk_import passes ✓
  VERIFIED

→ Auditing truth T-02: "Import rejects malformed CSV"
  L1 file exists ✓  L2 substantive ✓  L3 test_malformed_csv FAILS
  FAILED — test assertion not met

→ Auditing D-03: "Reject duplicates per tenant"
  Grep `validate_identificador` ... not found
  Grep `UniqueTogetherValidator` ... not found
  FAILED — decision not implemented

→ LOCK audit:
  ✓ TenantModel inherited
  ✓ no `.delay()` in production code
  ✓ no `fields='__all__'`

→ Wrote VERIFICATION.md
→ Status: GAPS_FOUND (2 gaps)

→ Next: /django:plan 01 --gaps to plan fix
```
