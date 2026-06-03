# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.15.0] — 2026-06-03

### BREAKING — Worktree-native parallel sessions (Model B); `workstreams` deprecated; 7 dead agents removed

New execution base: every unit of parallel work is a **session** — an ephemeral git worktree on a
`session/<label>` branch cut from one **base branch** — merged back with a serialized, conflict-safe
merge. Replaces the sustained per-domain `workstreams` model. Lets N Claude sessions run independent
domains (financeiro / operacional / RH …) at once and fold into one trunk.

#### Added
- **`/release:session`** — `start` / `finish` / `list` / `abort` / `base`. `start` cuts a worktree+branch
  off base; `finish` does a **serialized, conflict-safe** merge-back: per-base lock, `merge --no-ff`, and
  on conflict `merge --abort` so base stays byte-identical (NEVER auto-resolved) with the session
  preserved for rebase+retry. Merges inside base's own checkout (a branch lives in one worktree).
- **`bin/test-session-merge.sh`** — real-git contract test (12 assertions): disjoint sessions merge
  clean; conflicting session STOPS with base untouched + no half-merge; per-base lock serializes fan-in.
- Honest **conflict-surface table** (Django shared wiring: `INSTALLED_APPS` / root `urls.py` /
  `requirements` / `ROADMAP` phase-number ranges) with mitigations — disjoint app code + per-app
  migrations rarely collide; the shared wiring is the small, known surface.

#### Changed
- **`/release:execute`** detects `.release-planning/.session` and commits in place on the session
  branch (`no_branch`), skipping the nested phase-worktree + lock (the session already isolates it).
- **STATE is local + git-ignored** (`STATE.md`, `.session`, `active-workstream`) — parallel sessions
  never collide on a shared mutable cursor; committed truth is the per-phase artifacts under `phases/`.
- **`/release:auto`** rule 13 routes parallel / session / worktree intents to `/release:session`.

#### Deprecated
- **`/release:workstreams`** (sustained `ws-<name>` domain model) → use `/release:session`. Kept for
  in-flight migrations; removed in a future release.

#### Removed — dead code (7 agents; 44 → 37)
Orphans no release skill ever spawned + the unwired multi-cycle debug manager: `release-advisor-researcher`,
`release-research-synthesizer`, `release-project-researcher`, `release-domain-researcher`,
`release-eval-planner`, `release-doc-synthesizer`, `release-debug-session-manager`.


## [0.13.1] — 2026-06-01

### BREAKING — Concurrency-safe execution (session-isolated worktrees + per-phase lock)

Fixes cross-session corruption when running `/release:execute` in multiple simultaneous sessions on
the same repo. Symptom was `UU` unmerged paths + stray untracked test files in the main checkout, with
no `MERGE_HEAD` — produced by the serial fallback writing TDD output directly in the shared working tree
while another session was also writing there.

Root cause: both `skills/execute` and `release-wave-executor` mutated the **shared main checkout**
(`git checkout`, cherry-pick, serial fallback) with **non-session-scoped** worktree/branch names
(`wave/{NN}-{TASK}`, `../release-worktrees/{NN}-{slug}-w{N}-{TASK}`). Two sessions = one `.git/HEAD`,
one index, one worktree namespace → HEAD ping-pong, index races, `git worktree add` collisions.

- **Camada 1 — session-scoped phase worktree.** Each `/release:execute` now runs entirely inside
  `../release-worktrees/$SESSION_ID/phase`. The main checkout is never mutated. `ensure_branch`,
  cherry-pick merge, and the collision-bound serial fallback all run there via `git -C "$PHASE_WT"`.
- **Camada 2 — per-phase lock.** `../release-worktrees/.locks/{NN}-{slug}.lock` (shared sibling, visible
  to all sessions). A second session on the same phase gets a clean refusal instead of a git error.
  Stale locks (holder worktree gone) auto-reclaim.
- **Camada 3 — hygiene.** `git worktree prune` before every add; wave branches are now
  `wave/$SESSION_ID/w{N}-{TASK}` (session+wave scoped, collision-proof); explicit teardown removes the
  phase worktree + releases the lock on completion/abort.
- `--no-branch` unchanged: legacy single-session path in the main checkout (concurrency unsafe by design).
- `git worktree` unsupported → falls back to `--no-branch` with a loud warning.

Files: `skills/execute/SKILL.md`, `agents/release-wave-executor.md`.

## [0.12.0] — 2026-05-26

