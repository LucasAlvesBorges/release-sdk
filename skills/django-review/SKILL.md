---
description: >
  Adversarial Django code review — finds N+1 queries, mass assignment, missing select_related/prefetch_related,
  RLS bypass, lost-update races, .delay() instead of .delay_on_commit(), @csrf_exempt on auth endpoints.
  Use when: reviewing PR diff, auditing recently-modified Django files, pre-merge quality gate.
allowed_tools: Agent, Read, Bash, Grep, Glob
---

# /django:review — Adversarial Django Code Review

Reviews Django/DRF source files for bugs, security issues, performance anti-patterns. Produces REVIEW.md with BLOCKER/WARNING/INFO classification.

## Usage

```
/django:review backend/apps/financeiro/views.py
/django:review backend/apps/financeiro/ --depth=deep
/django:review --diff main..HEAD --depth=standard
```

## Arguments

- `$ARGUMENTS` — Paths to review (file, directory, or git diff range)
- `--depth=quick|standard|deep` — Review depth (default: standard)
- `--review-path=PATH` — Where to write REVIEW.md (default: `./REVIEW.md`)
- `--fix` — After review, invoke django-code-fixer to apply Critical+Warning fixes

## Workflow

1. Parse arguments — resolve files to review
2. Spawn `django-code-reviewer` agent with:
   - `files`: resolved file list
   - `depth`: requested depth
   - `review_path`: output location
3. Agent produces REVIEW.md
4. If `--fix` flag: spawn `django-code-fixer` agent with `review_path` to apply fixes
5. Report back to user: BLOCKER count, WARNING count, fix summary

## Output

`REVIEW.md` with:
- YAML frontmatter (findings counts, status)
- Blocker findings (BLOCKER classification, must-fix)
- Warning findings (should-fix)
- Info findings (style, naming, dead code)
- Concrete fix snippets for every BLOCKER and WARNING

## Example

```
/django:review backend/apps/abastecimento/

→ Spawning django-code-reviewer (depth=standard)
→ 4 files reviewed
→ REVIEW.md created at .planning/review/REVIEW.md

Found:
  - 2 Blockers (mass_assignment in serializer, missing TenantModel inheritance)
  - 5 Warnings (3 N+1, 1 missing select_related, 1 .delay() instead of .delay_on_commit())
  - 3 Info

Run /django:review --fix to apply auto-fixes.
```
