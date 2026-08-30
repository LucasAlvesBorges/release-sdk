# release-sdk

> Kit de aceleração full-stack para Claude Code e Codex Desktop. Django + React + React Native. Distribuições isoladas por runtime.

> 🇺🇸 [English version](./README.en.md) (mirror)

Comandos `/release:*` context-aware roteiam automaticamente para os agents certos baseado nos seus arquivos e ROADMAP. Um SDK, três stacks (Django · React · React Native).

**Porta de entrada:** **`/release:auto <sua intenção em linguagem natural>`** — roteador leve que lê estado só quando precisa desempatar, imprime a rota escolhida e nunca ativa loops implicitamente.

**Versão atual: v0.26.0** — fluxos adaptativos C0–C4, especialistas sob demanda, invocação curta `/release:*` e distribuições próprias para Claude Code e Codex. Veja [CHANGELOG.md](./CHANGELOG.md) pra evolução completa.

---

## Skills especialistas por stack

Quatro especialistas compactos ficam disponíveis para dúvidas realmente específicas da stack. Os fluxos `spec`, `plan`, `execute`, `quick`, `loop` e `review` não carregam uma segunda persona apenas porque encontraram Django ou React; referências aprofundadas são abertas somente para a superfície afetada.

| Skill | Uso |
|-------|-----|
| `django-expert` | decisão específica de Django/DRF, ORM, migrations ou concorrência |
| `react-expert` | estado, renderização, acessibilidade, segurança ou testes web |
| `react-native-expert` | fronteiras nativas/Expo, lifecycle, storage, navegação ou performance mobile |
| `security-expert` | investigação ofensiva explicitamente autorizada e delimitada |

- Cada entrada principal tem cerca de 200–320 palavras e roteia para `references/*.md` por assunto.
- O especialista resolve uma incerteza estreita e devolve o controle ao workflow dono da tarefa.
- Auditoria completa continua em `/release:security`; revisão de diff, em `/release:review`.

> Distribuição: os experts vivem em `skills/` do plugin e chegam via `autoUpdate` após publicação. Os experts globais do usuário (`~/.claude/skills/django-expert` e `security-auditor`) foram **arquivados** (`~/.claude/archived-global-experts/`) — o SDK não usa experts globais; a fonte é só o repo/plugin. O `security-expert` é a persona de segurança ofensiva author-time (dispara em intenção de auditoria/pentest, não preempta os experts de stack em implementação de rotina; cobre backend + web + mobile — ver `references/mobile.md`); distinto do agent `security-auditor` (worker spawnado por `/release:security`).

---

## A ideia central

**Você define a arquitetura uma vez. Toda feature subsequente honra o que você travou.**

1. `/release:init` — captura visão, trava stack backend + frontend, modelo de auth, padrões proibidos → `PROJECT.md` (LOCK-01..LOCK-12)
2. `/release:roadmap` — decompõe milestone em fases vertical-slice → `ROADMAP.md`
3. Por fase: `/release:spec` → `/release:plan` → `/release:execute` → `/release:verify`; `plan` resolve gray areas antes de criar o PLAN
4. Decisões D-XX vivem no SPEC compacto, são referenciadas pelo PLAN e verificadas contra o codebase real

Zero suposição silenciosa. Zero "v1 / placeholder / vai ser ligado depois". Zero mudança não-rastreável.

---

## Orquestração adaptativa de custo

`bin/release-economy-lib.sh` classifica C0–C4 e escolhe o menor fluxo compatível com o risco:

| Perfil | Escopo típico | Execução |
|---|---|---|
| lean (C0/C1) | trivial/bem delimitado | inline, teste focado, sem subagent |
| standard (C2) | feature moderada | um planner ou worker, passagem única, gate final |
| strict (C3/C4) | arquitetura ou risco real | checker independente e paralelismo só com 3+ tasks disjuntas |

Auth, pagamentos, privacidade e tenancy têm piso C3; migração destrutiva/data loss, C4. O perfil padrão de Claude é `opus-sonnet`; checker C0–C2 usa um turno independente no tier de worker e só C3/C4 sobe ao tier do orquestrador. Effort é `low/medium/high/max` por complexidade. No Codex, coordenação comum usa Terra/medium; Frontier fica reservado a decisões realmente complexas ou críticas.

`quick` e `execute` não entram em loop automaticamente. `/release:loop` ou `execute --loop` são explícitos e limitados a 1/2/3 correções por perfil, com teto padrão de USD 5.

`/release:tokens` mede custo por workflow, agente, fase, complexidade e modo, junto com latência,
spawns e execuções de gate. Isso permite comparar o custo real de C1/C2 com `strict`/`loop` sem
gravar o conteúdo das mensagens.

---

## Novidades (v0.5 → v0.16)