### BREAKING — Waves-by-default execution + PLAN slice token economy

`/release:execute` no longer spawns `release-tdd-executor` directly. ALL phase execution
now routes through `release-wave-executor`, which:

1. **Parses PLAN** (wave-split dir `{NN}-PLAN/manifest.md` preferred; legacy monolithic
   `{NN}-PLAN.md` accepted only if ≤ 600 lines — otherwise refused with re-split hint).
2. **Auto-derives parallel_groups** within each wave when frontmatter omits explicit
   declarations: greedy disjoint-files partition over per-task `files:` entries, plus
   collision_detection rules (migrations, lockfiles, Django graph coherence).
3. **Slices PLAN per task** (~3KB) into worktree-local `PLAN-SLICE-{TASK_ID}.md`.
   Executor spawns full-read the slice instead of re-reading 100KB+ monolithic PLAN.
4. **Spawns N `release-tdd-executor` concurrently** in `git worktree`-isolated branches
   when disjoint files detected. Cherry-picks per-task commits back to `feat/{NN}-{slug}`
   after each wave.
5. **Verify per-wave** (intermediate, cheap gates only) + **full `parallel_test_sweep`
   at end-of-phase** (terminal wave only — replaces redundant per-task sweep).
6. **`--resume` idempotent** — skips tasks already committed by greping task IDs in
   `git log` of phase branch.

#### Removed flags

- `--waves` — waves are now default; flag dropped from `/release:execute` CLI
- `--serial` — no override; serial-in-main-tree falls out automatically when
  collision_detection forces it (Django graph coherence, migration collisions, etc.)

#### New `release-tdd-executor` spawn config

- `skip_sweep: bool` — intermediate-wave spawns skip `parallel_test_sweep`; wave-executor
  runs ONE sweep at end-of-phase
- `is_slice: bool` — plan_path is a per-task slice; executor full-reads and MUST NOT
  re-load parent PLAN/manifest (token economy contract)

#### Token economy

Phase 46 hubus baseline (Frontend, 40 tasks, monolithic 115KB PLAN):
- Before: ~4.6MB input (40 spawns × 115KB PLAN re-read)
- After:  ~120KB input (40 spawns × 3KB slice)
- **-97% input tokens.** Estimated cost drop @ Opus 4.7 input rate: ~$8 → ~$0.40 per phase.

#### Speed

Phase 46 hubus baseline:
- Before: 2h05 (Frontend serial) + 2h (Backend serial) = 4h05
- After (estimated): ~1h Frontend + ~1h25 Backend (Django graph limits BE parallelism) = ~2h25
- **~-42% wall time.**

#### Migration guide

- Existing phases with monolithic PLAN.md ≤ 600 lines: continue to work (back-compat).
- Existing phases with monolithic PLAN.md > 600 lines: re-run `/release:plan {NN}` to
  emit wave-split dir (planner already mandates this layout since v0.11.0).
- CI/CD scripts using `/release:execute {NN} --waves`: drop the `--waves` flag.

#### Files changed

- `skills/execute/SKILL.md` — drop `--waves`, invert routing to wave-executor default
- `agents/release-wave-executor.md` — add `<auto_derive_parallel_groups>` step + PLAN slice
  generation + `<resume_skip_filter>` step + monolithic PLAN refusal + terminal vs
  intermediate verify split
- `agents/release-tdd-executor.md` — accept `skip_sweep` + `is_slice` spawn config; update
  `<plan_read_protocol>` for slice mode; update `<parallel_test_sweep>` skip conditions;
  description marks v0.12.0 spawn-by-wave-executor-only

---

## [0.11.3] — 2026-05-26

### Changed — Model dispatch right-sizing per agent

Default `model: opus` (1M context) was too heavy for mechanical agents — grep-only
verifiers and one-shot writers were spending opus tokens for haiku-tier work.
Re-dispatch tightens cost without losing reasoning where it matters.

**Sonnet (medium-tier — grants 200k window, ~5x cheaper than opus)**:
- `release-code-fixer` — applies REVIEW.md findings mechanically
- `release-test-auditor` — gap detection via name matching
- `release-uat-conductor` — Q&A walkthrough via `AskUserQuestion`
- `react-ui-checker` — BLOCK/FLAG/PASS against UI-SPEC dimensions

