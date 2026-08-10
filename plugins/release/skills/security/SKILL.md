---
name: security
description: >
  Context-aware 9-category security audit PLUS an always-on advanced-threat audit. Routes .py
  files to security-auditor and .tsx/.ts files to security-auditor, and ALWAYS
  spawns advanced-threat-auditor in parallel (A1-A13 Django + RA1-RA5 React: race/TOCTOU,
  SSRF, deserialization, command injection, SSTI, XXE, JWT forgery, exploitation-grade SQLi,
  image/media DoS+RCE, AWS cloud-infra incl. IaC static checks). Produces one unified SECURITY.md.
  Use when: feature complete, pre-merge, or periodic security review.
---

## Codex runtime contract (generated; overrides incompatible source directives)

This skill is the Codex edition of release-sdk. The source workflow below is
kept for behavioral parity, but this contract has precedence whenever the
source mentions Claude Code primitives.

### Isolation

- Never create, edit, delete, or inspect runtime state under `~/.claude`,
  `.claude/`, `.claude-plugin/`, `.claude-plugin-cache/`, or `CLAUDE.md`.
- Release planning artifacts remain under `.release-planning/`. Durable Codex
  project guidance belongs in `AGENTS.md` only when the workflow explicitly
  needs to add it.
- Resolve `RELEASE_PLUGIN_ROOT` as the directory two levels above this
  `SKILL.md`. Resolve `RELEASE_PLUGIN_DATA` from `PLUGIN_DATA` when supplied;
  otherwise use `${CODEX_HOME:-$HOME/.codex}/release-sdk`.

### Step 0 — AGENTS.md gate

Before any Write/Edit/apply_patch, the target project MUST have a root
`AGENTS.md`. `release-agents-md-guard.js` enforces this at the hook level and
will block the write — do not try to route around it. If it blocks:
`.codex/config.toml`'s `[agents_md] mode` is `strict` (default: stop, tell the
user `AGENTS_MD_REQUIRED`) or `bootstrap` (spawn `release-agents-md-builder`
read-only, let it draft and save `AGENTS.md`, then stop and tell the user to
re-run the original task). Never fabricate the file yourself outside that
role, and never inline the full `AGENTS.md` content into a subagent prompt —
let Codex discover it normally from `cwd`.

### Step 1 — score complexity, then decide whether to spawn anything

Self-score the task C0–C4 using `complexity-rubric.md` before touching
anything else, apply the risk floors, then use `routing-policy.md`'s fleet
table for the level. Default is **no subagents** (`spawn = false`). Spawn one
only when ALL of:

```text
bounded_subtask
AND explicit_success_criteria
AND (independent OR noisy_output OR specialist_required OR broad_read_avoided)
AND estimated_context_avoided > spawn_overhead
```

Never spawn for C0. Never spawn just to "use multiagent." Never spawn a
subtask that immediately depends on another subtask's result and can't run in
parallel. Group reads over the same files instead of one agent per file.

**Read vs write:** read-only agents may run in parallel freely. Writers never
share a file set — one writer per path set, sequential when there's a
dependency, parallel only with disjoint scopes or isolated worktrees (declare
`allowed_paths`/`forbidden_paths` up front either way).

### Invoking a subagent

```text
Role: {role}
Single objective: {subtask_objective}

Allowed scope:
{allowed_paths}

Do not access:
{forbidden_paths}

Minimal context:
{task_specific_context}

Completion criteria:
{success_criteria}

Rules:
- Follow the AGENTS.md chain applicable to cwd.
- Do not expand scope on your own — return needs_scope_expansion instead.
- Do not restate the prompt back.
- Do not return full logs.
- Stop as soon as the criteria are met.
- Return only JSON matching SubagentResultV1.
```

Pass only this delta — never the full parent transcript, never the full
`AGENTS.md`, never whole files already in the workspace, never full logs.

### Handoff

Only when the task continues in another thread/session — see
`handoff-template.md` (60 lines / ~500 tokens max). Not a substitute for the
normal end-of-task summary.

