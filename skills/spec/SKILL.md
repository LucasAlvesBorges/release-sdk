---
name: spec
description: >
  Clarify WHAT a phase delivers BEFORE discuss. Detects stack (Django / React TSX / fullstack),
  asks scope/boundary questions, produces SPEC.md with HIGH/MED/LOW ambiguity scoring.
  Use when: phase goal is fuzzy, scope-creep risk, or you want a sharper WHAT before /release:discuss.
---

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation.

---

# /release:spec — Stack-Aware Phase Specification

Sharpens WHAT a phase will deliver. Produces SPEC.md with explicit scope, exclusions, open questions, and an ambiguity score (HIGH/MED/LOW). Runs BEFORE `/release:discuss`.

## Usage

```
/release:spec 01                     # auto-detect stack, ask WHAT-questions
/release:spec 01 --django            # force backend spec dimensions
/release:spec 01 --react             # force frontend spec dimensions
/release:spec 01 --fullstack         # both dimension sets
```

> Previously: `--gsd-context` flag. Removed in v0.4.0 — use `/release:import` once to convert GSD planning files; all skills then assume release-sdk native format.

## When to use

- Phase goal in ROADMAP.md is vague ("improve checkout", "refactor auth").
- Multiple plausible interpretations of "done".
- High scope-creep risk (touches many domains).
- About to run `/release:discuss` and want WHAT locked before HOW.

Skip `/release:spec` and go straight to `/release:discuss` if:
- Goal already states a single observable outcome with a clear actor.
- Scope is unambiguous (e.g., "add `is_archived` field to InvoiceModel + migration").

## Detection

Same logic as `/release:plan` and `/release:discuss`:

1. Read `.release-planning/ROADMAP.md` → extract phase goal and tags.
2. Read existing phase artifacts in `.release-planning/phases/{NN}-{slug}/` if present.
3. Classify stack:

| Signal | Classification |
|---|---|
| `manage.py`, `models.py`, `serializers.py`, `Celery`, `migration`, `queryset` | `django` |
| `package.json` with `react`/`tsx`, `component`, `route`, `Zustand`, `TanStack Query` | `react` |
| Both detected, or goal references API + UI | `fullstack` |
| Neither clear | ask user via AskUserQuestion |

4. Apply `--django` / `--react` / `--fullstack` flags to override detection.

## Workflow

1. Load LOCK context: read `.release-planning/RELEASE-LOCKS.md` if exists, else `.release-planning/PROJECT.md`.
2. Load ROADMAP phase entry, REQUIREMENTS.md, and (if present) prior SPEC/CONTEXT artifacts.
3. Spawn `release:spec-clarifier` agent with detected stack + LOCK context.
4. Agent runs stack-aware WHAT-questions via `AskUserQuestion` — **at least 5 domain-clarifying questions
   (mandatory floor)**, of which ≥2 probe the business domain and ≥1 is an explicit "out of scope".
5. Agent writes `{phase_dir}/{NN}-SPEC.md` from `templates/SPEC.md`.
6. Skill verifies output, prints ambiguity verdict, recommends next step.
7. **Linear sync (only if the Linear MCP is connected):** mirror the spec into Linear as a `[spec]`
   issue whose body equals the `.md` (see *Linear sync* below). If no Linear MCP, skip silently.

## Backend WHAT dimensions (Django)

When stack = `django` or `fullstack`, the clarifier probes:

1. **Data shape** — new model? extension? what fields are user-observable?
2. **Endpoint surface** — which HTTP verbs/paths are in scope? bulk ops?
3. **Permission/role boundary** — who can call this? admin-only? tenant-member?
4. **Tenancy scope** — single-tenant? cross-tenant view? tenant cascade?
5. **Side effects** — Celery tasks? signals? notifications? webhooks?
6. **Acceptance signal** — what UAT-observable behavior proves "done"?
7. **Out of scope** — what nearby capability is explicitly NOT in this phase?

## Frontend WHAT dimensions (React)

When stack = `react` or `fullstack`, the clarifier probes:

1. **Page/route surface** — new route? modal? inline? which user journey?
2. **State scope** — new Zustand slice? extend existing? TanStack Query keys?
3. **Optimistic UI** — optimistic mutation? rollback strategy? loading skeleton?
4. **Form/validation shape** — react-hook-form + Zod schema fields?
5. **Error/empty/loading UX** — what does the user see in each state?
6. **Accessibility floor** — keyboard nav? screen reader labels? focus traps?
7. **Out of scope** — what nearby UI is explicitly deferred?

## Fullstack

Runs both dimension sets. Groups questions to avoid cognitive overload:
- Backend WHAT first (1-7 above)
- Frontend WHAT second (1-7 above)
- Integration WHAT last: API contract, auth handoff, error propagation

