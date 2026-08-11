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

## Codex runtime contract (generated; overrides incompatible source directives)

This skill is the Codex edition of release-sdk. The source workflow below is
kept for behavioral parity, but this contract has precedence whenever the
source mentions Claude Code primitives.

### Isolation

- Never create, edit, delete, or inspect runtime state under `~/.claude`,
  `.claude/`, `.claude-plugin/`, `.claude-plugin-cache/`, or `CLAUDE.md`.
- Release planning artifacts remain under `.release-planning/`. Durable Codex
  project guidance belongs in `AGENTS.md` only when the workflow explicitly
  needs to add it.
- Resolve `RELEASE_PLUGIN_ROOT` as the directory two levels above this
  `SKILL.md`. Resolve `RELEASE_PLUGIN_DATA` from `PLUGIN_DATA` when supplied;
  otherwise use `${CODEX_HOME:-$HOME/.codex}/release-sdk`.

### Step 0 — AGENTS.md gate

Before any Write/Edit/apply_patch, the target project MUST have a root
`AGENTS.md`. `release-agents-md-guard.js` enforces this at the hook level and
will block the write — do not try to route around it. If it blocks:
`.codex/config.toml`'s `[agents_md] mode` is `strict` (default: stop, tell the
user `AGENTS_MD_REQUIRED`) or `bootstrap` (spawn `release-agents-md-builder`
read-only, let it draft and save `AGENTS.md`, then stop and tell the user to
re-run the original task). Never fabricate the file yourself outside that
role, and never inline the full `AGENTS.md` content into a subagent prompt —
let Codex discover it normally from `cwd`.

### Step 1 — score complexity, then decide whether to spawn anything

Self-score the task C0–C4 using `complexity-rubric.md` before touching
anything else, apply the risk floors, then use `routing-policy.md`'s fleet
table for the level. Default is **no subagents** (`spawn = false`). Spawn one
only when ALL of:

```text
bounded_subtask
AND explicit_success_criteria
AND (independent OR noisy_output OR specialist_required OR broad_read_avoided)
AND estimated_context_avoided > spawn_overhead
```

Never spawn for C0. Never spawn just to "use multiagent." Never spawn a
subtask that immediately depends on another subtask's result and can't run in
parallel. Group reads over the same files instead of one agent per file.

**Read vs write:** read-only agents may run in parallel freely. Writers never
share a file set — one writer per path set, sequential when there's a
dependency, parallel only with disjoint scopes or isolated worktrees (declare
`allowed_paths`/`forbidden_paths` up front either way).

### Invoking a subagent

```text
Role: {role}
Single objective: {subtask_objective}

Allowed scope:
{allowed_paths}

Do not access:
{forbidden_paths}

Minimal context:
{task_specific_context}

Completion criteria:
{success_criteria}

Rules:
- Follow the AGENTS.md chain applicable to cwd.
- Do not expand scope on your own — return needs_scope_expansion instead.
- Do not restate the prompt back.
- Do not return full logs.
- Stop as soon as the criteria are met.
- Return only JSON matching SubagentResultV1.
```

Pass only this delta — never the full parent transcript, never the full
`AGENTS.md`, never whole files already in the workspace, never full logs.

### Handoff

Only when the task continues in another thread/session — see
`handoff-template.md` (60 lines / ~500 tokens max). Not a substitute for the
normal end-of-task summary.

### Tools

- Treat `Read`, `Write`, `Edit`, `Bash`, `Grep`, and `Glob` in the source as
  conceptual operations. Use the Codex tools currently available: targeted
  file reads, `apply_patch` for edits, `exec_command` for commands, and `rg`
  or `rg --files` for search.
- A source reference to `AskUserQuestion` means: use the structured user-input
  tool when it is available to the parent agent. A subagent must instead
  return `USER_INPUT_REQUIRED` with the exact question and 2-3 choices so the
  parent can ask it. If no structured input tool is available, ask one concise
  question in the parent task.
