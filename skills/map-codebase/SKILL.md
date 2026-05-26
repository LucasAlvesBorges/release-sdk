---
name: map-codebase
description: >
  Analyze the codebase with parallel mapper agents (tech, arch, quality, concerns) to produce
  structured analysis documents under `.release-planning/codebase/`. Stack-aware (django/react/fullstack).
  Use when: starting research on a phase, onboarding to a new repo, refreshing context after major refactors.
allowed_tools: Agent, Read, Write, Bash, Grep, Glob
---

# /release:map-codebase — Parallel Codebase Mapper

Spawns parallel `release-codebase-mapper` agents — one per focus area — to produce structured
analysis documents under `.release-planning/codebase/`. Stack-aware: detects django, react, or
fullstack and adapts probes accordingly.

## Usage

```
/release:map-codebase                      # run all 4 focus areas in parallel
/release:map-codebase --focus tech         # only the tech-stack focus
/release:map-codebase --focus arch         # only the architecture focus
/release:map-codebase --focus quality      # only the code-quality focus
/release:map-codebase --focus concerns     # only the security/perf concerns focus
/release:map-codebase --refresh            # rewrite even if files already exist
```

## Pre-checks

Before spawning agents:

1. **`.release-planning/` exists.**
   ```bash
   test -d .release-planning || { echo "Run /release:init first"; exit 1; }
   ```

2. **Repo has source code.** Glob for code roots; if none → abort.
   ```bash
   has_source=$(find . -maxdepth 3 \( -name "*.py" -o -name "*.tsx" -o -name "*.ts" \) \
     -not -path "./node_modules/*" -not -path "./.venv/*" 2>/dev/null | head -1)
   [ -z "$has_source" ] && { echo "No source code detected; nothing to map"; exit 1; }
   ```

3. **Existing outputs without `--refresh`.** If a target file already exists and `--refresh`
   was not passed, skip that focus and report `(cached)` in the summary.

## Stack detection

The skill resolves stack in this order:

1. `.release-planning/PROJECT.md` — read `stack:` field from frontmatter
2. Fallback by globbing:
   - `manage.py` present → `django`
   - `package.json` + any `*.tsx` → `react`
   - Both present → `fullstack`
3. Pass detected stack to every spawned agent

## Execution

For each requested focus (default: all 4), spawn one `release-codebase-mapper` agent in
parallel. Each agent writes to a distinct output path so the spawns never race:

| Focus      | Output path                                       |
|------------|---------------------------------------------------|
| `tech`     | `.release-planning/codebase/STACK.md`             |
| `arch`     | `.release-planning/codebase/ARCHITECTURE.md`      |
| `quality`  | `.release-planning/codebase/QUALITY.md`           |
| `concerns` | `.release-planning/codebase/CONCERNS.md`          |

Spawn pattern (parallel — issue all Task tool calls in one assistant turn):

```
Task → release-codebase-mapper { focus: tech,     stack: <detected>, output_path: .release-planning/codebase/STACK.md }
Task → release-codebase-mapper { focus: arch,     stack: <detected>, output_path: .release-planning/codebase/ARCHITECTURE.md }
Task → release-codebase-mapper { focus: quality,  stack: <detected>, output_path: .release-planning/codebase/QUALITY.md }
Task → release-codebase-mapper { focus: concerns, stack: <detected>, output_path: .release-planning/codebase/CONCERNS.md }
```

`--focus X` collapses the spawn set to a single agent.

## Post-execution

After all agents return, the skill:

1. **One-line summary per output file** — read the file's frontmatter and print a digest line
   (focus, stack, top finding count).
2. **Commit** with all generated files staged:
   ```bash
   mkdir -p .release-planning/codebase
   git add .release-planning/codebase/
   git commit -m "chore(codebase): map {focus areas} into .release-planning/codebase/"
   ```
   Where `{focus areas}` is the comma-joined list of focuses actually written this run
   (e.g. `tech,arch,quality,concerns` or just `tech` for `--focus tech`).

If `--refresh` was not passed and every requested focus was cached, the skill prints
`(all outputs cached; pass --refresh to rewrite)` and skips the commit.

## Example output

```
/release:map-codebase

→ Pre-checks
   .release-planning/ ✓
   source detected: python + tsx ✓
   stack: fullstack (from PROJECT.md)

→ Spawning 4 mappers in parallel...
   [tech]     release-codebase-mapper → STACK.md
   [arch]     release-codebase-mapper → ARCHITECTURE.md
   [quality]  release-codebase-mapper → QUALITY.md
   [concerns] release-codebase-mapper → CONCERNS.md

→ All mappers returned (4/4 ok)
   STACK.md         — 5 languages, 12 frameworks, vitest+pytest
   ARCHITECTURE.md  — 4 django apps, 3 react features, REST API, Celery
   QUALITY.md       — ruff configured, tsc strict, 14 TODO, 2 long files (>500 LOC)
   CONCERNS.md      — auth: JWT cookie ✓, 3 N+1 risks, CORS open in dev

→ Commit
   chore(codebase): map tech,arch,quality,concerns into .release-planning/codebase/

→ Next: read .release-planning/codebase/*.md or run /release:discuss
```

## When to use

- **Starting a phase** — run before `/release:discuss` so the orchestrator has architecture
  context to reason against.
- **Onboarding** — first thing to run on an unfamiliar repo; produces a 4-doc snapshot.
- **Post-refactor refresh** — pass `--refresh` after a structural rewrite so subsequent
  research agents read the current shape.
- **Targeted re-map** — `--focus concerns` after a security audit, `--focus quality` after a
  lint/types overhaul.

## Output

```
.release-planning/codebase/
  STACK.md          # tech focus
  ARCHITECTURE.md   # arch focus
  QUALITY.md        # quality focus
  CONCERNS.md       # concerns focus
```

Each document is read-only relative to source — the mapper never edits code. Every claim in
the documents cites `file:line` so downstream agents (`release-feature-researcher`,
`release-pattern-mapper`, `release-feature-planner`) can jump to evidence.

---

## Stack dispatch

This skill spawns the merged `release-codebase-mapper` agent. Stack is inferred from
`.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`) and passed
to every spawned mapper. Each agent applies stack-specific probes and writes a single
document for its assigned focus.