- **v0.19.0** — **Orquestração por tier de modelo.** Toda operação vira um loop de dois tiers: orquestrador (Fable) faz fan-out pra workers (Opus), cada worker loopa sozinho, e o orquestrador loopa pra avaliar — checker sempre um tier acima do maker (maker≠checker literal). Fallback quando não há Fable: orquestrador Opus + workers Sonnet. Perfil **auto-detectado** do model da sessão (o LLM sabe o próprio model — nunca pergunta, nunca spawna tier que você não tem). Nova lib `bin/release-model-lib.sh` (SSOT) + `bin/test-model-lib.sh` (23 asserts). Override raro via env `RELEASE_MODEL_PROFILE`/`MODELS.yml`. Fiado em `execute`/`loop`/`quick`/`security`/`debug` + `wave-executor`; doctrine LOCKED no router herdada por todas as skills. Tudo em effort máximo (exceção: `test-discover`/Haiku).

- **v0.17.0** — merge-back automático: rode uma fase + vários `/release:quick` em paralelo e **veja a feature funcionando ao vivo** no seu trunk. `quick` e `execute` isolam em worktree **e aterrissam sozinhos** na base quando os testes passam (hot-reload pega na hora); checkout sujo é **segurado, nunca sobrescrito** (`held-dirty`). Motor único `land_branch` (`bin/release-merge-lib.sh`) compartilhado por `session finish`/`quick`/`execute`/novo `/release:land`, serializado por lock por-base. Teste 48→66 asserts agora *sourceia* o motor real (zero drift). BREAKING: `quick` não commita mais no teu checkout; `execute` não deixa mais `feat/<NN>` solto (use `--no-merge`/`--pr` pro comportamento antigo).
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
│  /release:spec {NN}     →  SPEC.md compacto (AC + D-XX + riscos)          │
│  /release:plan {NN}     →  resolve gray areas + cria PLAN uma única vez    │
│  /release:execute {NN}  →  uma passagem + testes focados + gate final     │
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
│                            sequência (spec→plan→execute→verify).          │
│                            Aborta na primeira falha de verify.            │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## Comandos slash

### Entry point
| Comando | Stack | Propósito |
|---|---|---|
| `/release:auto {intent}` | both | **Roteador de intenção livre.** Mapeia seu prompt para o skill `/release:*` certo. Imprime rota + razão antes de invocar. |

### Ciclo de vida do projeto + fase
| Comando | Stack | Propósito |
|---|---|---|
| `/release:init` | both | Inicializa PROJECT.md (LOCK-01..LOCK-12). Injeta bloco delimitado no CLAUDE.md raiz. |
| `/release:import` | both | Mass-port GSD `.planning/` → release-sdk `.release-planning/` (one-shot, todas as fases) |
| `/release:spec {NN}` | both | Esclarece O QUE a fase entrega (SPEC.md, score de ambiguidade) |
| `/release:plan {NN}` | both | Resolve gray areas em lotes de até 3, grava D-XX e gera um PLAN pronto para execute |
| `/release:ui-phase {NN}` | frontend | Produz UI-SPEC.md (contrato de design) |
| `/release:ai-phase {NN}` | both | Produz AI-SPEC.md (framework LLM, prompts, eval, guardrails) |
| `/release:execute {NN}` | both | Execução TDD-strict (pytest ou vitest). **Auto-land** na base quando a fase passa (`--no-merge`/`--pr` pra segurar) |
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
| `/release:architecture` | both | Review clean-code + escalabilidade (2 dims + Scale Ceiling) — ARCH-REVIEW.md |
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
| `/release:quick` | both | Task bounded multi-arquivo com TDD executor, **isolado em worktree** (N quicks em paralelo, sem colisão) + **auto-land** na base ao passar. Cursor intocado. Entre fast e plan. |
| `/release:forensics` | both | Post-mortem pra workflows que falharam. Timeline + 5-whys + plano de recovery. |
| `/release:add-tests {NN}` | both | Backfill de cobertura UAT ou cobertura de regressão pra um arquivo. |

### Repo intelligence
| Comando | Stack | Propósito |
|---|---|---|
| `/release:map-codebase` | both | Análise paralela 4-focus do codebase (tech, arch, quality, concerns) → `.release-planning/codebase/*.md` |
| `/release:docs-update` | both | Regenera README/CONTRIBUTING/ARCHITECTURE verificados contra o codebase |
| `/release:session [sub]` | both | Sessões paralelas worktree-native: `start`/`sync`/`finish`/`list`/`doctor`/`cleanup`/`abort`/`base`. N domínios independentes → um trunk, merge-back serializado conflict-safe |
| `/release:land [label]` | both | Aterrissa na base uma unidade segurada/`--no-merge` (`quick/*`, `feat/*`, `session/*`) — retry do auto-merge, mesmo motor serializado conflict-safe. `--all` aterrissa todas |
| `/release:workstreams [sub]` | both | ⚠️ Deprecated (v0.15) — substituído por `/release:session` |

