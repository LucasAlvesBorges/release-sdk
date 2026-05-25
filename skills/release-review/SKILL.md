---
description: >
  Context-aware adversarial code review. Analyzes file paths to split .py files to release-code-reviewer
  and .tsx/.ts files to release-code-reviewer. Produces a unified REVIEW.md with sections per stack.
  Use when: reviewing PR diff, auditing recently-modified files, pre-merge quality gate.
allowed_tools: Agent, Read, Bash, Grep, Glob
---

# /release:review — Adversarial Code Review (Django + React)

Routes files to the correct reviewer based on extension. Produces unified REVIEW.md.

## Usage

```
/release:review                              # review all files changed vs main
/release:review backend/apps/financeiro/     # Django-only path
/release:review src/features/Invoices/       # React-only path
/release:review --diff main..HEAD            # git diff
/release:review --depth=deep                 # deep review both stacks
/release:review --fix                        # apply fixes after review
```

> Previously: `--gsd-context` flag. Removed in v0.4.0 — use `/release:import` once to convert GSD planning files; all skills then assume release-sdk native format.

## Routing logic

0. Load LOCK constraints: read `.planning/RELEASE-LOCKS.md` if exists (GSD import), else `.planning/PROJECT.md`. Pass active LOCKs to each reviewer as forbidden-pattern context.
1. Resolve files to review (from args, git diff, or changed since last commit).
2. Split by extension:
   - `.py` → `django_files` → spawn `release-code-reviewer`
   - `.tsx`, `.ts`, `.jsx`, `.js` → `react_files` → spawn `release-code-reviewer`
   - Other → skip (lock files, migrations, .md)
3. Run reviewers in parallel if both sets present.
4. Merge findings into single REVIEW.md with `## Django Findings` and `## React Findings` sections.
5. Report combined totals: `{N} Django blockers, {M} React blockers`.

## Fullstack integration check

When BOTH Django and React files are in scope (e.g., reviewing a feature that adds API + UI):
1. Check API contract alignment: does the Django serializer field set match the Zod schema in React?
2. Check auth consistency: Django uses httpOnly cookie? React doesn't read token from localStorage?
3. Report mismatches as `## Integration Issues` section in REVIEW.md.

## Output

```
REVIEW.md (or path specified by --review-path):
  Frontmatter: totals per stack
  ## Django Findings
    ### Blockers (CR-XX)
    ### Warnings (WR-XX)
  ## React Findings
    ### Blockers (CR-XX)
    ### Warnings (WR-XX)
  ## Integration Issues (if fullstack)
```

## Example

```
/release:review --diff main..HEAD

→ Changed files:
    backend/apps/financeiro/serializers.py  → Django
    backend/apps/financeiro/views.py        → Django
    src/features/Invoices/InvoiceList.tsx   → React
    src/hooks/useInvoices.ts                → React

→ Spawning release-code-reviewer (2 files, depth=standard)...
→ Spawning release-code-reviewer (2 files, depth=standard)... [parallel]

→ Django findings: 1 BLOCKER (mass assignment in serializer), 2 WARNINGS
→ React findings: 0 BLOCKERS, 3 WARNINGS (missing memo, missing error state, key={index})

→ Integration check:
  InvoiceSerializer.fields: [id, amount, status, created_at]
  InvoiceSchema (Zod): z.object({ id, amount, status, createdAt }) ← camelCase mismatch
  ⚠️ INTEGRATION: Django serializer uses snake_case, React schema uses camelCase.
     Ensure API client transforms keys (axios + camelcase-keys) or align naming.

→ REVIEW.md written at .planning/review/REVIEW.md
   Total: 1 BLOCKER, 5 WARNINGS, 1 INTEGRATION ISSUE
→ Run /release:review --fix to apply auto-fixes.
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
