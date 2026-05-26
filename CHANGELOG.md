# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.10.1] — 2026-05-25

### Fixed — Skills not loading in Claude Code v2.1.142+

All 40 `skills/*/SKILL.md` files were missing the `name:` frontmatter field.
Claude Code v2.1.142 silently fails to register skills without `name:` —
result: `/release:*` autocomplete showed no skills in new sessions and
`/reload-plugins` reported only "1 skill" total across all installed plugins.

Added `name: <dirname>` to every SKILL.md in the plugin. Slug matches the
directory name (e.g. `skills/auto/SKILL.md` → `name: auto`).

Other plugins (claude-mem, caveman) had `name:` already; release-sdk relied on
dir-name inference which stopped working in recent Claude Code releases.

## [0.10.0] — 2026-05-25

### Added — Token tracker dashboard

New `/release:tokens` skill opens a local HTTP dashboard at `http://localhost:47777`
showing token usage, cost ($), cache hit ratio, and efficiency metrics for every
Claude Code turn — across sessions, models, projects, and skills.

**Files:**
- `bin/release-token-worker.js` — Node HTTP daemon, no external deps; JSONL storage at `~/.claude/token-tracker/events.jsonl`
- `bin/release-token-dashboard.html` — single-file UI, Chart.js via CDN, auto-refresh 5s
- `hooks/release-token-collector.js` — PostToolUse hook; parses transcript tail, POSTs new assistant `usage` events to `/event`
- `skills/tokens/SKILL.md` — `/release:tokens` skill entry (spawn worker + open browser)

**Endpoints:**
- `POST /event` — append usage event to JSONL
- `GET /api/stats?session_id=X` — aggregates by session/today/week/month/all-time + breakdown by model/project/skill + timeline
- `GET /api/health` — `{ok, port, pid}`
- `GET /` — dashboard

**Pricing table** (hardcoded in worker, $/Mtok): Opus 4.7 `15/75 cache 1.5/18.75`, Sonnet 4.6 `3/15 cache 0.3/3.75`, Haiku 4.5 `1/5 cache 0.1/1.25`.

**Privacy:** worker binds `127.0.0.1` only; records token counters, never message content.

**Port choice:** 47777 (claude-mem uses 37777 — no conflict).

### Fixed — Commit hook heredoc bypass

`hooks/django-validate-commit.sh` was rejecting `git commit -m "$(cat <<'EOF' ... EOF)"`
because the Conventional Commits regex ran on the raw `$CMD` string before shell
expansion, capturing the literal `$(cat <<'EOF'` token as the subject.

Now skips validation when MSG contains command substitution (`$(cat`) or heredoc
markers (`<<'`, `<<"`, `<<NAME`) — same fallback used for empty `-m` (interactive
editor case).

## [0.9.1] — 2026-05-25

### Changed — Agent taxonomy: stack-pure prefix

Three-tier naming makes stack-specificity explicit at the agent name:

- `release-*` — merged agents that accept `stack: django|react|fullstack` param
- `django-*` — Django-pure logic agents
- `react-*` — React-pure logic agents (new)

Renamed 4 React-only agents from `release-*` → `react-*`:

- `release-ui-researcher` → `react-ui-researcher`
- `release-ui-checker` → `react-ui-checker`
- `release-ui-auditor` → `react-ui-auditor`
- `release-react-security-retro` → `react-security-retro`

All `subagent_type` refs in skill files updated. `git mv` preserves history.

### Removed — 2 orphan django-* agents

- `django-plan-checker` — superseded by `release-plan-checker` (v0.7.0). Zero live spawn refs.
- `django-roadmapper` — zero live spawn refs.

Kept (live spawn refs): `django-discuss-orchestrator`, `django-checklist-verifier`.

## [0.9.0] — 2026-05-25

### BREAKING — Plugin rename + skill prefix drop

Plugin invocation prefix shortened from `/release-sdk:release-<x>` to `/release:<x>`. Requires reinstall.

#### Migration (required)

```
/plugin uninstall release-sdk@release-sdk
/plugin marketplace update LucasAlvesBorges/release-sdk
/plugin install release@release-sdk
```

After reinstall, all commands change form: `/release-sdk:release-debug` → `/release:debug`, `/release-sdk:release-plan` → `/release:plan`, etc.

#### Changed

- **`plugin.json`**: `name: "release-sdk"` → `name: "release"`. Repo/product name remains `release-sdk` (no GitHub rename).
- **All 39 release-* skill directories** renamed without `release-` prefix: `skills/release-<x>/` → `skills/<x>/`. Performed via `git mv` so commit history follows.

#### Removed — legacy django-* skill set (11 skills)

The unified release-* skills with stack dispatch (`stack: "django"`) have covered Django since v0.7.0. The parallel `django-*` skill tree was kept for migration; now removed.

