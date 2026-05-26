---
name: add-tests
description: >
  Generate tests for a completed phase based on UAT criteria and implementation, or regression
  tests for a specific file after a fix. Stack-aware (django=pytest/factory-boy, react=vitest/RTL/MSW).
  Spawns release-tdd-executor in test-only mode. Tests that fail against current implementation
  surface as bugs in {NN}-TEST-GAP.md — never auto-fixed.
  Use when: phase UAT items lack regression coverage, or a debug session resolved a bug and you
  want a test that prevents regression.
---

# /release:add-tests — Stack-Aware Test Backfill

Additive test generation against an existing implementation. Never modifies impl, never deletes
existing tests, never introduces new test dependencies. Routes a `release-tdd-executor` in
TEST-ONLY mode that writes tests against what already exists.

## Relationship to /release:execute

| Skill | Mode | When tests are written | Implementation |
|---|---|---|---|
| `/release:execute` | TDD-strict (RED → GREEN → REFACTOR → SECURITY) | BEFORE impl (RED proves failure) | Written to satisfy tests |
| `/release:add-tests` | Test-only backfill | AFTER impl (tests written against existing code) | Untouched; bugs surfaced, not fixed |

`/release:execute` enforces TDD discipline for new features. `/release:add-tests` covers gaps
left by ad-hoc commits, debug fixes, or UAT items that were verified manually but not asserted
by a test.

## Usage

```
/release:add-tests {NN}                       # generate tests for phase NN (uses {NN}-UAT.md + impl)
/release:add-tests {NN} --gap-fill            # only add tests for UAT items not yet covered
/release:add-tests --regression-for {file}    # regression tests for one file (e.g. post-fix)
/release:add-tests {NN} --backend             # restrict to backend (Django) items
/release:add-tests {NN} --frontend            # restrict to frontend (React) items
/release:add-tests {NN} --dry-run             # show plan without spawning executor
```

## Pre-checks

1. `.release-planning/` directory exists at repo root.
2. If `{NN}` provided:
   - Phase dir `.release-planning/phases/{NN}-{slug}/` exists.
   - Phase stage in STATE.md is `executing` or `verified` (not `discussing` or `planning`).
3. If `--regression-for {file}`:
   - File path resolves inside the worktree.
   - File is not under `tests/`, `__tests__/`, or `*.test.*` (refuse to "test the tests").
4. Worktree does NOT need to be clean — this skill is additive.

Abort with actionable message on any failed pre-check.

## Stack detection

Priority order:

1. `--backend` / `--frontend` flag → forced stack.
2. If `--regression-for {file}` → infer from file extension:
   - `.py` → django
   - `.ts` / `.tsx` / `.jsx` → react
3. If `{NN}` provided → read `{NN}-PLAN.md` frontmatter `stack:` field.
4. Else read `.release-planning/PROJECT.md` `stack:` field.
5. For `stack: fullstack` phases with no flag → ask user which stack to target.

## Source resolution

For phase mode:

1. `{phase_dir}/{NN}-UAT.md` — primary source. Parse UAT Items table; each row = candidate test.
2. `{phase_dir}/{NN}-PLAN.md` — read task list (`files`, `done_when`) to understand what was built
   and which public surfaces should have assertions.
3. `{phase_dir}/{NN}-SUMMARY.md` (if present) — read `commits:` list to scope tests to actually
   delivered work.

For regression mode:

1. Target file content — enumerate exported / public functions, components, view classes, hooks.
2. Most recent commit touching the file — extract the bug description from the commit body
   (e.g. `fix(orders): prevent negative quantity` → regression test asserts quantity validation).
3. If `.release-planning/phases/{NN}-{slug}/{NN}-DEBUG.md` exists for the file → use the
   recorded reproduction steps verbatim.

## Coverage gap detection (--gap-fill)

For each UAT item U-XX in `{NN}-UAT.md`:

1. Extract identifying tokens (endpoint path, component name, route, function name) from item
   description and adjacent `Steps` column.
2. Glob existing tests:
   - django: `backend/**/tests/test_*.py`, `backend/**/tests/**/test_*.py`
   - react:  `src/**/__tests__/**`, `src/**/*.test.{ts,tsx}`
3. Grep test bodies for the identifying tokens.
4. Item is COVERED if any test asserts the behavior; UNCOVERED otherwise.
5. `--gap-fill` mode skips COVERED items; default mode regenerates all (skipping items already
   labelled `Status: PASS` with a `Test:` cross-ref).

Write the gap analysis to `{phase_dir}/{NN}-TEST-PLAN.md` before spawning the executor.

## Target test paths

### django

For each item with module token `apps/{app}/...`:

```
backend/apps/{app}/tests/test_{module}.py            # unit / view tests
backend/apps/{app}/tests/test_{feature}_regression.py # regression bundle (--regression-for)
backend/apps/{app}/tests/factories.py                 # factory-boy fixtures (append, don't replace)
```

Use existing `conftest.py` fixtures (`auth_client_a`, `auth_client_b`, `db`, `tenant_a`). If
none exist, abort with: "no conftest.py — run /release:execute first to scaffold test infra."

### react

For each item with component / hook token `src/features/{feature}/{Comp}.tsx`:

```
src/features/{feature}/__tests__/{Comp}.test.tsx        # RTL component tests
src/features/{feature}/__tests__/{Comp}.regression.test.tsx  # --regression-for bundle
src/test/mocks/handlers.ts                              # MSW handler (append, don't replace)
```

