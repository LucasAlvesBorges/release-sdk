# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] — 2026-05-25

### Added

- **`/release:auto`** — freeform-intent router. Reads the user's prompt + `.release-planning/` state and dispatches to the right `/release:*` skill (20 routes covering import / status / init / spec / discuss / plan / execute / review / verify / verify-work / secure-phase / security / ui-phase / ai-phase / workstreams / checklist / ship / debug / quick / fast). Always prints the chosen route + a 1-line reason before invoking; falls back to `AskUserQuestion` when classification confidence is low. Mirrors GSD's `gsd-progress` "unified situational command" pattern.
- **`/release:debug`** — persistent debug session under `.release-planning/debug/{session_id}/`. Survives `/clear` via checkpoint protocol. Stack-aware (django / react / fullstack) dispatch to the existing `release-debugger` agent.
- **`/release:fast`** — trivial inline task execution. No subagents, no phase machinery, no state writes. Clean-worktree gate + atomic commit. For < 30 LOC single-file edits where the work is faster than planning it.
- **`/release:quick`** — bounded multi-file task with atomic commits + light state tracking (logs to `.release-planning/quick-log.md`) but skips the SPEC / DISCUSS / PLAN heavy envelope. Spawns `release-tdd-executor` in `quick_mode`. Cursor untouched.
- **`/release:ship`** — final PR gate for verified phases. Pre-ship review via `release-code-reviewer`, PR title + body grounded in `{NN}-SPEC.md` / `{NN}-PLAN.md` / `{NN}-UAT.md`, `gh pr create`, then moves `.release-planning/STATE.md` cursor to `shipped`. Never auto-merges. Refuses to ship anything not at `active_stage: verified`.

### Notes

- All four new skills (`debug`, `fast`, `quick`, `ship`) are native to release-sdk and live under the `/release:*` namespace; `/release:auto` no longer falls back to `/gsd:*` for any route.
- `/release:auto` is opt-in. Nothing else in release-sdk depends on it.

## [0.5.0] — 2026-05-25 — BREAKING

### Changed

- **BREAKING**: Renamed planning directory from `.planning/` to `.release-planning/` to avoid conflict with upstream GSD, which also uses `.planning/`. Projects with both tools can now coexist without file collisions.
  - All release-sdk skills (`/release:init`, `/release:spec`, `/release:plan`, `/release:execute`, `/release:review`, `/release:ui-phase`, `/release:ai-phase`, `/release:status`, `/release:ship`, etc.) now read and write under `.release-planning/`.
  - `/release:import` is the bridge: reads GSD `.planning/` (untouched) and writes release-sdk artifacts to a parallel `.release-planning/` tree.
  - `release-import-orchestrator` agent rewritten with explicit source/dest separation: `.planning/` for READS, `.release-planning/` for WRITES. Idempotency check moved from `.planning/RELEASE-LOCKS.md` to `.release-planning/RELEASE-LOCKS.md`. State updates write to `.release-planning/STATE.md`; GSD's `.planning/STATE.md` is never touched.

### Migration

- **Standalone release-sdk projects** (no GSD): `mv .planning .release-planning`. No content change needed.
- **GSD-imported projects**: re-run `/release:import` after upgrading. The orchestrator now writes the parallel `.release-planning/` tree and leaves GSD `.planning/` untouched. Old `.planning/RELEASE-LOCKS.md` and `{NN}-*.md` siblings from a prior import can be removed once `.release-planning/` is populated.
- **Mixed setups**: both `.planning/` (GSD) and `.release-planning/` (release-sdk) can now live in the same repo.

## [0.4.0] — 2026-05-25

### Added

- **`/release:import`** — one-shot mass importer that converts an existing GSD `.release-planning/` tree into release-sdk native format. Single pass:
  - Project-level: extracts LOCK-01..LOCK-12 from `PROJECT.md`/`ARCHITECTURE.md`/`CONVENTIONS.md`/`config.json` → writes `.release-planning/RELEASE-LOCKS.md` with `[EXTRACTED]` / `[INFERRED]` / `[MISSING]` status per LOCK.
  - Phase-level: globs `.release-planning/phases/*/`, detects stack (Django / React / fullstack) from PLAN/SPEC content, ports `SPEC.md` → `{NN}-SPEC.md` (stack-aware ambiguity), `CONTEXT.md` → `{NN}-CONTEXT.md` (preserves D-XX), `PLAN.md` → `{NN}-PLAN.md` (injects RC1-RC7 + Q1-Q7 + 9-cat security), `VERIFICATION.md` → `{NN}-VERIFICATION.md` + `{NN}-UAT.md` (splits machine vs user-observable items).
  - Stubs (never fabricated): seeds `{NN}-UI-SPEC.md` for React/fullstack phases, `{NN}-AI-SPEC.md` for LLM phases, `{NN}-SECURITY.md` placeholders — all flagged `ready_for_plan: false` with `[NEEDS REVIEW]`.
- **`release-import-orchestrator`** agent — drives the mass port. Read-only against GSD originals; writes release-sdk siblings alongside.
- Flags: `--dry-run`, `--force` (re-import with AskUserQuestion confirmation), `--phases=NN[,NN]`, `--no-stubs`.

### Removed — BREAKING

- **`--gsd-context` flag** removed from `release-init`, `release-spec`, `release-ui-phase`, `release-ai-phase`, `release-plan`, `release-review`. Runtime translation of GSD artifacts is replaced by the one-shot `/release:import`. Migration: run `/release:import` once; all skills then assume release-sdk native format.
- Sections removed: `GSD Context Mode (--gsd-context)`, `Co-installed GSD plugin (--gsd-context)`, Steps 1–7 of GSD-presence check in `release-init`.

