# release-sdk

> Kit de aceleração full-stack para Claude Code. Django + React TSX. Sem API key — usa sua assinatura Claude.

> 🇺🇸 [English version](./README.en.md) (mirror)

Comandos `/release:*` context-aware roteiam automaticamente para os agents certos baseado nos seus arquivos e ROADMAP. Um SDK, duas stacks.

**Porta de entrada:** **`/release:auto <sua intenção em linguagem natural>`** — roteador de 32 regras que despacha pro skill `/release:*` certo, imprime a rota escolhida + razão antes de invocar, faz fallback pra `AskUserQuestion` quando a confiança é baixa.

**Versão atual: v0.16.0** — invocação curta `/release:*`, 41 skills, 37 agents (taxonomia: nome sem prefixo = merged stack-dispatched, `django-*` Django-puro, `react-*` React-puro; spawnados via `release:<nome>` — ex. `release:tdd-executor`). Veja [CHANGELOG.md](./CHANGELOG.md) pra evolução completa.

---

## A ideia central

**Você define a arquitetura uma vez. Toda feature subsequente honra o que você travou.**

1. `/release:init` — captura visão, trava stack backend + frontend, modelo de auth, padrões proibidos → `PROJECT.md` (LOCK-01..LOCK-12)
2. `/release:roadmap` — decompõe milestone em fases vertical-slice → `ROADMAP.md`
3. Por fase: `/release:discuss` → `/release:plan` → `/release:execute` → `/release:verify`
4. Decisões travadas em `discuss` viram D-XX em CONTEXT.md, referenciadas por toda task de PLAN.md, verificadas contra o codebase real

Zero suposição silenciosa. Zero "v1 / placeholder / vai ser ligado depois". Zero mudança não-rastreável.

---

## Novidades (v0.5 → v0.16)