- `skills/django-checklist/`
- `skills/django-discuss/`
- `skills/django-execute/`
- `skills/django-init/`
- `skills/django-phase/`
- `skills/django-plan/`
- `skills/django-review/`
- `skills/django-roadmap/`
- `skills/django-security/`
- `skills/django-status/`
- `skills/django-verify/`

Functionality preserved via `/release:init`, `/release:plan`, `/release:execute`, `/release:review`, `/release:verify`, etc, which detect Django stack from `STATE.md` / `CONTEXT.md`.

The four supporting `django-*` agents (`django-discuss-orchestrator`, `django-plan-checker`, `django-checklist-verifier`, `django-roadmapper`) are retained — they are spawned internally by `/release:discuss`, `/release:plan`, and `/release:checklist`.

## [0.8.1] — 2026-05-25

### Fixed — Agent isolation hardening

`gsd-*` agents from prior GSD installs (left in `~/.claude/agents/` or in project-scope `.claude/agents/` of GSD-imported repos) leak into the `subagent_type` list available to Claude. In sessions where both `gsd-debugger` and `release-debugger` are visible, Claude can substitute the GSD-named variant — bypassing release-sdk hooks, stack dispatch, and audit trail.

- **All 16 skills that spawn agents** now carry an `## Agent Policy (LOCKED)` block immediately after frontmatter forbidding `gsd-*` substitution and stating the `gsd-<x>` → `release-<x>` rule.
- **`/release:auto`** carries the extended policy with a full substitution map covering 16 explicit agent mappings.
- Affected skills: `release-ai-phase`, `release-auto`, `release-autonomous`, `release-debug`, `release-discuss`, `release-import`, `release-init`, `release-mvp-phase`, `release-plan`, `release-quick`, `release-review`, `release-ship`, `release-spec`, `release-ui-phase`, `release-undo`, `release-verify`.

No agent definitions, hooks, or routing rules changed. Defense-in-depth only.

## [0.8.0] — 2026-05-25

### Added — Wave 5: Django+React operational gap closure (8 new files)

Wave 5 closes the operational gap identified in the GSD v1.42 audit for Django+React projects. Adds milestone lifecycle, session handoff, dependency-aware undo, MVP vertical-slice planner, and wires four v0.7.0 orphan agents into their parent skills.

#### Milestone lifecycle (3 skills + 1 agent)

- **`/release:new-milestone`** (`skills/release-new-milestone/SKILL.md`) — initialize new milestone (v1.0 → v1.1). Bumps PROJECT.md milestone field, appends new ROADMAP.md section, optionally promotes backlog items to phases. Hard gate: zero phases in `executing`/`planned` in previous milestone.
- **`/release:complete-milestone`** (`skills/release-complete-milestone/SKILL.md`) — closes current milestone. Runs `release-milestone-auditor` (hard gate). Moves `phases/{NN}-{slug}/` → `milestones/{name}/phases/{NN}-{slug}/`. Generates `SUMMARY.md` (timeline, commits, LOC, D-XX, REQ coverage). Updates ROADMAP archive section.
- **`/release:audit-milestone`** (`skills/release-audit-milestone/SKILL.md`) — non-destructive standalone milestone audit. Writes timestamped `MILESTONE-AUDIT-{name}-{date}.md`. Read-only. Safe mid-milestone. `--hot-list` mode for compact view.
- **`release-milestone-auditor`** agent (`agents/release-milestone-auditor.md`) — cross-checks REQ → phase → UAT → verify. Classifies each requirement COVERED / PARTIAL / GAP with file:line evidence. Adversarial stance: assumes ≥1 REQ has incomplete coverage even if all phases marked shipped.

#### Session lifecycle (2 skills)

- **`/release:pause-work`** (`skills/release-pause-work/SKILL.md`) — captures session handoff at `.release-planning/sessions/{YYYY-MM-DD-HHhMM}/` with HANDOFF.md, cursor.yaml, git-state.txt, open-files.txt, context.md. Multi-session history (additive, never overwrites). No commits, no worktree mutations.
- **`/release:resume-work`** (`skills/release-resume-work/SKILL.md`) — restores context from a paused session. Interactive picker (most recent first), `--latest`, `--list`, `--clear-after`. Detects drift between paused cursor + current STATE.md, and between paused git state + current worktree. Never auto-executes the next-action command — prints it.

#### Rollback (1 skill)

- **`/release:undo`** (`skills/release-undo/SKILL.md`) — dependency-aware `git revert` (additive — never rewrites history). Three modes: default (HEAD), `--plan {NN.X}`, `--phase {NN}`. Reads per-phase MANIFEST.md to walk later phases and abort if any depends_on the target. `--force` to override. Cross-`main` boundary requires `--force` + warning.