### Qualidade padrão de implementação

Clean Code faz parte de todo `/release:fast`, `/release:quick`, `/release:execute` e
`/release:loop`; não exige uma skill separada. O executor usa nomes significativos, funções coesas,
guard clauses, booleanos nomeados e abstrações somente quando removem duplicação real, separam uma
responsabilidade ou protegem um conceito de domínio. Refatorações começam com testes verdes,
avançam em baby steps e preservam assinaturas e comportamento externo.

### Legacy single-stack (mantidos por compatibilidade)
| Comando | Stack | Propósito |
|---|---|---|
| `/django:review` | backend | Review Django-only |
| `/django:security` | backend | Audit de segurança Django-only |

---

## Agents — Singletons (release-sdk nativos)

### Plan
| Agent | Papel |
|---|---|
| `spec-clarifier` | Clarifica contrato/aceitação no preflight estrito de spec ou plan |
| `assumptions-analyzer` | Análise profunda e delimitada quando uma gray area depende do codebase |
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
| `architecture-reviewer` | Review clean-code (CC1-CC6) + escalabilidade stack-dispatched (Django SD1-SD7 / React SR1-SR6) com Scale Ceiling — spawned por `/release:architecture` |

### Django-specific (lógica pura Django)
| Agent | Papel |
|---|---|
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
| `release-efficiency-context.js` | SessionStart/SubagentStart | Injeta uma vez a política base de solução mínima, contexto compacto e uso opcional de RTK |
| `django-validate-commit.sh` | PreToolUse:Bash | Enforcement de Conventional Commits (ambas stacks) |
| `release-edit-guard.js` | PreToolUse:Write/Edit | Um único processo: teste focado, tenant scope, prompt injection e segurança React |
| `release-token-collector.js` | PostToolUse:* | Lê apenas bytes novos do transcript e alimenta o dashboard de custo |

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

### Claude Code — Marketplace

```
/plugin marketplace add LucasAlvesBorges/release-sdk
/plugin install release@release-sdk
```

Reinicie o Claude Code.

### Codex Desktop no macOS — Marketplace

O pacote Codex é gerado separadamente em `plugins/release/`; ele não altera nem
reutiliza a configuração do Claude Code.

```bash
codex plugin marketplace add LucasAlvesBorges/release-sdk
codex plugin add release@release-sdk
```

Para atualizar uma instalação existente:

```bash
codex plugin marketplace upgrade release-sdk
codex plugin remove release@release-sdk
codex plugin add release@release-sdk
```

Depois:

1. Abra **Plugins** no Codex Desktop e confirme **Release SDK** em **Installed**.
2. Em uma tarefa, selecione pelo `@` a skill `release:setup-codex` para instalar os agentes personalizados `release-*`.
3. Abra uma nova tarefa — os agentes personalizados são carregados no início da tarefa.

O instalador escreve somente arquivos `release-*.toml` em
`${CODEX_HOME:-$HOME/.codex}/agents/`. Nada em `~/.claude`, `.claude-plugin/`,
`CLAUDE.md` ou no cache do Claude é modificado.

Para desenvolver ou validar a edição Codex localmente:

```bash
python3 codex/build_plugin.py
python3 codex/test_compat.py
```

### Claude Code — clone local (recomendado pra dev)

```bash
git clone https://github.com/lucasalvesborges/release-sdk ~/.claude/plugins/release-sdk
# Reinicie o Claude Code
```

### Claude Code — symlink (dev ao vivo)

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

# 3. Spec — resultado, critérios e decisões que realmente mudam implementação
/release:spec 01
  # → um 01-SPEC.md compacto; pergunta só o que não dá pra inferir

# 4. Um plan fullstack
/release:plan 01
  # → um 01-PLAN.md, normalmente 2–8 tasks verticais
  # → lint estrutural determinístico; checker LLM só em risco C3/C4

# 5. Executa tudo uma vez
/release:execute 01
  # → testes focados durante build + um gate fullstack final + auto-land seguro
  # → use --loop somente quando quiser correção autônoma limitada

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
        ├── {NN}-SPEC.md                    # outcome + AC + D-XX + riscos
        ├── {NN}-PLAN.md                    # 2–8 tasks verticais; backend/frontend juntos
        ├── {NN}-CONTEXT.md                 # opcional: compatibilidade com fases antigas
        ├── {NN}-PLAN-CHECK.md              # opcional: review strict C3/C4
        ├── {NN}-CONVERGENCE-LOG.md         # iterações de /release:plan-review-convergence
        ├── {NN}-PATTERNS.md                # legado/opt-in; não gerado no fluxo padrão
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
- Codex Desktop para macOS / Codex CLI com suporte a plugins e subagentes

---

## Licença

MIT