### Tools

- Treat `Read`, `Write`, `Edit`, `Bash`, `Grep`, and `Glob` in the source as
  conceptual operations. Use the Codex tools currently available: targeted
  file reads, `apply_patch` for edits, `exec_command` for commands, and `rg`
  or `rg --files` for search.
- A source reference to `AskUserQuestion` means: use the structured user-input
  tool when it is available to the parent agent. A subagent must instead
  return `USER_INPUT_REQUIRED` with the exact question and 2-3 choices so the
  parent can ask it. If no structured input tool is available, ask one concise
  question in the parent task.
- A source reference to a `Skill` tool means to run the installed
  `release:<skill-name>` skill. If there is no callable skill tool, delegate to
  a `default` subagent with a task that explicitly names that installed skill,
  pass the original arguments unchanged, wait for it, and surface its result.

### Subagents

- Source agent names `release:<name>` are mapped in this generated edition to
  Codex custom agents named `release-<name>`.
- Spawn agents only through Codex collaboration tools. Do not emulate a
  subagent with a shell command and do not use a nonexistent `Task` or `Agent`
  tool.
- Prefer the named `release-<name>` agent when it is available. These agents
  are installed by the `release:setup-codex` skill and become available in a
  new task.
- If the exact named agent is not available, prefer this plugin's own generic
  roster before Codex's bare defaults: `release-explorer-fast` /
  `release-explorer-deep` for read-only research, `release-worker` /
  `release-worker-lite` / `release-worker-complex` for implementation,
  `release-reviewer` / `release-security-reviewer` for judgment-heavy review,
  `release-planner` for orchestration. Only fall back to Codex's bare
  `explorer` / `worker` / `default` if none of those are installed either —
  and in that case give the fallback agent the absolute path to
  `agents/release-<name>.toml` under `RELEASE_PLUGIN_ROOT` and require it to
  read and follow the `developer_instructions` before working.
- For write tasks, assign explicit file ownership and tell every worker that
  other agents may be editing the repository; it must preserve and integrate
  others' changes. Parallelize only independent scopes and respect the current
  session's concurrency limit.
- Wait for required agents, collect their final results, and keep completion
  judgment in the parent/orchestrator. A worker never declares the overall
  workflow complete.

### Models and reasoning

- Ignore source instructions that pin or derive Claude model tiers such as
  Fable, Opus, Sonnet, or Haiku, and ignore `CLAUDE_EFFORT`. Those do not
  apply in Codex.
- Every `release-<name>` custom agent already carries its own
  `model`/`reasoning_effort` per `routing-policy.md` — spawn it as-is. Only
  request a higher reasoning effort than the agent's default when the C0–C4
  fleet table for this task's level calls for it (`complexity-rubric.md`);
  never request a lower one.
- Preserve maker-versus-checker independence by using distinct agent turns —
  a checker runs as its own spawn, never as a self-review by the maker.

### Invocation vocabulary

- `/release:<name>` in the source is a workflow label retained for
  compatibility. In Codex Desktop the user selects the `release` plugin or its
  `release:<name>` skill from the composer.
- `claude` CLI launch examples map to `codex` in this generated edition.

# /release:security — Full-Stack Security Audit

Routes to the correct security auditor based on file type. Unified SECURITY.md output.

## Usage

```
/release:security 01                         # audit phase 01 files
/release:security backend/apps/financeiro/   # Django-only audit
/release:security src/features/Invoices/     # React-only audit
/release:security --diff main..HEAD          # audit changed files
```

## Model tiers (LOCKED — see /release:auto → "Model-Tier Orchestration")