- A source reference to a `Skill` tool means to run the installed
  `release:<skill-name>` skill. If there is no callable skill tool, delegate to
  a `default` subagent with a task that explicitly names that installed skill,
  pass the original arguments unchanged, wait for it, and surface its result.

### Subagents

- Source agent names `release:<name>` are mapped in this generated edition to
  Codex custom agents named `release-<name>`.
- Spawn agents only through Codex collaboration tools. Do not emulate a
  subagent with a shell command and do not use a nonexistent `Task` or `Agent`
  tool.
- Prefer the named `release-<name>` agent when it is available. These agents
  are installed by the `release:setup-codex` skill and become available in a
  new task.
- If the exact named agent is not available, prefer this plugin's own generic
  roster before Codex's bare defaults: `release-explorer-fast` /
  `release-explorer-deep` for read-only research, `release-worker` /
  `release-worker-lite` / `release-worker-complex` for implementation,
  `release-reviewer` / `release-security-reviewer` for judgment-heavy review,
  `release-planner` for orchestration. Only fall back to Codex's bare
  `explorer` / `worker` / `default` if none of those are installed either —
  and in that case give the fallback agent the absolute path to
  `agents/release-<name>.toml` under `RELEASE_PLUGIN_ROOT` and require it to
  read and follow the `developer_instructions` before working.
- For write tasks, assign explicit file ownership and tell every worker that
  other agents may be editing the repository; it must preserve and integrate
  others' changes. Parallelize only independent scopes and respect the current
  session's concurrency limit.
- Wait for required agents, collect their final results, and keep completion
  judgment in the parent/orchestrator. A worker never declares the overall
  workflow complete.

### Models and reasoning

- Ignore source instructions that pin or derive Claude model tiers such as
  Fable, Opus, Sonnet, or Haiku, and ignore `CLAUDE_EFFORT`. Those do not
  apply in Codex.
- Every `release-<name>` custom agent already carries its own
  `model`/`reasoning_effort` per `routing-policy.md` — spawn it as-is. Only
  request a higher reasoning effort than the agent's default when the C0–C4
  fleet table for this task's level calls for it (`complexity-rubric.md`);
  never request a lower one.
- Preserve maker-versus-checker independence by using distinct agent turns —
  a checker runs as its own spawn, never as a self-review by the maker.

### Invocation vocabulary

- `/release:<name>` in the source is a workflow label retained for
  compatibility. In Codex Desktop the user selects the `release` plugin or its
  `release:<name>` skill from the composer.
- `claude` CLI launch examples map to `codex` in this generated edition.

# /release:baseline — known pre-existing test failures

```
/release:baseline capture            # run the suites, record every current failure as known
/release:baseline capture --suite backend
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
    "backend": {
      "cmd": "pytest backend/apps -q",
      "failures": [
        {"id": "backend/apps/financeiro/tests/test_dre.py::test_saldo", "error": "AssertionError"}
      ]
    }
  }
}
```

The error type is part of the signature on purpose: the same test failing for a **different** reason
is a NEW failure — that is how a fresh bug hides behind an old red.

## capture

1. Resolve the suites from `.release-planning/VERIFY-GATE.yml` (its `test:`-ish steps), or take
   `--cmd` explicitly. Record the command with the results.
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
| `release-test-runner` | classifies each bucket failure `BASELINE` vs `NEW`; the JSON carries both counts |
| `release-phase-verifier` | never reports an inherited failure as a phase gap |
| `release-tdd-executor` | a RED proof must be a NEW failure — a baseline hit does not prove the test is exercising your code |

**Fail-safe everywhere:** no baseline file, unparseable output, or a single unrecognized failure and
everything is treated as NEW. An absent baseline can never hide a regression.
`RELEASE_BASELINE_DISABLE=1` forces that mode on demand (use it to audit whether the list is stale).