#### MVP planner (1 skill)

- **`/release:mvp-phase`** (`skills/release-mvp-phase/SKILL.md`) — vertical-slice planner. Captures canonical user story (As a / I want to / So that, regex-validated), runs heuristic size check, offers SPIDR decomposition (Spoke / Paths / Interfaces / Data / Rules) for oversized stories. Deferred slices auto-append to ROADMAP Backlog. Then delegates to `/release:plan {NN} --mvp` (flag scheduled for v0.8.1 wire-in).

#### v0.7.0 orphan agents wired (4 edits)

- **`release-plan-checker`** now auto-spawned by `/release:plan` (backend, frontend, fullstack). Verdict gating: BLOCK → suggest `--revise`, WARN → log + proceed, PASS → commit. Replaces legacy `django-plan-checker` reference.
- **`release-assumptions-analyzer`** now auto-spawned by `/release:discuss` immediately after stack detection, BEFORE D-XX questioning. DP-XX prompts from `ASSUMPTIONS.md` surfaced as "Hidden assumption — confirm or override:" questions in the dim 1-10 batch.
- **`release-integration-checker`** now auto-spawned by `/release:verify` when ≥2 phases at stage `verified`/`shipped` in current milestone. Writes `.release-planning/INTEGRATION-CHECK.md` (milestone-scoped). Informational only — never gates per-phase verdict.
- **`release-framework-selector`** now auto-spawned by `/release:ai-phase` between Q1 (provider) and Q2 (hosting model) when AI-SPEC.md has no `framework:` field OR `--reselect-framework` passed. Selector's recommendation prefills Q1's answer.

### Changed

- **`/release:auto` routing table extended** from 32 to 39 rules. New routes cover all 7 Wave 5 skills with explicit state guards (`dirty_worktree`, `sessions/` presence, milestone phase counts, current-milestone shipping status).

### Notes

- Wave 5 closes the GSD-substitution gap for Django+React projects. After v0.8.0, release-sdk is a drop-in replacement for GSD on any Django+React stack.
- `/release:plan --mvp` flag (delegated by `/release:mvp-phase`) is scheduled for v0.8.1 — currently `/release:plan` ignores unknown flags. MVP ROADMAP mutations (Mode + SPIDR slice) already take effect and the planner reads them.
- No removals. Safe upgrade from v0.7.x.
- 7 new skills + 1 new agent + 4 wired skills = 12 files affected.

## [0.7.0] — 2026-05-25

### Added — GSD-gap closure (31 new files across 4 parallel waves)

Spawned via 4 parallel agent waves (each agent in clean context, isolated by output path), this release closes the gap audit against upstream GSD across **planning, discussion, execution, research, debug, UI, eval, audit, docs** axes.

#### P0 — Core loop (Wave 1)

- **`release-plan-checker`** agent (`agents/release-plan-checker.md`) — pre-execution goal-backward verifier; every PLAN task must trace to a SPEC goal + a D-XX/LOCK-XX; stack-aware gates (Django N+1/raw SQL/`fields='__all__'`; React `localStorage`-auth/type contracts); produces `{NN}-PLAN-CHECK.md` with PASS/FAIL verdict.
- **`release-assumptions-analyzer`** agent (`agents/release-assumptions-analyzer.md`) — deep codebase analysis for a phase before planning; surfaces hidden assumptions, ripple analysis, LOCK cross-check; emits `DP-XX` discuss prompts in `{NN}-ASSUMPTIONS.md`.
- **`/release:autonomous`** skill (`skills/release-autonomous/SKILL.md`) — runs all remaining phases sequentially through spec → discuss → plan → execute → verify-work; aborts on first verify failure; never auto-ships.
- **`release-integration-checker`** agent (`agents/release-integration-checker.md`) — cross-phase E2E workflow probe + data-contract check (DRF↔Zod for fullstack); produces `INTEGRATION-CHECK.md`.

#### P1 — Research completeness (Wave 2)

- **`release-research-synthesizer`** agent — consolidates parallel researcher outputs into `SUMMARY.md` with CONSENSUS/CONFLICT/UNIQUE buckets + deterministic agreement score.
- **`/release:map-codebase`** skill + **`release-codebase-mapper`** agent — parallel 4-focus codebase analysis (tech, arch, quality, concerns) producing `.release-planning/codebase/*.md`.
- **`release-project-researcher`** agent — pre-roadmap ecosystem research (competitors, reference architectures, pitfalls, regulatory) via WebSearch+WebFetch.
- **`release-domain-researcher`** agent — pre-eval domain expertise (practitioner criteria, failure modes, regulatory landscape, benchmarks) for AI phases.
- **`release-intel-updater`** agent — cached intel files at `.release-planning/intel/` (MODELS, ROUTES, COMPONENTS, MIGRATIONS, DEPENDENCIES, TEST-MAP).

