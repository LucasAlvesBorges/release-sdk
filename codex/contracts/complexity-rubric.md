# Complexity scoring reference (C0–C4)

Referenced by `skill-contract.md`. Score BEFORE deciding whether to spawn
anything. This is a self-scoring rubric for the orchestrating model — there
is no deterministic script, because uncertainty/coupling/risk require
judgment.

## Dimensions

**A. File/module scope (0–3):** 0 = one known file or pure text change ·
1 = 2–3 files, same module · 2 = 4–8 files or two related modules ·
3 = >8 files, multiple packages/services.

**B. Uncertainty (0–3):** 0 = exact change already located · 1 = area known,
symbols still need locating · 2 = root cause unknown or behavior
inconsistent · 3 = open problem, undefined architecture, ambiguous
requirements.

**C. Coupling (0–3):** 0 = local change, no shared contract · 1 = internal
API or shared state within the module · 2 = public API, schema, DB, queue, or
cross-module integration · 3 = concurrency, distributed transaction,
migration, or multiple services.

**D. Risk (0–4):** 0 = docs/comments/style/behavior-free refactor · 1 =
common, easily reversible behavior · 2 = shared flow or user-visible impact ·
3 = auth, authorization, payments, privacy, or data integrity · 4 = possible
data loss, downtime, leak, or security-boundary break.

**E. Validation (0–2):** 0 = focused deterministic test already exists · 1 =
needs new tests or local integration · 2 = needs multiple environments,
perf/browser/concurrency, or flaky-test handling.

**F. External dependency (0–1):** 0 = no dependency on external/versioned
behavior · 1 = needs current docs, third-party API, or version-dependent
behavior.

## Levels

| Level | Score | Name |
|---|---:|---|
| C0 | 0–2 | Trivial |
| C1 | 3–5 | Simple |
| C2 | 6–8 | Moderate |
| C3 | 9–12 | Complex |
| C4 | 13–16 | Critical |

Apply the risk floors from `routing-policy.md` after summing the score —
they can only raise the level, never lower it.

Once scored, use `routing-policy.md`'s "Complexity → fleet shape" table to
pick agents, tiers, and concurrency limits.