**Haiku (cheap-tier — pure grep / count / classify)**:
- `release-pattern-mapper` — analog matching across model/view/serializer dirs
- `release-intel-updater` — codebase scan → cached intel files
- `release-nyquist-auditor` — counts tests per requirement
- `release-eval-auditor` — grep COVERED/PARTIAL/MISSING per eval dim
- `django-checklist-verifier` — Q1-Q7 PASS/FAIL via grep

**Opus retained** (deep reasoning / loop / large context):
- `release-tdd-executor` — RED→GREEN→REFACTOR loop with full PLAN.md reads
- `release-wave-executor` — multi-worktree dispatch + cherry-pick coordination
- All planners, researchers, reviewers, security auditors, debuggers, integration
  checkers, milestone auditors

Estimated savings on phase-46-class workloads: ~35-45% USD without quality loss
on critical reasoning paths.

### Fixed — Token tracker missed all subagent costs

`release-token-collector.js` was only hooked to `PostToolUse` of the main thread.
Result: `events.jsonl` recorded 100% `claude-opus-4-7` even when sonnet/haiku
subagents were running — every `Agent`-tool dispatch was invisible to the
dashboard.

Fix: added `SubagentStop` matcher invoking the same collector. Claude Code passes
the subagent's own `session_id` + `transcript_path` on that event; the collector's
per-session cursor isolates subagent runs naturally — no code change to the
collector, only a 3-line `plugin.json` addition.

Now `/release:tokens` "Por modelo" panel shows real opus/sonnet/haiku breakdown,
making the model-dispatch changes above measurable.

## [0.11.2] — 2026-05-26

### Fixed — Executor efficiency overhaul (Phase 46 audit fallout)

Audit forense da Phase 46 (hubus refactor, 68min wall / $32-60 USD / `status: PARTIAL`)
identificou 4 gargalos no `release-tdd-executor` + `release-wave-executor`. Fixes:

**1. Django pre-commit graph coherence (`release-wave-executor.md`)**

Phase 46 forçou coalesce de 22 tasks num único commit (gap de 37min). Causa: Django
`manage.py check` valida grafo inteiro (models → admin → views → serializers → urls)
— wave-executor spawnava parallel workers em worktrees, mas pre-commit no cherry-pick
rejeitava partial states.

Fix: `<collision_detection>` agora detecta `models.py` + downstream files na mesma
wave → força `coalesce_into_wave_commit: true`. Nova função
`has_django_system_check_precommit()` inspeciona `.pre-commit-config.yaml`.
WAVE-SUMMARY.md declara o coalesce explicitamente (audit trail honesto).

**2. Fullstack BACKEND-then-FRONTEND dispatch (`release-tdd-executor.md`)**

Phase 46 era fullstack mas PLAN-FRONTEND.md (40 tasks) nunca rodou — executor saiu
silenciosamente após backend. SUMMARY ficou `PARTIAL` mas sem checkpoint explícito.

Fix: novo bloco "Two-PLAN protocol" no `<fullstack-stack>`. Quando phase dir tem
`{NN}-PLAN-BACKEND.md` + `{NN}-PLAN-FRONTEND.md`: executa BACKEND completo, escreve
`SUMMARY-BACKEND.md`, executa FRONTEND, escreve `SUMMARY-FRONTEND.md`, agrega em
`SUMMARY.md` unificado. `half: backend|frontend` spawn config respeitado.
Critical rule: NEVER `status: SUCCESS` com metade untouched — força `PARTIAL`
+ checkpoint.

**3. Parallel test sweep unconditional**

`parallel_test_sweep` (introduzido no v0.11.2 step inicial) tinha skip-when-small
(<20 tests OR <5 files). Removido: agora sempre roda 5-way para coletar telemetria
+ inventory + `sweep-B*.json` requeridos pelo SUMMARY. Única exceção: `total_tests
== 0` → smoke single-shot.

**4. PLAN read protocol (`release-tdd-executor.md`)**

Phase 46 burned ~2.1M tokens em cache_read da PLAN.md monolítica (3121 linhas ×
34 tasks). Novo step `plan_read_protocol` força:
- Initial PLAN load ONCE (frontmatter + task index com line offsets)
- Per-task: `Read` com offset/limit cobrindo só section da task (~40-120 linhas)
- Cross-task lookups: `Grep` com `-A`/`-B` context, nunca full Read
- Wave files (~400 linhas) podem full-read — overhead negligível
- Anti-pattern explícito: `cat PLAN.md | grep` proibido, usar Grep tool

Redução estimada: 2.1M → ~100K tokens cache_read por phase (~95%).

