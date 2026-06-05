---
name: docs-update
description: >
  Generate or update project documentation (README, CONTRIBUTING, ARCHITECTURE, ONBOARDING)
  grounded in .release-planning/ artifacts and verified against the live codebase. Spawns
  doc-writer + doc-verifier in parallel per in-scope doc; STALE claims trigger
  rewrites; commits as `docs: regenerate ... verified`.
  Use when: docs are out of date, onboarding a new contributor, or post-milestone cleanup.
---

# /release:docs-update — Verified Documentation Refresh

Regenerates user-facing docs (README, CONTRIBUTING, ARCHITECTURE, ONBOARDING) from the project's
`.release-planning/` artifacts and proves every factual claim against the live codebase. Output
is committed only after all STALE claims are healed.

This skill is the docs-only counterpart of `/release:ingest-docs` (which absorbs external planning
docs into `.release-planning/`). Where ingest pulls IN, docs-update writes OUT.

## Usage

```
/release:docs-update                                # write/update README + CONTRIBUTING + ARCHITECTURE in repo root, verified
/release:docs-update --doc README                   # only README
/release:docs-update --doc ARCHITECTURE,ONBOARDING  # subset
/release:docs-update --verify-only                  # verify existing docs without rewriting (read-only)
/release:docs-update --mode supplement              # append rather than overwrite (writer mode=supplement)
/release:docs-update --no-commit                    # write to working tree but do not git commit
/release:docs-update --strict                       # any UNVERIFIABLE claim in writer output → second rewrite pass
```

Flags compose: `/release:docs-update --doc README --verify-only` checks README's current claims
without invoking the writer.

## When to use

- The project diverged from the README months ago — facts in the doc no longer match code.
- A new contributor is starting and ONBOARDING.md is stale or absent.
- Post-milestone: docs should reflect the just-shipped architecture.

Do NOT use if:
- The project has no `.release-planning/` directory — run `/release:init` first (the writer needs
  PROJECT.md + ROADMAP.md to ground claims).
- You want planning-doc INGESTION — that's `/release:ingest-docs` (different pipeline).

## Pre-checks (hard gates)

1. **Planning artifacts present:** `{repo_root}/.release-planning/PROJECT.md` MUST exist.
   - Missing → abort: "No `.release-planning/PROJECT.md` found. Run `/release:init` (new project)
     or `/release:import` (existing GSD project) first."
2. **Doc scope is valid:** if `--doc=X[,Y]` is set, each entry must be in
   `{README, CONTRIBUTING, ARCHITECTURE, ONBOARDING, API}`. Unknown → abort and list valid types.
3. **Git tree clean for commit:** if `--no-commit` is NOT set, working tree should have no
   uncommitted changes outside `.release-planning/`. Dirty tree → warn but proceed (writer +
   verifier only touch the target docs; commit step will be a separate commit).
4. **Verify-only path exists:** if `--verify-only` is set, every targeted doc must already exist.
   Missing → abort.

## Scope resolution

Default scope (no `--doc` flag): `[README, CONTRIBUTING, ARCHITECTURE]`. ONBOARDING is opt-in
because it depends on stable team conventions.

For each doc in scope, target path is:
- `README` → `{repo_root}/README.md`
- `CONTRIBUTING` → `{repo_root}/CONTRIBUTING.md`
- `ARCHITECTURE` → `{repo_root}/ARCHITECTURE.md` (or `{repo_root}/docs/ARCHITECTURE.md` if `docs/` exists)
- `ONBOARDING` → `{repo_root}/ONBOARDING.md` (or `{repo_root}/docs/ONBOARDING.md`)
- `API` → `{repo_root}/docs/API.md` (always under `docs/`)

Stack from `.release-planning/PROJECT.md` `stack:` field is passed through to every writer
spawn — the writer uses it to pick the right probes.

## Pipeline (default — write + verify + heal)

```
phase 1: writer wave (parallel)
  for each doc in scope:
    spawn release:doc-writer (doc_assignment built per type/mode/scope)

phase 2: verifier wave (parallel)
  for each doc just written:
    spawn release:doc-verifier (doc_path = target_path)

phase 3: heal pass (sequential, only for docs whose verifier reported STALE)
  for each stale doc:
    spawn release:doc-writer with mode=update, doc_assignment.must_cover augmented with
      the STALE claims and the verifier's evidence
    re-run release:doc-verifier
    if still STALE after one heal pass → flag for human review, do NOT loop infinitely

phase 4: commit (unless --no-commit)
  git add {doc paths}
  git commit -m "docs: regenerate {doc list} verified against codebase"
```

The heal pass runs at most once per doc. A doc still STALE after one heal is left in the working
tree with its `.verify.json` sidecar — the user resolves manually.

## Pipeline (--verify-only)

```
phase 1: verifier wave (parallel)
  for each doc in scope (must already exist):
    spawn release:doc-verifier

phase 2: report
  print one-line summary per doc + verdict
  do NOT modify any doc
  do NOT commit
  return non-zero (semantically) if any verdict ≠ PASS so calling skills can branch
```

## doc_assignment construction

For each in-scope doc, build a `doc_assignment` block (passed verbatim to release:doc-writer):

```yaml
doc_assignment:
  type: README | CONTRIBUTING | ARCHITECTURE | ONBOARDING | API
  mode: {create | update | supplement}    # create if target missing; else from --mode flag
  target_path: {absolute path}
  scope: {one-line per-doc — see scope_lines table below}
  audience: {per-doc audience — see audience table below}
  must_cover: {per-doc bullets — see must_cover table below}
  must_avoid:
    - marketing copy
    - AI-generated commentary
    - future-tense aspirations not in ROADMAP.md
  stack: {from PROJECT.md}
```

