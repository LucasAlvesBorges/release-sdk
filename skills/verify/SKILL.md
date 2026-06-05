---
name: verify
description: >
  Context-aware goal-backward verification. Detects which stacks were implemented in a phase,
  spawns release-phase-verifier and/or release-phase-verifier, produces VERIFICATION.md.
  Use when: execute complete, before marking phase done.
---

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation.

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

## Backend verification (release:release-phase-verifier)

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

## Cross-phase integration check (release:release-integration-checker)

**Final optional step**, after per-phase VERIFICATION.md is written.

Gate:
```
verified_or_shipped_count = count of phases in current milestone (from ROADMAP.md) at stage ∈ {verified, shipped}
if verified_or_shipped_count >= 2:
    spawn release:release-integration-checker
else:
    echo "Integration check skipped (only $verified_or_shipped_count phases at verified+, need 2)."
```

Spawn invocation:
```
Agent({
  subagent_type: "release:release-integration-checker",
  phases: [<NNs of all verified/shipped phases in current milestone>],
  stack: "{django|react|fullstack}",   # auto-detect from PROJECT.md stack: field
  milestone: "{label}"                  # from ROADMAP.md current milestone
})
```

Output: `.release-planning/INTEGRATION-CHECK.md` (milestone-scoped, NOT inside a single phase directory — it spans phases).

**Non-gating:** failures detected by the integration checker DO NOT change the per-phase verify verdict — this step is informational only. Print findings table to stdout so the user sees seam issues, but `{NN}-VERIFICATION.md` verdict stands as written by `release:release-phase-verifier`.

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-VERIFICATION.md

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


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.

## Notes / Constraints

- v0.7.0 wires `release:release-integration-checker` as an OPTIONAL final step: spawns only when ≥2 phases in the current milestone are at stage `verified` or `shipped`. Writes milestone-scoped `.release-planning/INTEGRATION-CHECK.md` (not per-phase). Informational — does NOT change the per-phase verify verdict.