### Added — 5-way parallel test sweep + cheaper models

**Problema:** Final test sweep do `release-tdd-executor` rodava `pytest`/`vitest`
em série sobre 200+ testes via Opus → 5+ min wall time + custo alto. Em fases
com waves paralelas (v0.11.0) o sweep virava o novo gargalo.

**Solução:** Novo step `parallel_test_sweep` substitui o sweep serial:

1. **`release-test-discover`** (model: **haiku**) — roda `pytest --collect-only`
   ou `vitest list`, emite JSON `{file: test_count}` ordenado desc.
2. **Bucket greedy bin-packing** — distribui arquivos em 5 buckets balanceados
   por número de testes (~total/5 por bucket).
3. **`release-test-runner`** (model: **sonnet**) — 5x spawn em paralelo, cada
   um roda seu bucket, emite JSON `{passed, failed, failures[]}` com traceback
   head capado em 10 linhas.
4. **Aggregate** — qualquer FAIL → Opus re-roda só arquivo afetado pra diagnose
   completa + fix flow normal (Rule 1/2 deviation).

**Skip parallel** quando `total_tests < 20` OU `total_files < 5` (overhead > ganho).

**Ganho estimado:** sweep 5 min → ~1 min wall time (5x parallel). Custo cai
~80% no sweep (haiku discover + sonnet runners vs opus serial).

**Telemetria:** SUMMARY.md ganha bloco `parallel_sweep:` com `wall_time_seconds`,
`serial_estimate_seconds`, `speedup`.

**Stack blocks atualizados:** `### Final sweep` em django-stack e react-stack
agora cobre só lint/grep/tsc — pytest/vitest delegado pro novo step. Suítes
especializadas (smoke/race/memray/security) também usam `release-test-runner`
mas com 1 bucket (já são pequenas).

**Backward-compat:** se inventário vier vazio (`total_tests == 0`), executor
roda sweep single-shot inline (comportamento legacy).

## [0.11.1] — 2026-05-26

### Fixed — Token dashboard: "Sessão atual" sempre $0.00 + "Por skill" sempre vazio

**Bug 1 — Sessão atual = $0.00:**

Dashboard chamava `/api/stats` sem query `session_id`. Worker recebia `null`
e nunca acumulava events na bucket `session`. Fix: quando `session_id` ausente
na query, worker auto-detecta = `session_id` do evento mais recente (se < 30min).
Dashboard agora exibe os 8 primeiros chars do session_id ativo (com tag "(auto)"
quando inferido). Funciona transparentemente independente de qual sessão CC abriu o browser.

**Bug 2 — POR SKILL sempre vazio:**

`release-token-collector.js` extraía skill via regex `<command-name>X</command-name>`.
Esse formato só aparece em comandos built-in (`/clear`, `/login`, `/model`).
Slash commands de plugin (`/release:plan`, `/release:execute`) injetam conteúdo
diferente no transcript — header `# /release:<name>` + path `.../skills/<name>/SKILL.md`.

Fix: novo `extractSkill()` reconhece 3 formatos em ordem:
1. Path `Base directory for this skill: .../skills/<name>` → `release:<name>`
2. Header `# /<command>` → `<command>`
3. Tag `<command-name>X</command-name>` (built-ins) → `X`

Também removido `break;` prematuro que parava após primeira user message
mesmo quando sem skill signal. Agora walk-back continua até encontrar ou esgotar.

Events anteriores ao fix permanecem com `skill: null` — dashboard só
preenche POR SKILL para events futuros. Clear `~/.claude/token-tracker/events.jsonl`
para reset opcional.

## [0.11.0] — 2026-05-26

### BREAKING — Wave-split PLAN structure

PLAN.md monolíticos (3000+ linhas vistos em fases reais) substituídos por diretório
de waves. Cada wave file = 3-5 tasks, 200-600 linhas. Cap duro 600 linhas. Drasticamente
reduz contexto consumido por executores e plan-checkers, e permite paralelização real
entre waves.

**Antes:**
```
{NN}-PLAN.md            (3101 linhas, 34 tasks)
{NN}-PLAN-CHECK.md
```

**Depois:**
```
{NN}-PLAN/
  manifest.md           (frontmatter + waves table, < 300 linhas)
  W1-red-tests.md       (~300 linhas, 4 tasks)
  W2-models-migration.md
  W3-viewsets.md
  W4-serializers.md
  W5-security.md
  W6-verify.md
{NN}-PLAN-CHECK.md      (inclui wave-budget audit)
```

