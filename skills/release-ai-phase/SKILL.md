---
description: >
  AI/LLM phase design contract. Reads SPEC.md + PROJECT.md + RELEASE-LOCKS.md, asks only unanswered
  questions (LLM provider, hosting model, prompt structure, evaluation strategy, guardrails, monitoring),
  then routes to release-ai-researcher. Defaults to Anthropic SDK (claude-sonnet-4-6) with prompt caching,
  tool use, and streaming. Produces AI-SPEC.md design contract consumed by /release:plan --fullstack.
  Use when: phase embeds LLM/AI features in a Django+React app (chat, summarization, structured extraction,
  RAG, agents, vision, tool use).
allowed_tools: Agent, Read, Write, Bash, Grep, Glob, AskUserQuestion
---

# /release:ai-phase — AI/LLM Feature Design Contract

For phases that embed an LLM call inside a Django backend with a React frontend. Produces `AI-SPEC.md`
before planning so prompt structure, eval strategy, and guardrails are decided up-front (not retrofitted).

## Usage

```
/release:ai-phase 01                 # interactive — asks only unanswered questions
/release:ai-phase 01 --revise        # re-run after edits to SPEC.md or LOCKs
/release:ai-phase 01 --provider anthropic   # force provider (skips Q1)
/release:ai-phase 01 --provider openai
/release:ai-phase 01 --provider langchain
/release:ai-phase 01 --no-researcher # write AI-SPEC.md draft only, skip release-ai-researcher
```

> Previously: `--gsd-context` flag. Removed in v0.4.0 — use `/release:import` once to convert GSD planning files; all skills then assume release-sdk native format.

## When to use

Activate this skill when the phase description includes any of:

- LLM / GPT / Claude / generative AI / chat / chatbot / assistant
- Summarization, extraction, classification (LLM-powered)
- RAG, embeddings, vector search, semantic search
- Tool use / function calling / agent
- Streaming responses, SSE, server-sent events for AI
- Vision (image understanding), document Q&A

If the phase is non-AI (CRUD, dashboards, batch jobs without LLM) → use `/release:plan` directly.

## Workflow

### Step 1 — Load context (parallel reads)

Read every file that exists, skip gracefully if missing:

| File | Used for |
|---|---|
| `.planning/phases/{NN}-{slug}/SPEC.md` | Problem statement, acceptance criteria, scope |
| `.planning/PROJECT.md` | Project domain, team |
| `.planning/RELEASE-LOCKS.md` | LOCK-01 (Django version), LOCK-03 (auth), LOCK-07 (React+Vite), LOCK-09 (httpOnly cookie), LOCK-10 (Zod), LOCK-12 (API contract) |
| `.planning/ROADMAP.md` | Phase entry text |
| Existing AI code (probe) | `grep -rln "anthropic\|openai\|langchain\|llama_index" backend/ frontend/` |

If `.planning/phases/{NN}-{slug}/SPEC.md` is missing → abort with:
> "Run `/release:spec {NN}` first — AI phases need a clear problem statement before design."

### Step 2 — Detect already-answered questions

Scan SPEC.md and PROJECT.md for signals that already pin a decision. Mark each of the 6 question groups as `[ANSWERED]`, `[INFERRED]`, or `[OPEN]`.

| Question | Signal | If found |
|---|---|---|
| Q1 Provider | "Anthropic", "Claude", "GPT", "OpenAI", "Bedrock", "LangChain", "LlamaIndex" in SPEC/PROJECT | `[ANSWERED]` |
| Q2 Hosting | "Django proxy", "SSE", "WebSocket", "streaming", existing `apps/ai/` or `apps/llm/` | `[INFERRED]` |
| Q3 Prompt shape | "tool use", "function calling", "structured output", "JSON schema", "vision" | `[INFERRED]` |
| Q4 Evaluation | "golden dataset", "eval", "LLM-as-judge", "deepeval", "promptfoo" | `[INFERRED]` |
| Q5 Guardrails | "rate limit", "moderation", "prompt injection", "PII", "redaction" | `[INFERRED]` |
| Q6 Monitoring | "Langfuse", "Helicone", "Phoenix", "OpenLLMetry", "cost tracking" | `[INFERRED]` |

Show the extraction report:

```
AI Phase Context — Extraction Report
════════════════════════════════════════
Phase: {NN}-{slug}

Q1 Provider     [ANSWERED]  Anthropic SDK (claude-sonnet-4-6)
Q2 Hosting      [INFERRED]  Django proxy with SSE streaming — will confirm
Q3 Prompt       [OPEN]      no signals
Q4 Evaluation   [OPEN]      no signals
Q5 Guardrails   [INFERRED]  rate limit via DRF throttling — will confirm
Q6 Monitoring   [OPEN]      no signals
════════════════════════════════════════
```

### Step 3 — Ask only `[OPEN]` and `[INFERRED]` questions

Use **AskUserQuestion** for each non-answered group. Skip `[ANSWERED]`.

#### Q1 — LLM Provider / Framework (default: Anthropic SDK)

Options offered:
- **Anthropic SDK** (recommended default) — direct `anthropic` Python + `@anthropic-ai/sdk` if needed.
  Model: `claude-sonnet-4-6` (latest as of 2026-05). Prompt caching, tool use, streaming all first-class.
- **OpenAI SDK** — direct `openai` Python. Model: `gpt-4o` / `o1`.
- **LangChain** — orchestration framework on top of Anthropic/OpenAI. Use when chains/agents are non-trivial.
- **LlamaIndex** — RAG-first framework. Use when retrieval is the dominant concern.
- **Bedrock / Vertex** — cloud-managed.
- **Other / custom**.

Skipped if `--provider` flag set.

#### Q2 — Hosting architecture

Options offered:
- **Django proxies LLM calls** (recommended) — React → Django → LLM provider. Secrets in `settings.py`, never in browser. **This is the only acceptable pattern when LOCK-09 (httpOnly cookie auth) is set** — the API key must never reach the browser.
- **Direct from React with API key** — REJECTED unless the key is short-lived, scoped, and proxied through a backend session. Flag as a security blocker in AI-SPEC.
- **Streaming model:** SSE (recommended for Django — `StreamingHttpResponse`), WebSockets (Django Channels), polling, or non-streaming.

Note: when Q1 = Anthropic SDK, recommend `stream=True` with `client.messages.stream(...)` piped through Django `StreamingHttpResponse` and consumed by React with `EventSource` or `fetch` + `ReadableStream`.

#### Q3 — Prompt contract

Ask which of these the feature needs (multi-select via AskUserQuestion):
- **System prompt** (always) — set role, output format, refusal rules.
- **User prompt** with template variables — what variables, validated by Zod on frontend + serializer on backend.
- **Tool use / function calling** — list tools, their JSON schemas, max iterations, parallel-tool-use yes/no.
- **Structured output** — JSON schema enforced via tool-use trick (Anthropic) or `response_format` (OpenAI).
- **Vision** — image input (base64 / URL), max images, max resolution.
- **Prompt caching** (Anthropic) — recommended when system prompt > 1024 tokens or repeated context. Save 90% cost on cache hits.
- **Few-shot examples** — how many, sourced from where.

#### Q4 — Evaluation strategy

Ask:
- **Golden dataset** — initial size (target 20-50 cases minimum), source (manually curated / production logs / synthetic), stored where (`.planning/phases/{NN}-{slug}/eval/golden.jsonl`).
- **Judge** — exact match / regex / LLM-as-judge / human review only. If LLM-as-judge, recommend Claude with a separate rubric prompt.
- **Metrics** — accuracy, F1, BLEU, ROUGE, custom rubric score, refusal rate, latency p50/p95, cost per request.
- **Cadence** — pre-merge gate? nightly CI? weekly? on every prompt change?
- **Regression bar** — drop > X% on golden set → block merge.

#### Q5 — Guardrails

Ask which apply:
- **Rate limit** — per user, per tenant, per IP. Recommend DRF `ScopedRateThrottle` + Redis backend.
- **Content moderation** — Anthropic has native refusal; OpenAI has Moderation API. Pre-filter user input or post-filter LLM output?
- **Prompt injection defense** — input sanitization, system-prompt isolation, output validation against schema, no tool execution on untrusted input without confirmation.
- **PII scrubbing** — strip emails, CPF, CNPJ, phone numbers from prompts and logs. Recommend a regex pre-filter + audit log of redactions.
- **Cost cap** — per-request token cap (`max_tokens`), per-user daily budget, kill switch.

#### Q6 — Production monitoring