This audit IS the loop topology: the **orchestrator** (this session) fans out to **worker auditors**,
then **evaluates** their findings on the orchestrator tier. Resolve tiers ONCE before spawning — you are
the orchestrator; self-identify (if your session model is Opus, not Fable: `export RELEASE_MODEL_PROFILE=opus-sonnet`):
```bash
find_lib(){ local p="${RELEASE_PLUGIN_ROOT:+$RELEASE_PLUGIN_ROOT/bin/$1}"; [ -n "$p" ]&&[ -f "$p" ]&&{ printf %s "$p"; return; }; find "${CODEX_HOME:-$HOME/.codex}" -name "$1" -path '*/bin/*' 2>/dev/null|head -1; }
MODEL_LIB="$(find_lib release-model-lib.sh)"; [ -f "$MODEL_LIB" ] && . "$MODEL_LIB"
WORKER_MODEL="$(  [ -f "$MODEL_LIB" ] && release_worker_model  || echo sonnet )"   # security-auditor, advanced-threat-auditor
CHECKER_MODEL="$( [ -f "$MODEL_LIB" ] && release_checker_model || echo opus   )"   # code-fixer verification / re-audit orchestration
```

## Routing logic

1. Resolve scope: phase directory, explicit paths, or git diff.
2. Split `.py` → `release-security-auditor`, `.tsx/.ts` → `release-security-auditor`. Spawn each with
   `model: $WORKER_MODEL` and a prompt suffix "operate at maximum rigor / max effort".
3. **ALWAYS** spawn `release-advanced-threat-auditor` (also `model: $WORKER_MODEL`) over the SAME resolved
   scope, regardless of detected surface (it is never conditional on a trigger surface being present). It
   runs in PARALLEL with the 9-category `release-security-auditor` pass.
4. Run all auditors in parallel; their findings merge into ONE SECURITY.md (the advanced auditor
   APPENDS its `## Advanced Threat Audit` section to the same per-phase SECURITY.md — no separate file).
5. Merge into SECURITY.md with per-stack category tables.
6. **Orchestrator evaluation (checker tier — the "loop to evaluate the workers" leg).** YOU, on the
   orchestrator/checker tier, review the merged findings before finalizing: reject false positives,
   confirm each OPEN cites real evidence (a HOLLOW status-code-only test is itself a finding, never a
   PASS), and reconcile severity. This is maker≠checker — the auditors found; a model *above* them
   adjudicates. If `--fix` is passed, spawn `release-code-fixer { model: $WORKER_MODEL, ... }` on the
   confirmed OPEN issues, then re-run the relevant auditor (worker tier) to verify the fix closed the
   category — a worker loop until the finding is CLOSED or escalated.

## Django 9 categories (backend)
1. Cross-Tenant Isolation
2. Intra-Tenant IDOR
3. Vertical Privilege Escalation
4. Mass Assignment
5. JWT Lifecycle
6. Input Validation / Injection
7. Auth State Transitions
8. CSRF
9. Cookie / Token Security

## React 9 categories (frontend)
1. XSS Prevention
2. Auth Token Storage (httpOnly cookies only)
3. CSRF (X-CSRFToken header)
4. Client-side IDOR
5. API Key / Secret Exposure
6. Content Injection (Markdown/rich text)
7. Prototype Pollution
8. Sensitive Data Logging
9. Input Validation (Zod schemas)

## Full-stack cross-cutting checks

When both stacks present:
- Auth model consistent: Django sets httpOnly cookie + React never touches localStorage
- CSRF consistent: Django `CsrfViewMiddleware` active + React sends `X-CSRFToken` header
- Permission model consistent: Django permission classes match React route guards (defense in depth)

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-SECURITY.md
  ## Backend Security (Django)
    | Category | Status | Evidence |
  ## Frontend Security (React)
    | Category | Status | Evidence |
  ## Full-Stack Cross-Cutting
    | Check | Status |
  ## Open Issues (BLOCKER)
    ...remediation steps...
  ## Advanced Threat Audit            ← appended by release-advanced-threat-auditor (always-on)
    ### Django Advanced (A1-A13)
      | Cat | Threat | Status | Evidence |
      A1 SSRF · A2 Deserialization · A3 Command Injection · A4 SSTI/Path-Traversal ·
      A5 XXE/Header-Log Injection · A6 ORM-level Injection · A7 Concurrency/TOCTOU/idempotency ·
      A8 JWT Forgery & Auth-Identity · A9 Constant-Time/Signed-Payload · A10 Transport/Headers/CORS ·
      A11 SQLi (exploitation-grade) · A12 Image/Media DoS+RCE · A13 AWS Cloud-Infra
    ### React Advanced (RA1-RA5)
      | Cat | Threat | Status | Evidence |
      RA1 URL-scheme/DOM sinks · RA2 postMessage/client-SSRF · RA3 CSP/Trusted-Types ·
      RA4 Build/supply-chain · RA5 SSR/hydration/DOM-clobbering/JSON-hijacking
    ### Advanced Open Issues (BLOCKER)
      ...auto-OPEN triggers + remediation...
