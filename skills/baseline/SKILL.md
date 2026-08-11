---
name: baseline
description: >
  Capture, inspect and clear the known pre-existing test failures in
  `.release-planning/test-baselines.json`. The gate, the test-runner and the phase-verifier compare
  against it, so a repo that inherits long-standing reds can still reach GATE=GREEN and the loop
  stops re-triaging failures this phase never caused. Use when: the suite has failures that predate
  your work, a gate is RED for reasons you did not introduce, or after fixing inherited failures
  (re-capture so they can never be excused again).
---

# /release:baseline — known pre-existing test failures

```
/release:baseline capture            # run the suites, record every current failure as known
/release:baseline capture --suite test    # one VERIFY-GATE step (the suite key IS the step name)
/release:baseline show               # what is currently excused, and since when
/release:baseline diff               # run the suites now and compare against the recorded baseline
/release:baseline clear              # delete the file (everything becomes NEW again)
```

## Why this exists

A phase gate asks "is the suite green?". In a repo carrying 44 long-standing failures the honest
answer is "no, and it never will be", so the loop burns iterations trying to fix code the phase
never touched, and a genuine regression hides inside the noise. The baseline changes the question
to the only one a phase gate should ask: **did WE break anything?**

## The file

`.release-planning/test-baselines.json` — a signature per known failure, `<test id>|<error type>`:

```json
{
  "captured_at": "2026-08-11T10:00:00Z",
  "captured_on": "main@a1b2c3d",
  "suites": {
    "test": {
      "cmd": "pytest backend/apps -q",
      "failures": [
        {"id": "backend/apps/financeiro/tests/test_dre.py::test_saldo", "error": "AssertionError"}
      ]
    }
  }
}
```

**The suite key is the VERIFY-GATE STEP NAME — not a stack label.** `run_gate` looks the baseline
up by the name of the step it just ran, so a file keyed `backend` while the gate step is `test:`
matches nothing and the feature is silently inert (the gate just stays RED, with nothing to explain
why). If `VERIFY-GATE.yml` declares `test:` and `fe-test:`, the suites are `test` and `fe-test`.
`capture` derives the keys from the gate for exactly this reason — do not rename them by hand.

The error type is part of the signature on purpose: the same test failing for a **different** reason
is a NEW failure — that is how a fresh bug hides behind an old red.

## capture

1. Resolve the suites from `.release-planning/VERIFY-GATE.yml` — **the suite key IS the step name**
   (`test:` → `suites.test`). Record each step's command alongside its results. `--suite <name>`
   selects one step; `--cmd` runs an ad-hoc command and requires an explicit `--suite` to key it.
   Verify after writing: every suite key must exist as a step in VERIFY-GATE.yml, and warn loudly
   about any that does not — that entry can never match.
2. **Refuse to capture on a dirty tree, and warn loudly when not on the project's base branch** —
   a baseline captured on top of half-finished work excuses your own breakage forever. State the
   branch + SHA you captured on; they go into `captured_on`.
3. Run each suite (with `$RELEASE_EXEC_PREFIX` when the project uses per-worktree envs), parse the
   failures with `baseline_parse_failures` from `bin/release-baseline-lib.sh`, write the file.
4. Print the count per suite and, when a previous baseline existed, the delta:
   `+3 newly excused, -7 fixed since <date>`.

Fixing an inherited failure and re-capturing is how the list shrinks. **A growing baseline is a
warning sign** — say so when it grows.

## show / diff / clear

- `show` — the recorded signatures grouped by suite, with `captured_at` / `captured_on` and the
  total. Flag it when the capture is older than ~30 days: a stale baseline excuses failures that
  may already be fixed.
- `diff` — run the suites now and classify with `baseline_classify`: `NEW=` lines are yours,
  `BASELINE=` lines are inherited, plus the verdict (`clean` / `baseline-only` / `new`). Nothing is
  written.
- `clear` — delete the file after confirming. Everything becomes NEW again (the fail-safe default).

## Who reads it

| Consumer | Behaviour |
|---|---|
| `run_gate` (`bin/release-gate-lib.sh`) | a failing step whose failures are ALL baseline ⇒ `GATE_STEP=<n> PASS_BASELINE`, gate stays GREEN. One unknown failure ⇒ plain FAIL/RED |
| `release:test-runner` | classifies each bucket failure `BASELINE` vs `NEW`; the JSON carries both counts |
| `release:phase-verifier` | never reports an inherited failure as a phase gap |
| `release:tdd-executor` | a RED proof must be a NEW failure — a baseline hit does not prove the test is exercising your code |

**Fail-safe everywhere:** no baseline file, unparseable output, or a single unrecognized failure and
everything is treated as NEW. An absent baseline can never hide a regression.
`RELEASE_BASELINE_DISABLE=1` forces that mode on demand (use it to audit whether the list is stale).