- **v0.16.0** — `/release:session` endurecido: 6 bugs de uso multi-sessão real (cwd-drift crash no `finish`, conflito mutando o checkout da base, planning vazando pra PR, sem drift handling, `base-branch` não persistindo sob gitignore, pouca visibilidade) + review adversarial de 6 lentes (27 achados — incl. TOCTOU resolvido com lock-first/sync-merge atômico, lockfile slash-safe, reclaim de lock morto, refused-merge). Novos subcomandos `sync`/`doctor`/`cleanup`; `bin/test-session-merge.sh` 12 → 48 asserts regression-guarded. **Agentes agora namespaceados** `release:<nome>` (Claude Code exige prefixo de plugin; `subagent_type` cru falhava) — 320 spawns reescritos em 62 arquivos.
- **v0.15.0** — BREAKING: sessions worktree-native (Model B). Cada domínio paralelo (financeiro/operacional/RH…) é um worktree numa branch `session/<label>` cortada de uma base, mergeado de volta com merge serializado conflict-safe (base nunca fica suja; conflito PARA, nunca auto-resolve). `/release:session start|sync|finish|list|doctor|cleanup|abort|base`. Substitui `workstreams` (deprecated). 7 agents mortos removidos (44→37).
- **v0.13.x** — Auditor de ameaças avançadas always-on (A1-A13 Django / RA1-RA5 React: SSRF/IMDS, desserialização insegura, command injection, SSTI/path-traversal, SQLi exploit-grade, race/TOCTOU, image-DoS, AWS-IaC). Execução concurrency-safe: worktree de fase isolado por sessão + lock por fase (fix corrupção UU em execute multi-sessão).
- **v0.12.0** — BREAKING: waves-by-default no `/release:execute` (sem flag `--waves`). `wave-executor` faz fan-out de N `tdd-executor` em branches paralelas worktree-isoladas por grupo de task disjunto; PLAN fatiado por task; verify-per-wave.
- **v0.11.1** — Token tracker dashboard fix. `Sessão atual` $0 + `POR SKILL` vazio resolvidos. Worker auto-detecta `session_id` do evento mais recente (< 30min) quando query param ausente. `extractSkill` reconhece 3 formatos: path `skills/<name>`, header `# /release:<name>`, tag `<command-name>` (built-ins). Dashboard exibe tag de sessão ativa com `(auto)` quando inferido.
- **v0.11.0** — BREAKING: PLAN.md monolítico substituído por diretório `{NN}-PLAN/` (manifest.md + N wave files). Target 400 linhas / 3-5 tasks por wave; hard cap 600 linhas (BLOCKER no plan-checker). Fullstack vira `{NN}-PLAN-BACKEND/` + `{NN}-PLAN-FRONTEND/`. Plan-checker novas regras: empty wave, tasks no manifest, cross-wave dep cycle, file overlap entre `parallel_safe` waves. Back-compat: PLAN.md legacy ainda lido com finding MED. **Model dispatch:** agents mecânicos (plan-checker, pattern-mapper, codebase-mapper, intel-updater, nyquist-auditor, eval-auditor, security-retros, checklist-verifier) rodam Sonnet 4.6; doc-verifier + doc-classifier rodam Haiku 4.5; planejadores/executores/researchers permanecem Opus 4.7. Ganho estimado vs Phase 46: latência plan stage 1h37min → ~35-45min, tokens 700k → ~280k.
- **v0.10.x** — `/release:tokens` dashboard daemon HTTP em :47777 + USD/BRL com FX live awesomeapi (cache 1h, fallback) + breakdown por sessão/dia/semana/all-time/modelo/projeto/skill + cache hit ratio. Hook PostToolUse `release-token-collector.js` parseia transcript JSONL pra `~/.claude/token-tracker/events.jsonl`. Fixes: SKILL.md frontmatter (`name:` field obrigatório em CC v2.1.142, `allowed-tools` com hífen não underscore), `django-prompt-guard.js` U+2028 LINE SEPARATOR em regex literal.
- **v0.9.x** — react-* prefix em agents React-puros pra clarificar dispatch + delete 2 orphan django-* agents desalinhados com taxonomy.
- **v0.8.0** — Drop-in GSD substitution: milestone + session + undo + mvp + 4 orphan agents wired. Router `/release:auto` 32 → 39 regras.
- **v0.7.0** — 31 arquivos novos (20 agents + 11 skills) fechando audit gap vs upstream GSD. Highlights: `/release:autonomous`, `/release:audit-fix`, `/release:validate-phase`, `/release:ui-review`, `/release:eval-review`, `/release:docs-update`, `/release:forensics`, `plan-checker`, `assumptions-analyzer`, `release-debug-session-manager`, `framework-selector`, família `release-doc-*` completa.
- **v0.6.1** — `/release:init` e `/release:import` injetam bloco delimitado `<!-- release-sdk:start --> ... <!-- release-sdk:end -->` no `CLAUDE.md` raiz. Idempotente.
- **v0.6.0** — `/release:auto` (roteador de intenção livre) + nativos `/release:debug`, `/release:fast`, `/release:quick`, `/release:ship`.
- **v0.5.0** — BREAKING: `.planning/` → `.release-planning/` pra coexistir com GSD upstream. `/release:import` lê GSD `.planning/` (intocado) e escreve árvore paralela.

---

## Workflow no panorama