### Scope lines

| Type | scope |
|------|-------|
| README | monorepo entry + how to run + repo layout + link out to deeper docs |
| CONTRIBUTING | local setup + branching + code style + tests + PR checklist |
| ARCHITECTURE | system overview + multi-tenancy + auth model + data flow + key conventions |
| ONBOARDING | new contributor 1-hour path — setup, tests, codebase tour, first change |
| API | enumerated endpoints — method/path/auth/serializer reference |

### Audience

| Type | audience |
|------|----------|
| README | external_consumer |
| CONTRIBUTING | new_contributor |
| ARCHITECTURE | maintainer |
| ONBOARDING | new_contributor |
| API | external_consumer |

### must_cover

| Type | must_cover bullets |
|------|--------------------|
| README | name + tagline; stack with versions; quickstart commands; repo layout; link to CONTRIBUTING + ARCHITECTURE; license |
| CONTRIBUTING | local setup; branching policy (from intel/CONVENTIONS.md if present); code style; test commands; PR checklist |
| ARCHITECTURE | system diagram (text); multi-tenancy model; auth model; request lifecycle; deployment topology |
| ONBOARDING | repo TL;DR; environment setup; test suite run; top-5 directory tour; first-change pattern |
| API | base URL; auth flow; endpoint table (method, path, description, auth) |

## Heal-pass doc_assignment augmentation

When phase 3 fires for a stale doc, augment the original `doc_assignment` with:

```yaml
doc_assignment:
  ...original fields...
  mode: update
  must_cover:
    - ...original must_cover items...
    - REWRITE: section containing claim "{C-XXX from verifier}"
      reason: "verifier marked STALE — probe: {probe used}, evidence: {evidence or null}"
  must_avoid:
    - ...original items...
    - the specific stale claim values from verifier (so writer doesn't reintroduce them)
```

The writer then drops/replaces only the stale sections — the rest of the doc is untouched
(diff-friendly).

## Commit message format

```
docs: regenerate {comma-separated doc types} verified against codebase

Refreshed via /release:docs-update.
Claims verified per release:doc-verifier sidecars (see {doc}.verify.json).
Stack: {django | react | fullstack}
```

Body is plain — no AI commentary, no co-author attribution unless project convention requires it.

## Output

Working tree changes:
- `{target_path}` for each in-scope doc (newly written or rewritten)
- `{target_path}.verify.json` sidecar per doc

Console summary at end:

```
docs-update summary
  README        → wrote 142 lines, verifier PASS (V:38 S:0 U:2)
  CONTRIBUTING  → wrote 89 lines, verifier PASS (V:21 S:0 U:0)
  ARCHITECTURE  → wrote 211 lines, verifier STALE → heal pass → PASS (V:54 S:0 U:3)

committed: docs: regenerate README, CONTRIBUTING, ARCHITECTURE verified against codebase
```

## Constraints

- DO NOT modify source code, configs, migrations, or tests.
- DO NOT auto-resolve heal failures — surface them and stop.
- DO NOT commit unless every target doc's final verifier verdict is `PASS` (or
  `UNVERIFIABLE_HEAVY` with explicit user override — for now, treat as non-commit).
- Verifier sidecars (`.verify.json`) are tracked artifacts during a run but should NOT be
  committed unless the project keeps them under version control by convention.
- Heal pass runs at most once per doc — never loop indefinitely.
- Skill is read-only with respect to `.release-planning/` (it reads PROJECT.md, ROADMAP.md, etc.
  but never modifies them).

## Routing

This skill orchestrates two release-* sub-agents:
- `release:doc-writer` — one spawn per in-scope doc per pass (initial + heal).
- `release:doc-verifier` — one spawn per in-scope doc per pass.

Both are stack-agnostic in the orchestrator — the stack value is passed through from
`.release-planning/PROJECT.md` into each spawn. Sub-agents handle stack-specific probes
internally.

## Example

```
/release:docs-update --doc README,ARCHITECTURE

→ Stack: fullstack (django + react-tsx)
→ Pre-checks: .release-planning/PROJECT.md present ✓
→ Phase 1 (writer wave, parallel):
   release:doc-writer → README (mode=update, target=/repo/README.md)
   release:doc-writer → ARCHITECTURE (mode=create, target=/repo/ARCHITECTURE.md)
→ Phase 2 (verifier wave, parallel):
   release:doc-verifier → README.verify.json (PASS — V:36 S:0 U:1)
   release:doc-verifier → ARCHITECTURE.verify.json (STALE — V:48 S:2 U:3)
→ Phase 3 (heal pass):
   release:doc-writer → ARCHITECTURE (mode=update, must_cover augmented with STALE C-014, C-027)
   release:doc-verifier → ARCHITECTURE.verify.json (PASS — V:51 S:0 U:3)
→ Phase 4: commit
   docs: regenerate README, ARCHITECTURE verified against codebase

Summary:
  README        wrote 138 lines  verifier PASS
  ARCHITECTURE  wrote 207 lines  verifier PASS (after 1 heal pass)
```

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from
`.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). The writer
uses stack to pick the right code probes; the verifier uses stack to bias which file globs and
package manifests it consults first. No per-stack skill variants exist — one orchestrator covers
all three.