```

Evidence model in the Advanced Threat Audit section is split:
- Most categories are **[pytest]** — proven by a runtime test asserting DATA-LAYER / behavioral impact
  (sentinel row survives, row-count baseline, wall-time < 1s, zero outbound egress), cited as `file::test_name`.
  A test whose ONLY assertion is an HTTP status code (e.g. `assert r.status_code in (201, 400)`) is HOLLOW
  and is itself a finding — it accepts a STORED payload and manufactures a false PASS.
- The AWS half of **A13** (sub-cats A13.2/.4/.6/.7/.9/.10, and parts of .1/.8) is **[IaC/CSPM static]** —
  proven by a passing `check_*` static gate over `terraform/*.tf`, `serverless.yml`, `cdk/`, policy JSON,
  `settings.py`, `.env` (tfsec/checkov/conftest/CI grep), NOT a pytest. Evidence is cited as the `check_*` name.

## Example

```
/release:security 01

→ Scope: FULLSTACK
→ Django files: 3 (.py)
→ React files: 4 (.tsx/.ts)

→ Backend audit (release-security-auditor)...
  Cat 1 (Cross-Tenant): CLOSED — TenantModel used, empresa filter in get_queryset
  Cat 4 (Mass Assignment): OPEN — InvoiceSerializer uses fields = '__all__'
  ...

→ Frontend audit (release-security-auditor)...
  Cat 2 (Auth Token): CLOSED — no localStorage usage found
  Cat 3 (CSRF): PARTIAL — X-CSRFToken header set, but missing in multipart form requests
  ...

→ Cross-cutting:
  Auth model: CONSISTENT ✓ (httpOnly cookie Django ↔ credentials:include React)
  CSRF: PARTIAL — see Cat 3 above

→ Advanced threat audit (release-advanced-threat-auditor, always-on)...
  Cat A1 (SSRF): OPEN — requests.get(user_url) at services/preview.py:34 with no link-local denylist
  Cat A7 (TOCTOU): OPEN — coupon.is_valid()→coupon.redeem() outside select_for_update/atomic; no race test
  Cat A11 (SQLi): OPEN — ?ordering reaches .order_by() with no allowlist; only test asserts status (HOLLOW)
  Cat A13.1 (IMDS): OPEN [IaC] — launch template http_tokens not "required" (check_imds_v2_required FAIL)
  Cat A13.2 (S3 public): OPEN [IaC] — bucket policy Principal:"*" unconditioned (check_no_wildcard_principal FAIL)
  Cat RA1 (URL-scheme): PARTIAL — href={userUrl} has no scheme allowlist; test_dynamic_href_rejects_javascript_scheme missing

→ SECURITY.md written
   Backend: 1 OPEN, 1 PARTIAL, 7 CLOSED
   Frontend: 0 OPEN, 1 PARTIAL, 8 CLOSED
   Advanced: 5 OPEN (3 [pytest], 2 [IaC static]), 1 PARTIAL — see ## Advanced Threat Audit
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.

In addition to the stack-dispatched `release-security-auditor`, this skill ALWAYS spawns `release-advanced-threat-auditor` over the same scope (it is unconditional — never gated on a detected trigger surface) and runs it in parallel. It applies the matching stack's advanced catalog (Django A1-A13 / React RA1-RA5) and appends its `## Advanced Threat Audit` section to the same SECURITY.md.