```
┌───────────────────────────────────────────────────────────────────────────┐
│  UMA VEZ POR PROJETO                                                      │
│  /release:init      →  PROJECT.md (LOCK-01..LOCK-12: backend + frontend)  │
│                     →  ROADMAP.md (fases)                                 │
│                     →  REQUIREMENTS.md (REQ-XX)                           │
│                     →  STATE.md (cursor)                                  │
│                     →  CLAUDE.md (bloco delimitado release-sdk injetado)  │
├───────────────────────────────────────────────────────────────────────────┤
│  POR FASE                              backend         frontend           │
│  /release:spec {NN}     →  SPEC.md (score de ambiguidade)                 │
│  /release:discuss {NN}  →  CONTEXT.md (D-01..10)    (D-11..20)            │
│  /release:plan {NN}     →  {NN}-PLAN/  (manifest.md + W1..WN wave files)  │
│                            fullstack: -BACKEND/ + -FRONTEND/ dirs         │
│  /release:execute {NN}  →  TDD: RED → GREEN → REFACTOR → SECURITY         │
│                            Django: pytest, ruff                           │
│                            React:  vitest, tsc                            │
│  /release:verify {NN}   →  VERIFICATION.md (PASS / GAPS_FOUND)            │
│  /release:verify-work   →  walkthrough UAT conversacional                 │
│  /release:ship          →  pre-ship review → gh pr create → cursor=shipped│
├───────────────────────────────────────────────────────────────────────────┤
│  QUALITY GATES (qualquer hora)                                            │
│  /release:review         |  /release:security      |  /release:checklist  │
│  /release:secure-phase   |  /release:validate-phase|  /release:ui-review  │
│  /release:eval-review    |  /release:audit-fix     |  /release:audit-uat  │
├───────────────────────────────────────────────────────────────────────────┤
│  INVESTIGAÇÃO + WORK PEQUENO                                              │
│  /release:debug          |  /release:fast          |  /release:quick      │
│  /release:forensics      |  /release:add-tests                            │
├───────────────────────────────────────────────────────────────────────────┤
│  REPO INTELLIGENCE                                                        │
│  /release:map-codebase   |  /release:docs-update                          │
├───────────────────────────────────────────────────────────────────────────┤
│  OBSERVABILIDADE                                                          │
│  /release:tokens         →  dashboard token tracker (USD/BRL, cache hit,  │
│                            por sessão/dia/skill/projeto/modelo)           │
├───────────────────────────────────────────────────────────────────────────┤
│  AUTONOMOUS                                                               │
│  /release:autonomous     →  roda todas fases pendentes do ROADMAP em      │
│                            sequência (spec→discuss→plan→execute→verify).  │
│                            Aborta na primeira falha de verify.            │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## Comandos slash

### Entry point
| Comando | Stack | Propósito |
|---|---|---|
| `/release:auto {intent}` | both | **Roteador de intenção livre.** 32 regras mapeiam seu prompt para o skill `/release:*` certo. Imprime rota + razão antes de invocar. |

### Ciclo de vida do projeto + fase
| Comando | Stack | Propósito |
|---|---|---|
| `/release:init` | both | Inicializa PROJECT.md (LOCK-01..LOCK-12). Injeta bloco delimitado no CLAUDE.md raiz. |
| `/release:import` | both | Mass-port GSD `.planning/` → release-sdk `.release-planning/` (one-shot, todas as fases) |
| `/release:spec {NN}` | both | Esclarece O QUE a fase entrega (SPEC.md, score de ambiguidade) |
| `/release:discuss {NN}` | both | Coleta decisões (D-XX) da fase |
| `/release:plan {NN}` | both | Gera PLAN.md com checklists + segurança |
| `/release:ui-phase {NN}` | frontend | Produz UI-SPEC.md (contrato de design) |
| `/release:ai-phase {NN}` | both | Produz AI-SPEC.md (framework LLM, prompts, eval, guardrails) |
| `/release:execute {NN}` | both | Execução TDD-strict (pytest ou vitest) |
| `/release:verify {NN}` | both | Verificação estática goal-backward |
| `/release:verify-work {NN}` | both | Walkthrough UAT conversacional (UAT.md) |
| `/release:ship` | both | Pre-ship review → PR body grounded em SPEC/PLAN/UAT → `gh pr create` → cursor `shipped`. Nunca faz auto-merge. |
| `/release:status` | both | Cursor + atividade recente + próxima ação |
| `/release:autonomous` | both | Roda todas as fases pendentes do ROADMAP em sequência. Aborta na primeira falha de verify. |

### Quality gates + audits
| Comando | Stack | Propósito |
|---|---|---|
| `/release:review` | both | Code review adversarial (REVIEW.md) |
| `/release:security` | both | Audit de segurança 9-categorias author-time (SECURITY.md) |
| `/release:secure-phase {NN}` | both | Audit retroativo de threat-mitigation (scorecard) |
| `/release:checklist` | both | Verificação Q1-Q7 + RC1-RC7 |
| `/release:validate-phase {NN}` | both | Audit de cobertura Nyquist: cada requirement precisa de ≥2 testes |
| `/release:ui-review {NN}` | frontend | Audit visual retroativo 6-pilares (a11y, responsive, loading/error, i18n, type contracts, design system) |
| `/release:eval-review {NN}` | both | Audit retroativo de cobertura de eval AI (COVERED/PARTIAL/MISSING por dim) |
| `/release:audit-fix` | both | Loop autônomo audit→fix (auditors paralelos → code-fixer → re-audit) |
| `/release:audit-uat` | both | Varredura cross-phase de UATs pendentes com hot-list por prioridade |
| `/release:plan-review-convergence {NN}` | both | Loop de peer-review cross-AI (codex/gemini) até HIGH=0 AND MED≤2 |

### Investigação + trabalho pequeno
| Comando | Stack | Propósito |
|---|---|---|
| `/release:debug` | both | Sessão de debug persistente em `.release-planning/debug/{id}/`. Sobrevive `/clear` via checkpoint. |
| `/release:fast` | both | Edit inline trivial. Sem agents, sem state. Gate de worktree limpa, commit atômico. Envelope < 30 LOC. |
| `/release:quick` | both | Task bounded multi-arquivo com TDD executor. Cursor intocado. Entre fast (sem envelope) e plan (envelope completo). |
| `/release:forensics` | both | Post-mortem pra workflows que falharam. Timeline + 5-whys + plano de recovery. |
| `/release:add-tests {NN}` | both | Backfill de cobertura UAT ou cobertura de regressão pra um arquivo. |

### Repo intelligence
| Comando | Stack | Propósito |
|---|---|---|
| `/release:map-codebase` | both | Análise paralela 4-focus do codebase (tech, arch, quality, concerns) → `.release-planning/codebase/*.md` |
| `/release:docs-update` | both | Regenera README/CONTRIBUTING/ARCHITECTURE verificados contra o codebase |
| `/release:session [sub]` | both | Sessões paralelas worktree-native: `start`/`sync`/`finish`/`list`/`doctor`/`cleanup`/`abort`/`base`. N domínios independentes → um trunk, merge-back serializado conflict-safe |
| `/release:workstreams [sub]` | both | ⚠️ Deprecated (v0.15) — substituído por `/release:session` |

### Legacy single-stack (mantidos por compatibilidade)
| Comando | Stack | Propósito |
|---|---|---|
| `/django:review` | backend | Review Django-only |
| `/django:security` | backend | Audit de segurança Django-only |

---

## Agents — Singletons (release-sdk nativos)

### Plan + discuss
| Agent | Papel |
|---|---|
| `spec-clarifier` | Score de ambiguidade do SPEC.md antes do discuss |
| `assumptions-analyzer` | Análise profunda do codebase pré-plan, surface hidden assumptions + ripple analysis |
| `feature-planner` | Geração de PLAN.md por stack |
| `plan-checker` | Pre-execute goal-backward + LOCK trace (gates stack-aware) |
| `pattern-mapper` | Mapeia arquivos novos para análogos existentes mais próximos |

### Research
| Agent | Papel |
|---|---|
| `feature-researcher` | Pesquisa pre-plan da fase |
| `ai-researcher` | Pesquisa de framework AI/LLM pra `/release:ai-phase` |
| `react-ui-researcher` | Autor do contrato de design UI-SPEC.md |
| `codebase-mapper` | Análise paralela 4-focus do codebase |
| `intel-updater` | Arquivos de intel cached em `.release-planning/intel/` |

### Execute + verify
| Agent | Papel |
|---|---|
| `tdd-executor` | TDD RED→GREEN→REFACTOR→SECURITY (stack-aware) |
| `wave-executor` | Execução em waves paralelas via git worktrees |
| `code-reviewer` | Code review adversarial stack-aware |
| `code-fixer` | Aplica findings do REVIEW.md como commits atômicos |
| `phase-verifier` | Verificação post-execute goal-backward |
| `uat-conductor` | Verificação UAT conversacional |
| `integration-checker` | Probe cross-phase E2E + data-contract (DRF↔Zod pra fullstack) |
| `test-auditor` | Matriz de cobertura de testes por stack |
| `nyquist-auditor` | Audit ≥2-testes-por-requirement |
| `debugger` | Catálogo de 10 bug-shapes por stack |

### UI + AI
| Agent | Papel |
|---|---|
| `react-ui-checker` | UI-SPEC pre-validation (PASS/FLAG/BLOCK) em 6 dimensões de qualidade |
| `react-ui-auditor` | Audit visual retroativo scored 6-pilares |
| `framework-selector` | Matriz interativa de decisão pra seleção de framework AI/LLM |
| `eval-auditor` | Audit retroativo de cobertura de eval AI |

### Security
| Agent | Papel |
|---|---|
| `security-auditor` | Audit author-time 9-categorias stack-aware |
| `django-security-retro` | Scorecard retroativo de segurança Django |
| `react-security-retro` | Scorecard retroativo de segurança React |

### Docs + import
| Agent | Papel |
|---|---|
| `import-orchestrator` | Ponte one-shot GSD `.planning/` → release-sdk `.release-planning/` |
| `doc-writer` | Escreve/atualiza README, CONTRIBUTING, ARCHITECTURE, ONBOARDING grounded nos artefatos |
| `doc-classifier` | Classifica doc de planning como ADR/PRD/SPEC/DOC/UNKNOWN |
| `doc-verifier` | Verifica claims factuais em docs contra o codebase vivo |

### Django-specific (lógica pura Django)
| Agent | Papel |
|---|---|
| `django-discuss-orchestrator` | 10-dim questionnaire backend (models, multi-tenancy, Celery, F(), select_for_update, etc) — spawned por `/release:discuss` |
| `django-checklist-verifier` | Q1-Q7 verifier Django — spawned por `/release:checklist` |

---

## Checklists de autor

| Stack | Checklist | Questões |
|---|---|---|
| Django | Q1-Q7 | select_related, prefetch_related, annotate, Subquery, F()/select_for_update, delay_on_commit, iterator |
| React | RC1-RC7 | React.memo/useMemo/useCallback, isLoading/isError, TypeScript/Zod, accessibility, state discipline, auth token storage, test coverage |

---

## Hooks

| Hook | Evento | Propósito |
|---|---|---|
| `django-validate-commit.sh` | PreToolUse:Bash | Enforcement de Conventional Commits (ambas stacks) |
| `django-workflow-guard.js` | PreToolUse:Write/Edit | TDD advisory — avisa em edit de core Django sem teste |
| `django-tenant-scope-check.sh` | PreToolUse:Write/Edit | Avisa quando Model novo pula TenantModel |
| `django-prompt-guard.js` | PreToolUse:Write/Edit | Escaneia `.release-planning/` por padrões de prompt injection |
| `react-workflow-guard.js` | PreToolUse:Write/Edit | TDD advisory — avisa em edit de component React sem teste |
| `react-security-guard.js` | PreToolUse:Write/Edit | Avisa em localStorage token, dangerouslySetInnerHTML, eval |
| `release-read-injection-scanner.js` | PreToolUse:Read | Escaneia files lidos por padrões de prompt-injection |
| `release-context-monitor.js` | PostToolUse:* | Tracking de tool-call count; avisa em 50/100/150 pra summarizar ou `/release:pause-work` |

---

## 9 Categorias de Segurança

### Django (backend)
1. Cross-Tenant Isolation
2. Intra-Tenant IDOR
3. Vertical Privilege Escalation
4. Mass Assignment
5. JWT Lifecycle
6. Input Validation / Injection
7. Auth State Transitions
8. CSRF
9. Cookie / Token Security

### React (frontend)
1. XSS Prevention
2. Auth Token Storage (httpOnly cookies only — localStorage = BLOCKER)
3. CSRF (X-CSRFToken header)
4. Client-side IDOR
5. API Key / Secret Exposure
6. Content Injection (Markdown/rich text)
7. Prototype Pollution
8. Sensitive Data Logging
9. Input Validation (Zod schemas)

---

## Defaults de stack

| Concern | Default |
|---|---|
| Backend | Django 5.2 LTS + DRF 3.16.x + Python 3.12 |
| Frontend | React 18 + Vite + TypeScript strict |
| Client state | Zustand |
| Server state | TanStack Query v5 |
| Forms | react-hook-form + zod |
| Frontend tests | Vitest + React Testing Library + MSW |
| API mocks (tests) | MSW v2 |
| Backend tests | pytest + pytest-django + factory-boy |
| Auth | JWT httpOnly cookie + X-CSRFToken header |
| Multi-tenancy | empresa_id via django-rls + TenantModel |

---

## Instalação

### Marketplace (recomendado)

```
/plugin marketplace add LucasAlvesBorges/release-sdk
/plugin install release@release-sdk
```

Reinicie o Claude Code.

### Clone local (recomendado pra dev)

```bash
git clone https://github.com/lucasalvesborges/release-sdk ~/.claude/plugins/release-sdk
# Reinicie o Claude Code
```

### Symlink (dev ao vivo)

```bash
ln -s ~/release/personal/django-sdk ~/.claude/plugins/release-sdk
```

---

## Quick start — projeto fullstack

```bash
cd ~/meu-projeto

# 1. Inicializa
/release:init
  # → pergunta: stack backend, stack frontend, modelo de auth, multi-tenant, padrões proibidos
  # → produz: PROJECT.md (LOCK-01..LOCK-12) + ROADMAP.md + STATE.md + REQUIREMENTS.md
  # → injeta bloco delimitado em CLAUDE.md raiz

# 2. Escopo da primeira fase
/release:phase add "Lista de invoices com filtro e export CSV"
  # → adiciona Phase 01 ao ROADMAP, cria diretório da fase

# 3. Discuss — perguntas Django + React
/release:discuss 01
  # → backend: contrato API, escopo de tenant, estratégia ORM
  # → frontend: estrutura de component, slice Zustand, key TanStack Query, schema Zod
  # → trava D-01..D-22 em CONTEXT.md

# 4. Plan ambos os lados
/release:plan 01
  # → detecta: FULLSTACK
  # → backend: PLAN-BACKEND.md (pytest TDD, Q1-Q7, 9 security)
  # → frontend: PLAN-FRONTEND.md (vitest TDD, RC1-RC7, 9 security)
  # → integration check: campos do serializer ↔ schema Zod alinhados?

# 5. Executa backend primeiro (API antes de UI)
/release:execute 01 --backend
  # → RED → GREEN → REFACTOR → SECURITY
  # → pytest + ruff gated por commit

# 6. Executa frontend
/release:execute 01 --frontend
  # → RED → GREEN → REFACTOR → SECURITY
  # → vitest + tsc gated por commit

# 7. Verifica ambos
/release:verify 01
  # → backend: todo D-XX no code? Q1-Q7 presente? 9/9 security?
  # → frontend: todo D-XX no code? RC1-RC7 presente? vitest/tsc clean? sem localStorage?
  # → VERIFICATION.md: PASS ou GAPS_FOUND

# 8. Quality gates
/release:review 01       # review adversarial — REVIEW.md unificado Django + React
/release:security 01     # 9-categorias × 2 stacks
/release:checklist 01    # Q1-Q7 + RC1-RC7 grep

# 9. Ship
/release:ship
  # → pre-ship review → PR body grounded em SPEC/PLAN/UAT → gh pr create
  # → cursor avança pra shipped (sem auto-merge)
```

---

## Quick start — usando `/release:auto`

Se você não quer decorar 32 comandos, use o roteador:

```bash
/release:auto "fix the bug where invoice export crashes on PDFs >10MB"
  # → rota: /release:debug — razão: bug report com signal de crash durante fase ativa

/release:auto "add archived_at field to Invoice + migration + serializer"
  # → rota: /release:quick — razão: multi-arquivo bounded (4), sem novo design

/release:auto "rename EmpresaSerializer.user_email to owner_email"
  # → rota: /release:fast — razão: rename single-file, < 30 LOC

/release:auto "executa todas as fases que faltam"
  # → rota: /release:autonomous — razão: walk-away multi-fase com verify gating

/release:auto "onde estou"
  # → rota: /release:status

/release:auto "import this GSD repo"
  # → rota: /release:import — razão: GSD .planning/ presente, .release-planning/ ausente
```

---

## Artefatos de planning

```
.release-planning/                          # release-sdk-owned (renomeado em v0.5.0 pra coexistir com GSD .planning/)
├── PROJECT.md                              # LOCK-01..LOCK-12 (imutável)
├── RELEASE-LOCKS.md                        # tabela LOCK-XX extraída/importada
├── ROADMAP.md                              # lista de fases
├── REQUIREMENTS.md                         # REQ-XX
├── STATE.md                                # cursor
├── codebase/                               # output de /release:map-codebase
│   ├── STACK.md
│   ├── ARCHITECTURE.md
│   ├── QUALITY.md
│   └── CONCERNS.md
├── intel/                                  # output de intel-updater (cached)
│   ├── MODELS.md
│   ├── ROUTES.md
│   ├── COMPONENTS.md
│   ├── MIGRATIONS.md
│   ├── DEPENDENCIES.md
│   └── TEST-MAP.md
├── research/                               # research ecosistema + projeto
│   ├── PROJECT-ECOSYSTEM.md
│   └── SUMMARY.md                          # output de release-research-synthesizer
├── debug/{session_id}/                     # sessões persistentes de /release:debug
├── forensics/                              # post-mortems de /release:forensics
├── AUDIT-UAT.md                            # output de /release:audit-uat
├── audit-fix-log.md                        # log de loop /release:audit-fix
└── phases/
    └── {NN}-{slug}/
        ├── {NN}-SPEC.md                    # output do spec (score de ambiguidade)
        ├── {NN}-CONTEXT.md                 # output do discuss (D-XX backend + frontend)
        ├── {NN}-ASSUMPTIONS.md             # output de assumptions-analyzer
        ├── {NN}-RESEARCH.md                # output do researcher (single-stack)
        ├── {NN}-PLAN/                      # v0.11.0+ wave-split DIR
        │   ├── manifest.md                  # must_haves + threat_model 9-cat + waves table
        │   ├── W1-red-tests.md              # ~200-600 linhas, 3-5 tasks (hard cap 600)
        │   ├── W2-{subsystem}.md
        │   ├── ...
        │   └── WN-verify.md
        ├── {NN}-PLAN-BACKEND/               # (fullstack: lado Django — dir de waves)
        ├── {NN}-PLAN-FRONTEND/              # (fullstack: lado React — dir de waves)
        ├── {NN}-PLAN.md                    # legacy single-file (pré-v0.11) OR fullstack orchestration < 200 linhas
        ├── {NN}-PLAN-CHECK.md              # plan-checker veredito pre-execute (inclui wave budget audit)
        ├── {NN}-CONVERGENCE-LOG.md         # iterações de /release:plan-review-convergence
        ├── {NN}-PATTERNS.md                # output de pattern-mapper
        ├── {NN}-UI-SPEC.md                 # contrato design UI (fases frontend)
        ├── {NN}-UI-CHECK.md                # react-ui-checker veredito pre-impl
        ├── {NN}-UI-REVIEW.md               # react-ui-auditor audit scored
        ├── {NN}-AI-SPEC.md                 # contrato design AI (fases AI)
        ├── {NN}-EVAL-REVIEW.md             # relatório cobertura eval-auditor
        ├── {NN}-FRAMEWORK-DECISION.md      # matriz scored framework-selector
        ├── {NN}-SUMMARY.md                 # output do execute
        ├── {NN}-CHECKLIST.md               # Q1-Q7 + RC1-RC7
        ├── {NN}-SECURITY.md                # audit de segurança
        ├── {NN}-TEST-AUDIT.md              # mapa cobertura testes
        ├── {NN}-NYQUIST-AUDIT.md           # audit ≥2-testes-por-req
        ├── {NN}-TEST-GAP.md                # relatório gap modo test-only /release:add-tests
        ├── {NN}-UAT.md                     # items de acceptance observáveis pelo user
        ├── {NN}-VERIFICATION.md            # output do verify
        └── {NN}-SHIP-REVIEW.md             # findings pre-ship review /release:ship
```

---

## Por que isso existe

A maioria das ferramentas de AI coding deixam você shippar features rápido. Poucas deixam shippar features que honram o que você decidiu ontem.

**O problema:**
- Você discute arquitetura com Claude → Claude propõe solução → você aceita
- Próxima sessão, Claude esqueceu, propõe solução diferente, você aceita de novo
- Depois de 10 features: 4 padrões de auth, 3 abordagens de state management, 2 convenções de naming de API

**Solução do release-sdk:**
- Toda escolha arquitetural travada como LOCK-XX (project) ou D-XX (phase) em Markdown
- Todo planner, executor, verifier lê esses locks ANTES de escrever código
- Verifier confirma que locks estão no código real, não só no narrativo
- Hooks avisam de violações antes do commit
- Em v0.6.1 em diante: `/release:init` injeta bloco delimitado no `CLAUDE.md` raiz, garantindo que toda futura sessão Claude Code saiba que release-sdk tá ativo

Essa é a metodologia GSD, especializada pra engenharia full-stack Django + React.

---

## Referência

Metodologia GSD (`get-shit-done`) por Brennan Hughes.

- GSD: https://github.com/brennanhughes/get-shit-done
- release-sdk: https://github.com/lucasalvesborges/release-sdk

---

## Compatibilidade

- Django 5.2 LTS (4.x com adaptação mínima)
- DRF 3.16.x
- Python 3.12+
- React 18 + TypeScript 5.x
- Vite 5.x / Next.js 14+
- Claude Code 2.x+

---

## Licença

MIT
