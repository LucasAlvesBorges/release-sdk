---
name: tokens
description: >
  Token tracker dashboard. Inicia worker daemon HTTP em localhost:47777 (se ainda não estiver
  rodando) e abre o dashboard no browser padrão. Mostra custo $ por sessão/dia/semana/all-time,
  breakdown por workflow, agente, fase, complexidade e modo, além de tempo, spawns, gates e cache
  hit ratio. Dados gravados em ~/.claude/token-tracker/events.jsonl via hook
  PostToolUse que parseia transcripts JSONL do Claude e do Codex.
  Use quando: o usuário quiser ver gasto/eficiência de tokens, comparar custo entre skills,
  ou diagnosticar baixo cache hit.
---

# /release:tokens — Token Tracker Dashboard

Abre o dashboard de tokens em `http://localhost:47777`.

## Comportamento

O coletor aceita os dois schemas de transcript: `assistant.message.usage` do Claude e
`event_msg/token_count` do Codex. No Codex, `total_token_usage` é cumulativo; o cursor persiste o
último total e o evento gravado contém somente o delta. `cached_input_tokens` e
`cache_write_input_tokens` são separados de `input_tokens` para evitar dupla contagem.

1. **Verificar worker**: `curl -sf http://127.0.0.1:47777/api/health` (timeout 1s).
2. **Spawn se off**: se a porta não responder, lançar daemon detached:
   ```bash
   nohup node "$PLUGIN_DIR/bin/release-token-worker.js" \
     > ~/.claude/token-tracker/worker.log 2>&1 &
   disown
   ```
   Aguardar ~1s e re-checar `/api/health`. Se falhar, reportar log path e abortar.
3. **Abrir browser**: `open "http://localhost:47777?session_id=$SESSION"` (macOS) ou `xdg-open`
   (Linux). Passar `session_id` da sessão atual para destacar custo da conversa atual.
4. **Mensagem resumo**: imprimir 1 linha com KPI agregado da última hora (cost + cache hit).

## Argumentos opcionais

| Arg | Efeito |
|-----|--------|
| `--stop` | Mata o worker via PID file `~/.claude/token-tracker/worker.pid`, não abre browser |
| `--reset` | Apaga `events.jsonl` (pedir confirmação antes — operação destrutiva) |
| `--port=N` | Override porta (default 47777, usar quando colidir com outro processo) |
| `--no-browser` | Spawn worker mas não abre browser |

## Localizar PLUGIN_DIR

Plugin pode estar em:
1. `~/.claude/plugins/cache/release-sdk/release/<version>/`
2. Repo local em desenvolvimento (raiz do projeto)

Detectar via:
```bash
PLUGIN_DIR=$(dirname "$(dirname "$(realpath "$0")")")
# Ou buscar pelo arquivo:
WORKER=$(find ~/.claude/plugins/cache/release-sdk -name release-token-worker.js 2>/dev/null | head -1)
[ -z "$WORKER" ] && WORKER="$(pwd)/bin/release-token-worker.js"
```

## Custo

Pricing hardcoded no worker (`bin/release-token-worker.js`, const `PRICING`):

| Modelo | Input $/Mtok | Output $/Mtok | Cache read | Cache write |
|--------|-------------:|--------------:|-----------:|------------:|
| Opus 4.7 | 15 | 75 | 1.5 | 18.75 |
| Sonnet 4.6 | 3 | 15 | 0.3 | 3.75 |
| Haiku 4.5 | 1 | 5 | 0.1 | 1.25 |

Atualizar quando Anthropic mudar preços.

## Métricas de eficiência

- **Cache hit %**: `cache_read / (input + cache_read + cache_create)` — quanto maior, mais barato
- **tok/turno**: total tokens / turnos — saturação do contexto. Acima de 100k indica conversa longa
- **$/workflow e $/agent**: separa custo do orquestrador e dos workers
- **tempo, spawns e gates**: mostra onde latência e fan-out crescem sem ganho proporcional
- **fase/complexidade/modo**: permite comparar C0–C4, execução normal, strict, loop e agent

## Privacidade

- Dados ficam **locais** em `~/.claude/token-tracker/events.jsonl`. Worker só escuta `127.0.0.1`
- Schema do evento permanece retrocompatível e adiciona `workflow`, `agent`, `agent_id`, `phase`,
  `complexity`, `mode`, `latency_ms`, `spawns` e `gate_runs`
- **Não grava** conteúdo de mensagens — apenas contadores de tokens
- Para apagar histórico: `/release:tokens --reset`
