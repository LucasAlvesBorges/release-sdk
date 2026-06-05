---
name: quick
description: >
  Execute a bounded task with release-sdk guarantees (atomic commits, light state
  tracking) but skip the heavy phase machinery (no SPEC, no DISCUSS, no formal PLAN,
  no UI-SPEC, no AI-SPEC, no formal verification). Stack-aware via active phase or
  task content. Logs the run to `.release-planning/quick-log.md` for traceability.
  Use when: multi-file edit that's too big for `/release:fast` but doesn't need a
  formal phase (e.g., "add a new field to the Invoice model + migration + serializer
  + form", "swap library X for Y across three files").
---

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation.

---

# /release:quick — Bounded Task, Light Envelope

Between `/release:fast` (no envelope) and `/release:plan` (full envelope).

## Usage

```
/release:quick add `archived_at: DateTimeField(null=True)` to Invoice model + migration + serializer
/release:quick replace `axios` with `ky` in the three files that use it
/release:quick wire CSRF cookie passthrough in the React dev proxy
```

## Pre-checks

1. `.release-planning/` exists. Else: "Run `/release:init` first."
2. Worktree clean (`git status --short` empty). Else: "Stash or commit first."
3. Task scope sanity: if request implies > 10 files OR mentions "new feature", "design",
   "architecture", "spec" → abort with:
   > "Task looks like a feature. Use /release:spec to start a real phase."

## Execution flow

### Step 1 — Stack detection

From active phase in `.release-planning/STATE.md` if present; else from file extensions
in the task description; else ask user via `AskUserQuestion`: django / react / fullstack.

### Step 2 — Spawn TDD executor with `quick_mode: true`

```
Agent({
  subagent_type: "release:tdd-executor",
  description: "Quick task: {first-30-chars-of-task}",
  prompt: "{full task description from user}",
  metadata: {
    stack,
    quick_mode: true,
    no_plan: true,
    no_spec: true,
    write_state: false   # quick runs do not move the phase cursor
  }
})
```

The executor:
- Writes failing test(s) first (TDD)
- Implements the change to make them pass
- Refactors if needed
- Atomic commit per logical unit (typically 1-3 commits total)

### Step 3 — Log to quick-log

After agent returns, append to `.release-planning/quick-log.md` (create if missing):

```markdown
## {ISO timestamp} — {stack} — {first-line-of-task}

- Commits: {sha1}, {sha2}
- Files: {touched files list}
- Tests added: {test file paths}
- Result: {one-line outcome}
```

This is the only state side-effect — STATE.md and active-phase cursor are NOT touched.

### Step 4 — Report

Print to user:
- Commits made (sha + subject)
- Tests added
- Suggested next step (typically: `git push`, or `/release:status` to confirm cursor unchanged)

## Constraints

- **Worktree clean required.** No mixing with phase work.
- **No phase cursor move.** `/release:quick` is sideways work; it doesn't advance
  `active_phase` or `active_stage`.
- **TDD-first via `release:tdd-executor`.** No "implement then test later" shortcut.
- **Atomic commits.** Each commit is independently revertable.
- **No push.** User decides.
- **No SPEC, no PLAN, no UI-SPEC.** If those artifacts are needed, the task is too big —
  reroute to `/release:spec`.

## Example

```
/release:quick add `archived_at` to Invoice + migration + serializer + admin

→ Worktree clean ✓
→ Scope: 4 files (model, migration, serializer, admin) — within envelope ✓
→ Stack: django (active phase 03 = django)
→ Spawning release:tdd-executor (quick_mode)…
  [agent writes test_invoice_archived_at.py: 1 failing test]
  [agent adds field to Invoice model + makemigrations]
  [agent updates InvoiceSerializer + admin]
  [agent re-runs test: passes]
  [agent commits: feat(invoice): add archived_at soft-delete field]
→ Logging to .release-planning/quick-log.md
→ Result: 1 commit, 1 test added. Cursor unchanged (still phase 03 executing).
```

---

_Bounded task. Atomic commits. No phase machinery. Driven by `release:tdd-executor` in quick mode._