### Changed

- `release-init` is now scoped strictly to greenfield project initialization. For imports, use `/release:import` first.
- README slash-commands table now shows `/release:import` as the first command.

## [0.3.0] — 2026-05-25

### Added — close upstream GSD gaps with 6 new skills + 2 hooks

**Skills**

- `/release:spec {NN}` — clarifies WHAT a phase delivers before `/release:discuss`. Produces `SPEC.md` with HIGH/MED/LOW ambiguity scoring. Stack-aware (Django / React / fullstack).
- `/release:ui-phase {NN}` — design contract for React phases. Produces `UI-SPEC.md` with component inventory, routes, state contracts (loading/empty/error/success), a11y contract, performance budgets (LCP/TTI/INP), optimistic UI plan. React-only guard at skill + agent layer.
- `/release:verify-work {NN}` — conversational UAT walkthrough. Renders stack-specific verification scripts (Django curl + manage.py shell, React browser walk + a11y keyboard, fullstack e2e). PASS / FAIL / BLOCKED / SKIP per item. Resumable.
- `/release:secure-phase {NN}` — retroactive threat-mitigation audit. Greps shipped source for every threat declared in PLAN.md against a 9-category scorecard. Verdict: PASS / FLAG / BLOCK with file:line evidence.
- `/release:ai-phase {NN}` — AI-SPEC.md design contract for LLM features. Defaults to Anthropic SDK (`claude-sonnet-4-6`) with prompt caching, native tool use, SSE streaming via Django proxy (LOCK-09 httpOnly cookie enforced).
- `/release:workstreams [list|create|switch|status|progress|complete|resume|remove]` — top-level parallel feature isolation. Each workstream gets its own `.release-planning/workstreams/<name>/` namespace, `ws-<name>` branch, session-scoped active pointer.

**Agents**

- `release-spec-clarifier` — drives WHAT clarification via AskUserQuestion; refuses HOW questions to keep SPEC vs DISCUSS boundaries clean.
- `release-ui-researcher` — fingerprints design system (tailwind / shadcn / MUI / chakra / mantine), classifies 17 design dimensions LOCKED vs OPEN, batched AskUserQuestion for gaps only.
- `release-uat-conductor` — walks user through UAT items with stack-specific verification steps. Rewrites UAT.md after every answer (crash-resumable).
- `release-django-security-retro` — greps shipped Python for evidence of every T-XX threat across 9 categories + N+1 spot-check.
- `release-react-security-retro` — greps shipped `.tsx/.ts` for XSS, token storage, CSRF plumbing, IDOR, secret exposure, eval, Zod runtime validation.
- `release-ai-researcher` — validates LOCK-01 / 03 / 09 / 10 / 12 against AI integration plans; drafts prompt skeleton + Zod mirror + eval harness + `AILog` model. Appends to AI-SPEC.md (never overwrites).

**Templates**

- `SPEC.md` — rewritten stack-aware; HIGH/MED/LOW buckets replace numeric ambiguity scoring.
- `UI-SPEC.md` — new; 12.4 KB; `UI-DEC-XX` decisions grouped by composition / routing / state / a11y / perf / optimistic.
- `UAT.md` — new; ID / Item / Stack / Steps / Status / Notes / Verified At table.
- `SECURITY.md` — new retroactive scorecard with per-stack tables + drift detection vs author-time SECURITY.md.
- `AI-SPEC.md` — new; framework choice + hosting architecture + prompt contract + evaluation strategy + guardrails + production monitoring.
- `WORKSTREAM-STATE.md` — new per-workstream state file with YAML frontmatter (name, stack, branch, owner, status, cursor, blockers) + phase index table.

**Hooks**

- `release-read-injection-scanner.js` — PreToolUse:Read. Scans files (.py/.ts/.tsx/.js/.jsx/.json/.md/.yaml/.toml/.sh/.html/.css/.sql, <1 MB) for prompt-injection patterns: ignore-previous-instructions, role overrides, `<|system|>`, XML role tags, long base64 near decode/exec keywords, exfiltration language, zero-width chars (U+200B/200C/200D/FEFF). Pattern names only in warnings, never file contents. Disable via `RELEASE_SDK_READ_INJECTION_SCAN=0`.
- `release-context-monitor.js` — PostToolUse:*. Tracks tool-call count per session; warns once at 50 (moderate) / 100 (consider `/release:pause-work`) / 150 (critical, auto-compaction imminent). State at `.claude-plugin-cache/release-context-monitor-<session_id>.json`. Disable via `RELEASE_SDK_CONTEXT_MONITOR=0`.

### Changed

- README updated with new commands + hooks tables.
- Plugin manifest version bumped 0.2.0 → 0.3.0 in both `plugin.json` and `marketplace.json`.
- Marketplace description expanded to cover new capabilities.

### Fixed

- Casing of GitHub repo in manifests (`lucasalvesborges` → `LucasAlvesBorges`) so marketplace install URLs match canonical GitHub path.

## [0.2.0] — 2026-05-25

### Added

- Initial release: full-stack Django + React TSX acceleration plugin.
- 9 `/release:*` skills, 9 `/django:*` skills, 25 specialized agents, 7 hooks.
- Branch-per-phase logic in executors.
- Worktree-isolated parallel planning for fullstack phases.
- `release-wave-executor` agent for intra-phase parallel TDD execution.
- 9-category security audit (Django + React).
- RC1-RC7 + Q1-Q7 author checklists.
- N+1 detection, race-condition guards, XSS / auth-token security.
