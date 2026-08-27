---
name: discuss
description: >
  Resume or amend decisions in an existing phase spec. This is a compatibility alias, not a second
  discovery pipeline: it asks only unresolved HIGH/MED questions and updates NN-SPEC.md directly.
  A targeted assumptions scan is reserved for strict risk or explicit --scan.
---

# /release:discuss — resume decisions, do not rediscover the phase

## Usage

```text
/release:discuss 03
/release:discuss 03 --scan
/release:discuss 03 --strict
```

## Workflow

1. Read `{NN}-SPEC.md`. If absent, run `/release:spec {NN}` rather than recreating its work here.
2. Read legacy `{NN}-CONTEXT.md` only to import D-XX values not already present in SPEC.
3. Collect unresolved HIGH questions, then MED questions that change architecture, contract or risk.
4. Ask at most three questions in one batch. Never walk a fixed Django/React dimension list.
5. Update SPEC `Decisions`, `Open questions`, and `status`. Preserve decision IDs.
6. If a legacy CONTEXT file exists, append a compact compatibility mirror of newly locked D-XX;
   do not create one for new phases.
7. Commit one documentation change after the batch.

## Targeted scan

Do not spawn `release:assumptions-analyzer` by default. Spawn it once only when `--scan`, `--strict`,
or a C3/C4 risk floor applies and a decision genuinely depends on codebase evidence. Scope it to the
named modules and ask for only contradictions plus file:line evidence. Do not retain a broad
ASSUMPTIONS.md inventory when there are no findings.

Stop as soon as no HIGH question remains. Implementation details that follow an existing pattern
are planner discretion, not another user decision.