Ask:
- **Cost per request** — log `usage.input_tokens` + `usage.output_tokens` per call (Anthropic returns this).
- **Latency** — track TTFT (time to first token) for streaming + total duration.
- **Quality signals** — thumbs up/down on frontend? structured user feedback?
- **Hallucination / failure rate** — % of responses failing schema validation, % flagged by judge model.
- **Eval pipeline cadence** — when does the golden-set eval run in production?
- **Observability tool** — Langfuse / Helicone / Phoenix / OpenLLMetry / plain logging to PostgreSQL + Grafana.

### Step 4 — Write AI-SPEC.md

Path: `.planning/phases/{NN}-{slug}/AI-SPEC.md`.

Use `templates/AI-SPEC.md` as the template. Fill every section. For `[ANSWERED]` items, cite the source file
(e.g., `from SPEC.md §Constraints`). For user-answered items, record the decision verbatim.

### Step 5 — Route to release-ai-researcher

Unless `--no-researcher`, spawn the `release-ai-researcher` agent with `<config>` pointing at the new AI-SPEC.md.
The researcher probes the Django + React codebase for existing AI integration points, evaluates framework fit
against LOCKs, and appends a `## Researcher Findings` section to AI-SPEC.md.

### Step 6 — Commit artifact

```bash
git add .planning/phases/{NN}-{slug}/AI-SPEC.md
git commit -m "ai-spec({NN}): design contract for {slug}"
```

### Step 7 — Output summary

```
AI Phase Design Contract written
════════════════════════════════════════
Phase: {NN}-{slug}
Provider: {provider} ({model})
Hosting: Django proxy + {streaming-mode}
Prompt: {shape summary}
Eval: {dataset size} cases, {judge type}, {cadence}
Guardrails: {list}
Monitoring: {tool}

Next: /release:plan {NN} --fullstack
  → backend pipeline plans apps/{ai-app}/ (Django proxy, throttle, eval harness)
  → frontend pipeline plans streamed-response UI
```

## Defaults

- **Provider**: Anthropic SDK (`anthropic` Python package, `@anthropic-ai/sdk` if a frontend call is unavoidable).
- **Model**: `claude-sonnet-4-6` (latest as of 2026-05). Falls back to `claude-haiku-4-6` for cost-sensitive paths.
- **Prompt caching**: ON for any system prompt > 1024 tokens or any repeated context. Use `cache_control: {"type": "ephemeral"}` markers.
- **Tool use**: prefer Anthropic's native tool-use over LangChain when only 1-5 tools are needed.
- **Streaming**: SSE via `StreamingHttpResponse` on Django; `EventSource` or `fetch` + `ReadableStream` on React.
- **Eval framework**: lightweight `pytest` + golden JSONL + LLM-as-judge with Claude. Promote to `promptfoo` only if eval cases > 200.
- **Observability**: log `model`, `input_tokens`, `output_tokens`, `latency_ms`, `cost_usd`, `cache_hit_tokens` to a dedicated Django model (`AILog`) — Langfuse/Helicone optional.

## Output

```
.planning/phases/{NN}-{slug}/
  AI-SPEC.md             # design contract (this skill's output)
```

## Example

```
/release:ai-phase 04

→ Reading SPEC.md, PROJECT.md, RELEASE-LOCKS.md
→ Phase 04: "Auto-summarize invoice line items into a customer-facing description"
→ Extraction report:
    Q1 Provider     [INFERRED]  no signal — defaulting to Anthropic SDK (claude-sonnet-4-6)
    Q2 Hosting      [INFERRED]  LOCK-09 (httpOnly cookie) forces Django proxy
    Q3 Prompt       [OPEN]      asking
    Q4 Evaluation   [OPEN]      asking
    Q5 Guardrails   [INFERRED]  LOCK-02 (multi-tenant) → per-empresa rate limit
    Q6 Monitoring   [OPEN]      asking

→ AskUserQuestion: confirm Anthropic SDK? (Y / OpenAI / LangChain / other)
→ AskUserQuestion: SSE streaming or single response?
→ AskUserQuestion: tool use needed? structured output?
→ AskUserQuestion: golden dataset size + judge model?
→ AskUserQuestion: per-empresa rate limit threshold?
→ AskUserQuestion: observability tool?

→ Writing AI-SPEC.md...
→ Spawning release-ai-researcher → appending findings
→ Committing

→ Next: /release:plan 04 --fullstack
```