Decisions captured as numbered open questions Q-XX in SPEC.md (not D-XX — those come from `/release:discuss`).

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-SPEC.md

---
phase: {NN}
slug: {phase-slug}
stack: django | react | fullstack
ambiguity_score: HIGH | MED | LOW
ready_for_discuss: true | false
linear_issue: {Linear issue URL if synced, else omit}
---

# Phase {NN} Spec: {phase-name}

## Goal
{One paragraph — observable outcome.}

## Stack Detection
- Detected: {django | react | fullstack}
- Signals: {what files/keywords drove the detection}
- LOCK context: {.release-planning/RELEASE-LOCKS.md or .release-planning/PROJECT.md}

## Scope (in)
- {Capability 1}
- {Capability 2}

## Scope (out)
- {Excluded thing} — deferred / not part of product

## Acceptance Criteria
- [ ] {Observable behavior 1}
- [ ] {Observable behavior 2}

## Open Questions

### HIGH (must resolve in /release:discuss)
1. {Question} — options: A {tradeoff}, B {tradeoff}

### MED (should resolve in /release:discuss)
1. {Question}

### LOW (Claude's discretion acceptable)
1. {Question}

## Ambiguity Score
**Score:** HIGH | MED | LOW

- LOW (0-3 open questions, all MED/LOW): proceed to /release:discuss.
- MED (4-6 open questions, ≤2 HIGH): /release:discuss will be substantive.
- HIGH (7+ open questions OR ≥3 HIGH): consider splitting phase or running /gsd-explore first.

## Next
→ `/release:discuss {NN}`  (lock D-XX decisions)
```

## Linear sync (auto — only when a Linear MCP server is connected)

After SPEC.md is written and verified, mirror it into Linear so the team sees the spec where they plan.
This is **optional and conditional** — it runs only if a Linear MCP server is connected this session.

1. **Detect.** Check whether a Linear MCP create-issue tool is available (e.g. `mcp__linear__create_issue`)
   — load it via `ToolSearch` (`"select:mcp__linear__create_issue"`, or keyword `"linear create issue"`).
   If no Linear MCP tool resolves, **skip silently**: Linear is optional, never block the spec on it.
2. **Read the just-written `{phase_dir}/{NN}-SPEC.md` verbatim.**
3. **Idempotency first.** Search Linear for an open issue whose title starts with `[spec] Phase {NN}:`
   (e.g. `mcp__linear__list_issues` / search). If one exists → **update** its description; else **create**.
4. **Create / update the issue:**
   - **Title:** `[spec] Phase {NN}: {phase-name}` — the `[spec]` prefix marks release-sdk specs.
   - **Description:** the **exact** Markdown body of `{NN}-SPEC.md` — byte-for-byte, no summarizing, no
     reformatting, no truncation. The Linear issue text MUST equal the `.md`.
   - **Team / project:** use `.release-planning/PROJECT.md` `linear_team:` if present; else the MCP's
     default/first team; else ask once via `AskUserQuestion`.
5. **Record back.** Write the returned issue URL into the SPEC.md frontmatter `linear_issue:` field and
   print it. The `.md` on disk stays the source of truth; Linear is a mirror with identical text.

> Re-running `/release:spec {NN}` after edits re-syncs: same `[spec] Phase {NN}:` issue, description
> overwritten to match the new `.md`. No duplicates.

## Example

```
/release:spec 03

→ Reading ROADMAP.md Phase 03: "Invoice export with filters"
→ Detected stack: FULLSTACK (manage.py + package.json with react)
→ Reading .release-planning/RELEASE-LOCKS.md for LOCK context

→ Spawning release:spec-clarifier...

→ Backend WHAT questions:
  Q1: Which export formats? [CSV / XLSX / PDF / all]      → CSV + XLSX
  Q2: Sync endpoint or Celery-backed download?            → Celery (>1k rows)
  Q3: Permission boundary?                                → tenant-members only
  Q4: Out of scope?                                       → no scheduled exports

→ Frontend WHAT questions:
  Q5: Trigger from list page or dedicated screen?         → list page action menu
  Q6: Progress UI for async job?                          → toast + polling
  Q7: Out of scope?                                       → no email-on-completion

→ Integration WHAT:
  Q8: Job-status endpoint shape?                          → GET /api/exports/{id}/

→ Writing .release-planning/phases/03-invoice-export/03-SPEC.md
  Ambiguity score: MED (6 questions, 1 HIGH)
  ready_for_discuss: true

→ Linear MCP detected → upserted issue "[spec] Phase 03: Invoice export with filters" (description = 03-SPEC.md, byte-for-byte)
  linear_issue: https://linear.app/acme/issue/ENG-412
  (no Linear MCP connected → this step is skipped silently)

→ Next: /release:discuss 03
```