Use existing MSW server + `vi.mock` patterns. If `src/test/setup.ts` is missing, abort with
guidance.

## Executor spawn (TEST-ONLY MODE)

Spawn `release-tdd-executor` with explicit test-only configuration:

```yaml
stack: django | react
plan_path: {phase_dir}/{NN}-TEST-PLAN.md   # synthesized for this run
task_filter: [TT01, TT02, ...]              # one TT-id per uncovered item / target function
no_branch: true                              # commit to current branch (additive)
cwd: <repo root>
mode: test-only                              # NEW — see below
```

Test-only mode contract (passed in the spawn prompt, since executor frontmatter has no
`mode` slot natively):

- DO write new test files at the paths listed above.
- DO append to `factories.py` / `handlers.ts` when new fixtures are needed.
- DO run the test suite to verify each new test:
  - django: `pytest <new_test_file> -v`
  - react:  `npx vitest run <new_test_file> --reporter=verbose`
- DO NOT modify any non-test file under `backend/apps/` or `src/` (factories.py and
  handlers.ts are explicit exceptions).
- DO NOT delete or rewrite existing tests.
- DO NOT introduce new test dependencies — use what's already in `pyproject.toml` /
  `package.json`.
- DO NOT run RED phase (we are asserting against EXISTING impl — tests should PASS on first
  run; failure means a real bug).
- For each new test:
  1. Write the test asserting expected behavior.
  2. Run it once.
  3. If PASS → commit as `test({scope}): add coverage for U-XX {summary}`.
  4. If FAIL → DO NOT fix the impl. Append a row to `{NN}-TEST-GAP.md`:
     `| U-XX | {file}::{test_name} | {assertion that failed} | {1-line hypothesis} |`
     then SKIP that test commit (delete the failing test file so the suite stays green).
- Honor stack LOCKs when authoring (no `localStorage` reads in react tests; cookie auth in
  django tests — never JWT headers).

## Output

### Always written

```
.release-planning/phases/{NN}-{slug}/
  {NN}-TEST-PLAN.md      # gap analysis + TT-task list, generated by this skill
```

Frontmatter of TEST-PLAN.md:
```yaml
---
phase: {NN}
mode: phase | regression
stack: django | react | fullstack
generated_at: {iso}
uat_items_total: {N}
uat_items_covered: {N}
uat_items_added: {N}
target_files:
  - backend/apps/{app}/tests/test_{module}.py
  - src/features/{feature}/__tests__/{Comp}.test.tsx
---
```

### Conditionally written

```
{phase_dir}/{NN}-TEST-GAP.md     # only if any new test failed against current impl
{phase_dir}/{NN}-TEST-SUMMARY.md # written by executor on completion
```

`{NN}-TEST-GAP.md` shape:
```markdown
# Phase {NN} — Test Gaps Surfaced

These tests were written to assert UAT behavior but FAILED against the current implementation.
Each row is a likely bug. Do NOT auto-fix — investigate via `/release:debug`.

| UAT | Test (file::name) | Failed Assertion | Hypothesis | Next Action |
|-----|-------------------|------------------|------------|-------------|
| U-02 | InvoiceList.test.tsx::renders_zero_state | expected text "No invoices" not found | empty state JSX missing | `/release:debug 01 --item U-02` |
```

## Commit shape

One commit per test file (atomic, additive):

```
test(django): add coverage for phase {NN} UAT items U-01,U-03
test(ui): add coverage for phase {NN} UAT items U-02
test(django): regression coverage for apps/orders/views.py
test(ui): regression coverage for src/features/checkout/CheckoutForm.tsx
```

Skill itself does NOT commit `{NN}-TEST-PLAN.md` / `{NN}-TEST-GAP.md` (planning artifacts under
`.release-planning/` follow project-level commit policy; respect existing `.gitignore`).

## Workflow integration

Typical flows:

```
# Backfill after UAT pass
/release:verify-work 01            # human walks UAT, marks PASS/FAIL
/release:add-tests 01 --gap-fill   # add automated coverage for PASS items lacking tests
/release:ship 01                   # PR with both impl + new tests

# Regression after debug
/release:debug 01 --item U-02      # find + fix bug
git commit -m "fix(ui): handle empty invoice list"
/release:add-tests --regression-for src/features/invoices/InvoiceList.tsx
```

## What this skill does NOT do

- Does NOT modify implementation files (impl bugs go to `{NN}-TEST-GAP.md`).
- Does NOT delete or rewrite existing tests.
- Does NOT introduce new test deps (pytest, vitest, factory-boy, MSW must already be wired).
- Does NOT enforce TDD RED phase — tests are written AGAINST existing impl.
- Does NOT run REFACTOR or SECURITY phases (those are `/release:execute`).
- Does NOT update STATE.md cursor or advance phase stage.
- Does NOT open PRs.

## Anti-patterns

- Using `--gap-fill` on a phase still in `executing` stage → use `/release:execute` instead;
  TDD discipline is required for new code.
- Letting a `{NN}-TEST-GAP.md` entry sit unresolved before `/release:ship` → ship will block.
- Editing the synthesized `{NN}-TEST-PLAN.md` by hand to bypass coverage detection → re-run
  with `--gap-fill` instead.
- Re-running without `--gap-fill` after partial success → may duplicate tests; the skill
  detects existing `test_*` functions by name but is not infallible.


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