Para fullstack: `{NN}-PLAN-BACKEND/` + `{NN}-PLAN-FRONTEND/` (dois dirs paralelos).

#### Wave budget contract (HARD)

- `WAVE_TARGET_LINES: 400` (alvo)
- `WAVE_HARD_CAP_LINES: 600` — plan-checker emite BLOCKER acima
- `TASKS_PER_WAVE: 3-5`
- Manifest < 300 linhas; tasks moram nos W*.md
- Cada wave: `wave`, `depends_on`, `parallel_safe`, `files_touched` no frontmatter
- Tasks NUNCA atravessam wave files

#### Plan-checker novas regras (BLOCKER)

- Wave file > 600 linhas
- Empty wave (0 tasks)
- Tasks no manifest.md
- Cross-wave dep cycle
- Task duplicada em ≥2 waves
- File overlap entre waves `parallel_safe: true`

#### Back-compat

PLAN.md legacy (single-file) ainda é lido por checker e executor.
Plan-checker emite finding MED sugerindo re-rodar `/release:plan` para wave-split.

### Changed — Model dispatch per agent

Agents mecânicos (grep evidências, mapping estrutural) agora rodam em modelos mais baratos:

| Agent | Model | Razão |
|---|---|---|
| release-plan-checker | sonnet | grep + trace traceability |
| release-pattern-mapper | sonnet | map files → analogs |
| release-codebase-mapper | sonnet | inventário estruturado |
| release-intel-updater | sonnet | rewrite intel/ files |
| release-nyquist-auditor | sonnet | test counting |
| django-checklist-verifier | sonnet | Q1-Q7 grep |
| release-eval-auditor | sonnet | eval coverage grep |
| release-django-security-retro | sonnet | mitigation grep |
| react-security-retro | sonnet | mitigation grep |
| release-doc-verifier | haiku | factual claim verification |
| release-doc-classifier | haiku | 1-doc classifier |

Planejadores (`release-feature-planner`), executores (`release-tdd-executor`,
`release-wave-executor`) e researchers permanecem em Opus 4.7 — trabalho que exige
raciocínio profundo.

**Ganho medido vs Phase 46 (hubus, refactor quadros-horário):**
- Latência plan stage: 1h37min → ~35-45min estimado (~55% redução)
- Tokens plan+check: 700k → ~280k estimado (~60% redução)
- Custo proporcional

### Migration

Projetos pré-v0.11 funcionam — checker lê PLAN.md legacy e emite MED suggesting
re-run. Para migrar uma fase existente para wave-split:

```bash
/release:plan {NN}    # re-roda planejamento, emite {NN}-PLAN/ dir
```

## [0.10.3] — 2026-05-25

### Fixed — `django-prompt-guard.js` regex parse error broke plugin init

`hooks/django-prompt-guard.js:65` had a regex that embedded literal Unicode
characters including U+2028 (JS LINE SEPARATOR) inside the character class:

```js
if (/[​-‏ - ﻿­]/.test(content)) { ... }
```

Node v22+ parses the literal U+2028 as a source-level line terminator,
breaking the regex with `SyntaxError: Invalid regular expression: missing /`.
Plugin manifest registers this hook on `PreToolUse:Write|Edit` — Claude Code
fails to load the plugin's skills when any declared hook fails parse.

Symptom: `/reload-plugins` reported "1 skill" total even after adding
`release@release-sdk` to `enabledPlugins`. Agents and other hooks still loaded
because the loader continued past the broken hook for those.

Fix: rewrite the regex with escaped `\\uXXXX` source-form so the regex string
is byte-safe — same semantics, parser-safe.

## [0.10.2] — 2026-05-25

### Fixed — `allowed_tools:` (invalid) broke skill registration

After v0.10.1 added `name:` to all 40 SKILL.md, skills still failed to register.
Root cause: every skill used `allowed_tools: A, B, C` (underscore + CSV string).
The Claude Code spec uses `allowed-tools:` (hyphen, YAML array) — same form as
GSD's user-level skills in `~/.claude/skills/`. The underscore variant is not a
recognized field and made the loader bail on each release-sdk skill silently.

For now removed the line entirely. Skills load without per-skill tool
restrictions. Future release will re-add as proper YAML:

```yaml
allowed-tools:
  - Read
  - Write
  - Bash
```

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