#### P2 — Adjacent quality gates (Wave 3)

- **`release-debug-session-manager`** agent — multi-cycle `/release:debug` loop manager in isolated context; checkpoint-survives `/clear`; bubbles only consequential decisions; returns compact YAML summary.
- **`/release:add-tests`** skill — backfill tests for phase UAT items OR regression coverage for a file; spawns `release-tdd-executor` in test-only mode; surfaces impl bugs to `{NN}-TEST-GAP.md` (never auto-fixes).
- **`release-ui-checker`** agent + **`/release:ui-review`** skill + **`release-ui-auditor`** agent — UI-SPEC pre-validation (PASS/FLAG/BLOCK) + retroactive 6-pillar scored audit (accessibility, responsive, loading/error, i18n, type contracts, design system).
- **`release-advisor-researcher`** agent — single gray-area D-XX decision research with options × 5 dims comparison + falsifiable recommendation.
- **`/release:validate-phase`** skill + **`release-nyquist-auditor`** agent — every requirement must have ≥2 tests (Nyquist sampling); audit-only or auto-dispatch to `/release:add-tests` for gap-fill.
- **`/release:plan-review-convergence`** skill — pipes `{NN}-PLAN.md` to external AI CLIs (codex, gemini) iteratively until HIGH=0 AND MED≤2.

#### P3 — Eval + audit lifecycle (Wave 4)

- **`release-eval-planner`** + **`release-eval-auditor`** agents + **`/release:eval-review`** skill — AI eval strategy upfront (failure modes, dims with rubrics, tooling, dataset, guardrails, monitoring) + retroactive coverage audit (COVERED/PARTIAL/MISSING per dim) with PII/injection escalation rule.
- **`release-framework-selector`** agent — interactive decision matrix scoring 4-7 AI framework candidates (LangChain/LlamaIndex/LangGraph/Anthropic SDK/OpenAI/Vertex/Bedrock/Custom) on Fit/Latency/Cost/Compliance/Stack-Ergonomics.
- **`/release:forensics`** skill — post-mortem investigation with 5-whys + recovery plan in `.release-planning/forensics/`.
- **`/release:audit-fix`** skill — autonomous audit-to-fix loop (parallel auditors → classify → release-code-fixer per atomic commit → re-audit until clean or max-iters).
- **`/release:audit-uat`** skill — cross-phase outstanding-UAT sweep with priority-ranked hot-list.
- **`release-doc-writer`** + **`release-doc-classifier`** + **`release-doc-synthesizer`** + **`release-doc-verifier`** agents + **`/release:docs-update`** skill — full doc-ops family: write/classify/synthesize/verify project documentation grounded in `.release-planning/` + intel + codebase probes.

### Changed

- **`/release:auto` routing table extended** from 21 to 32 rules. Every new skill above is routable via freeform intent. All routes resolve to native `/release:*` skills — `/gsd:*` is not a fallback path.

### Notes

- This release adds capabilities without removing any; safe upgrade from v0.6.x.
- Some new agents are not yet wired into the existing skill flows — `/release:plan` does not yet auto-spawn `release-plan-checker`, `/release:discuss` does not yet auto-spawn `release-assumptions-analyzer`, etc. Those integrations will land in v0.7.x as the agents are validated against real-world phases. For now, invoke them directly via `Agent({subagent_type: "release-plan-checker", ...})` or via `/release:auto` keyword routing.
- 31 new files / ~8200 LOC added.

## [0.6.1] — 2026-05-25

### Added

- **`CLAUDE.md` injection** in `/release:init` and `/release:import`. Both flows now write a delimited `<!-- release-sdk:start --> ... <!-- release-sdk:end -->` block into the repo-root `CLAUDE.md` so future Claude Code sessions know release-sdk is installed and where the planning artifacts live. Idempotent:
  - File missing → created with a minimal header + the block.
  - File present, block present → only the delimited block is replaced; every other byte preserved.
  - File present, no block → block appended at the end (two blank lines before it).
- Block surfaces: framework name + stack, paths (`.release-planning/RELEASE-LOCKS.md`, `STATE.md`, `phases/{NN}-{slug}/`), and the `/release:auto` entry point with the full `/release:*` skill index.

### Fixed

- Gap surfaced by user audit: 5 agents (`release-feature-planner`, `release-spec-clarifier`, `release-tdd-executor`, `release-code-reviewer`, `release-code-fixer`) and `templates/PLAN.md` already READ `CLAUDE.md` for conventions, but nothing in release-sdk wrote it — so brand-new projects had agents reading an empty or generic file. `/release:init` and `/release:import` now own that write.

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
