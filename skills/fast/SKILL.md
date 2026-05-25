---
description: >
  Execute a trivial task inline — no subagents, no phase machinery, no state tracking.
  For one-shot edits where the work is faster than the overhead of planning it.
  Atomic commit at the end. Survives no context, but the task is small enough that it
  doesn't need to.
  Use when: rename a symbol, fix a typo, tweak a log line, change a single config value,
  or any task with a single-file feel and < 30 LOC of change.
allowed_tools: Read, Edit, Write, Bash, Grep, Glob
---

# /release:fast — Trivial Task, Inline

No planning. No agents. No state. Just do it and commit.

## Usage

```
/release:fast rename `EmpresaSerializer.user_email` to `owner_email`
/release:fast bump Django version in requirements.txt to 5.2.1
/release:fast remove debug print in views/invoice.py
/release:fast add CORS_ALLOWED_ORIGINS = [...] to settings.py
```

The arg is the task description. Treat it as a direct instruction.

## When to use this vs other skills

- **`/release:fast`** — single symbol or single file, no design decision needed
- **`/release:quick`** — multi-file but still bounded; needs atomic commit + light state
- **`/release:spec` → `/release:plan` → `/release:execute`** — anything with design ambiguity

If unsure, default to `/release:quick` (safer envelope).

## Execution flow

### Step 1 — Pre-checks

1. Worktree must be clean (`git status --short` empty). If dirty → abort with:
   > "Worktree has uncommitted changes. Stash or commit first."
2. Task scope check: if the request implies > 5 files OR > 30 LOC OR adds a new module,
   abort with:
   > "Task scope exceeds /release:fast envelope. Use /release:quick or /release:spec."

### Step 2 — Do the work

Use `Read` + `Edit` + `Grep` directly. No subagents. No `.release-planning/` writes.

### Step 3 — Validate

Run the obvious validation for the stack:
- Python edit → `python -m py_compile <file>` (or `ruff check <file>` if available)
- TypeScript edit → `tsc --noEmit <file>` is too heavy; skip (delegate to CI)
- JSON/YAML edit → parse to confirm valid

If validation fails → revert the edit, report failure to user, do NOT commit.

### Step 4 — Atomic commit

```bash
git add <touched files>
git commit -m "{type}({scope}): {one-line summary}

{optional body — only if the why isn't obvious}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

Commit type by intent:
- `fix:` — bug fix
- `chore:` — config / deps / lint
- `refactor:` — rename, restructure
- `docs:` — README / comments only

NEVER push automatically. The user pushes when ready.

## Constraints

- **No subagents.** This skill is intentionally synchronous and small.
- **No state writes.** `.release-planning/STATE.md` is untouched.
- **Clean worktree required.** No mixing with uncommitted work.
- **Validate before commit.** No commit on broken syntax.
- **No push.** User owns the push decision.

## Example

```
/release:fast remove unused `import json` from apps/invoice/views.py

→ Worktree clean ✓
→ Scope: 1 file, 1 line removal ✓
→ Editing apps/invoice/views.py…
→ py_compile passes
→ Committing: chore(invoice): drop unused json import
```

---

_Inline. No overhead. Built for tasks that cost more to plan than to do._
