---
description: >
  Context-aware goal-backward verification. Detects which stacks were implemented in a phase,
  spawns django-phase-verifier and/or react-phase-verifier, produces VERIFICATION.md.
  Use when: execute complete, before marking phase done.
allowed_tools: Agent, Read, Write, Bash, Grep, Glob
---

# /release:verify — Context-Aware Phase Verification

Detects phase type and runs the appropriate verification(s).

## Usage

```
/release:verify 01                   # auto-detect, verify
/release:verify 01 --backend         # Django verification only
/release:verify 01 --frontend        # React verification only
```

## Detection

Reads SUMMARY.md(s) from execute phase:
- `{NN}-SUMMARY.md` with `stack: django` → backend verify
- `{NN}-SUMMARY.md` with `stack: react-tsx` → frontend verify
- Both exist → fullstack verify

## Backend verification (django-phase-verifier)

Goal-backward analysis:
1. Every PLAN.md truth (must_haves.truths) observable in code?
2. Every D-XX decision implemented and grep-provable?
3. All pytest tests pass?
4. `makemigrations --check` clean?
5. `ruff check` clean?
6. Q6: no `.delay()` in production code?
7. 9-category security tests present and passing?

## Frontend verification

Goal-backward analysis:
1. Every D-XX (frontend) decision implemented?
2. All Vitest tests pass?
3. `tsc --noEmit` clean?
4. RC1-RC7 evidence in SUMMARY.md?
5. 9-category React security tests present and passing?
6. No localStorage auth token usage (grep)?
7. CSRF header sent in API calls (test evidence)?

## Integration verification (fullstack)

Additional checks:
- API endpoint from PLAN-BACKEND matches fetch URL in PLAN-FRONTEND
- Serializer field names match Zod schema fields
- Auth strategy consistent end-to-end

## Output

```
.planning/phases/{NN}-{slug}/{NN}-VERIFICATION.md

---
verdict: PASS | GAPS_FOUND
backend_verdict: PASS | GAPS_FOUND | N/A
frontend_verdict: PASS | GAPS_FOUND | N/A
---

## Backend Verification
[table: truth → code evidence → PASS/FAIL]

## Frontend Verification
[table: decision → code evidence → PASS/FAIL]

## Gaps Found (if any)
D-03: NOT IMPLEMENTED — ...
RC2: isError state missing in InvoiceList

## Next Steps
PASS → /release:review 01 (optional), mark phase done
GAPS_FOUND → /release:plan 01 --gaps → /release:execute 01 --gaps
```
