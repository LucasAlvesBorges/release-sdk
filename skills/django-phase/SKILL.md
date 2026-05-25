---
description: >
  CRUD for phases in ROADMAP.md — add, insert, remove, edit phase entries. Maintains dependency
  graph consistency. Creates/removes corresponding .planning/phases/{NN}-{slug}/ directory.
  Use when: scoping new feature, re-prioritizing roadmap, removing canceled phase.
allowed_tools: Read, Write, Edit, Bash, AskUserQuestion
---

# /django:phase — Roadmap Phase CRUD

Add, insert, remove, or edit phases in ROADMAP.md. Keeps dependencies + directory structure in sync.

## Usage

```
/django:phase add "Estorno workflow"           # appends as next phase
/django:phase insert 03 "Critical fix"         # inserts at position 03, shifts 03→04, 04→05...
/django:phase remove 07                        # removes Phase 07, archives directory
/django:phase edit 02 --goal="..."             # update phase metadata
/django:phase list                             # show all phases compact
```

## Subcommands

### add — append new phase

```
/django:phase add "{goal in one line}"
```

Asks:
- Slug (auto-generated from goal, user can override)
- Requirements covered (REQ-XX list, optional)
- Depends on (which phases must complete first)
- Estimated size (S/M/L)

Creates:
- New entry in ROADMAP.md `## Phases` (numbered next available)
- `.planning/phases/{NN}-{slug}/` directory

Commits:
```
docs: add phase {NN} ({slug})
```

### insert — insert at specific position

```
/django:phase insert 03 "Critical security fix"
```

Inserts at position 03, shifts existing 03 → 04, 04 → 05, etc.

Updates:
- All ROADMAP.md phase numbers
- All `depends_on` references that point to shifted phases
- Renames `.planning/phases/{NN}-{slug}/` directories

Commits:
```
docs: insert phase 03 ({slug}), shift 03+ → 04+
```

### remove — delete phase

```
/django:phase remove 07
```

Confirms:
- Is phase complete? (cancel removal if so — use `/django:phase archive` instead)
- Are downstream phases depending on it? (shows list, asks confirmation)

Then:
- Removes ROADMAP entry
- Moves `.planning/phases/{NN}-{slug}/` to `.planning/phases/_removed/{NN}-{slug}/`
- Renumbers subsequent phases
- Updates depends_on references

Commits:
```
chore: remove phase {NN} ({slug})
```

### edit — modify metadata

```
/django:phase edit 02 --goal="new goal"
/django:phase edit 02 --requirements=REQ-04,REQ-05
/django:phase edit 02 --depends-on=01,03
```

Updates specific fields without disturbing others. Commits.

### list — compact view

```
/django:phase list
```

Output:
```
01  veiculo-bulk-import       in-execute    REQ-02         depends:01        M
02  abastecimento-planilha    not-started   REQ-03,REQ-04  depends:01        M
03  estorno-workflow          not-started   REQ-07         depends:02        S
04  daily-fueling-grid        not-started   REQ-05         depends:02        L  ⚠ split
```

## Validation

Every operation runs:
- Dependency cycle check (no A → B → A)
- Coverage audit (any REQ uncovered after remove?)
- Numbering consistency (no gaps, no duplicates)

If violation:
- Cycle → blocked, ask user to break cycle
- Coverage gap → warn, ask whether to add replacement phase
- Numbering → auto-renumber

## Phase directory structure

When phase is added:
```
.planning/phases/{NN}-{slug}/
  (empty initially)
```

Populated by subsequent workflows:
- `/django:discuss {NN}` → `{NN}-CONTEXT.md`
- `/django:plan {NN}` → `{NN}-PLAN.md`, `{NN}-RESEARCH.md`, `{NN}-PATTERNS.md`, `{NN}-PLAN-CHECK.md`
- `/django:execute {NN}` → `{NN}-SUMMARY.md`
- `/django:security {NN}` → `{NN}-SECURITY.md`
- `/django:checklist {NN}` → `{NN}-CHECKLIST.md`
- `/django:verify {NN}` → `{NN}-VERIFICATION.md`

## Example

```
/django:phase add "Estorno workflow with race-protected saldo restoration"

→ Auto-slug: estorno-workflow
   Override? [Enter to accept] >
   
→ Requirements covered (comma-separated, or none):
   > REQ-07

→ Depends on (comma-separated phase numbers, or none):
   > 02

→ Estimated size [S/M/L]:
   > S

→ Phase 06 added:
   Goal: Estorno workflow with race-protected saldo restoration
   Slug: estorno-workflow
   Covers: REQ-07
   Depends: Phase 02
   Size: S

→ Created .planning/phases/06-estorno-workflow/
→ Committed: docs: add phase 06 (estorno-workflow)

→ Next: /django:discuss 06
```
