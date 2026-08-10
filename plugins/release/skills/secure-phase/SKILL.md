---
name: secure-phase
description: >
  Retroactive (post-implementation) security audit. Reads the phase PLAN.md threat model and
  the author-time 9-category checklist, then greps shipped source/diff for evidence that
  every declared threat is actually mitigated. Routes .py files to django-security-retro
  and .tsx/.ts files to react-security-retro. Produces SECURITY.md scorecard.
  Use when: phase shipped, before merge to main, periodic post-merge verification, audit recovery.
  Distinct from /release:security (author-time, runs during planning/execution).
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

# /release:secure-phase — Retroactive Threat Mitigation Audit

Runs AFTER a phase is implemented and committed. Verifies that every threat declared
in the phase PLAN.md `threat_model` block has a corresponding mitigation grep-provable
in the shipped code. Distinct from `/release:security` which is author-time guidance.

## Difference vs /release:security

| Axis | `/release:security` (author-time) | `/release:secure-phase` (retroactive) |
|---|---|---|
| When | During planning/execution | After phase ships |
| Input | Code currently being written | Frozen commits + PLAN.md threat model |
| Tone | Recommends mitigations | Verifies mitigations exist |
| Output | Inline guidance / SECURITY.md (open issues) | SECURITY.md scorecard (PASS/BLOCK/FLAG) |
| Modifies code | No (advisory) | No (read-only audit) |
| Agents | release-security-auditor / release-security-auditor | release-django-security-retro / release-react-security-retro |

## Usage

```
/release:secure-phase 01                         # audit phase 01 against its declared threat model
/release:secure-phase 01 --backend               # Django retro audit only
/release:secure-phase 01 --frontend              # React retro audit only
/release:secure-phase 01 --diff main..HEAD       # constrain evidence search to shipped diff
/release:secure-phase 01 --strict                # MISSING anywhere → BLOCK verdict
```

## Detection / Scope Resolution

1. Locate `.release-planning/phases/{NN}-{slug}/{NN}-PLAN.md`.
2. Parse `threat_model:` block from frontmatter (list of T-XX entries with category + plan).
3. Parse `{NN}-SUMMARY.md` for `stack:` field → `django`, `react-tsx`, or both.
4. Resolve files in scope:
   - Default: union of files touched in phase commits (`git log --name-only` between phase start and HEAD).
   - `--diff REV..REV`: explicit diff range.
5. Split by extension: `.py` → django retro agent, `.tsx/.ts` → react retro agent.
6. Run in parallel when both stacks present.

## Retroactive verification model

For each threat T-XX from PLAN.md frontmatter:

1. **Look up mitigation grep pattern** for its category (9-category matrix from `/release:security`).
2. **Run grep against shipped source** (scoped to files in step 4 above).
3. **Classify status:**
   - `MITIGATED` — grep matches evidence in shipped code AND (if applicable) test asserts attack blocked.
   - `PARTIAL` — code mitigation present but test missing OR test exists but weak/narrow.
   - `MISSING` — no code evidence (treated as BLOCKER for verdict).
   - `N/A` — category not applicable to this phase (e.g., no file upload → no MIME check).
4. **Record evidence** as `file:line` (mitigation) and `test_file::test_name` (test).
5. **Remediation block** populated only for MISSING / PARTIAL.

## Author-time checklist re-verification

If `<NN>-SECURITY.md` from author-time `/release:security` exists, cross-check:
- Categories marked CLOSED at author-time should still grep-prove MITIGATED at retro-time.
- Drift detection: anything that flipped CLOSED → MISSING is logged under "Regression" in scorecard.

## Django 9-category retro greps (backend)

| # | Category | Retro grep |
|---|----------|------------|
| 1 | Cross-Tenant Isolation | `TenantModel` inheritance, `get_queryset.*filter\(empresa=` |
| 2 | Intra-Tenant IDOR | `get_object_or_404.*owner=request.user`, ownership permission classes |
| 3 | Vertical Privilege Escalation | `permission_classes.*IsAdminUser`, `is_staff` guards |
| 4 | Mass Assignment | absence of `fields = '__all__'`, presence of `read_only_fields` |
| 5 | JWT Lifecycle | `BLACKLIST_AFTER_ROTATION`, `ROTATE_REFRESH_TOKENS`, blacklist on logout |
| 6 | Input Validation / Injection | absence of `.raw(.*f"`, `.extra(where=`, validators on serializer fields |
| 7 | Auth State Transitions | single-use reset tokens, `AnonRateThrottle` on login |
| 8 | CSRF | `CsrfViewMiddleware`, no `@csrf_exempt` on session-auth views, `ALLOWED_HOSTS` set |
| 9 | Cookie / Token Security | `HttpOnly` + `Secure` + `SameSite`, `SESSION_COOKIE_SECURE`, CORS allowlist (no `CORS_ALLOW_ALL_ORIGINS = True`) |

Plus N+1 spot-check (perf-as-security signal): grep for `select_related` / `prefetch_related` on listed querysets.

## React 9-category retro greps (frontend)

| # | Category | Retro grep |
|---|----------|------------|
| 1 | XSS Prevention | no raw `dangerouslySetInnerHTML`, no `.innerHTML =`, `DOMPurify`/`rehype-sanitize` present where needed |
| 2 | Auth Token Storage | no `localStorage\.setItem.*token`, no `sessionStorage\.setItem.*token` |
| 3 | CSRF Plumbing | `X-CSRFToken` header set in API client, `credentials: 'include'` / `withCredentials: true` |
| 4 | Client-side IDOR | no `?user_id=` from URL parsed and passed to API, auth via session cookie |
| 5 | API Key / Secret Exposure | no `VITE_.*SECRET`, no hardcoded keys (>= 16 char base64-ish in source) |
| 6 | Content Injection | sanitizer applied before any Markdown/HTML render |
| 7 | Open Redirects / eval | no `eval(`, no `new Function(`, no `location.href = userInput` |
| 8 | Sensitive Data Logging | no `console.log(user)`, no `console.log(response)` containing tokens |
| 9 | Input Validation (Zod) | Zod schemas on every form + API response, content sniffing flags reviewed |

Plus dependency CVE flag: pull `npm audit --json` summary if available (informational, not BLOCKER).

## Full-stack cross-cutting retro checks

When both stacks shipped:
- Auth model coherence: Django sets `HttpOnly` cookie AND React never reads tokens.
- CSRF coherence: Django middleware enabled AND React sends `X-CSRFToken`.
- Permission depth: Django permission class for endpoint X corresponds to a React route guard.
- Drift: anything that changed status between author-time SECURITY.md and retro SECURITY.md.

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-SECURITY.md
```

Scorecard table format (see `templates/SECURITY.md`):
- One row per declared threat T-XX (and one per untracked category audited).
- Columns: Category | Threat | Status | Evidence (file:line) | Remediation.
- Overall Verdict: `PASS` (all MITIGATED or N/A), `FLAG` (any PARTIAL, no MISSING), `BLOCK` (any MISSING).
- Action Items: concrete fixes for every non-MITIGATED row.

## Routing

- `.py` in scope → spawn `release-django-security-retro` agent.
- `.tsx`/`.ts` in scope → spawn `release-react-security-retro` agent.
- Merge agent outputs into single SECURITY.md with per-stack sections + cross-cutting block.

## Constraints

- Read-only: never edits source, migrations, settings, tests, or commits.
- Evidence must be `file:line`. No claims without grep proof.
- Status values restricted to: `MITIGATED`, `PARTIAL`, `MISSING`, `N/A`.
- Never auto-commits SECURITY.md (left as working-tree artifact for review).

## Example

```
/release:secure-phase 01

→ Phase: 01-invoices-crud
→ Stack: FULLSTACK (django + react-tsx)
→ Threat model: 9 declared threats (T-01 .. T-09)
→ Scope: 7 files (3 .py, 4 .tsx) from a1b2c3..HEAD

→ Backend retro audit (release-django-security-retro)...
  T-01 (cross_tenant): MITIGATED — backend/apps/financeiro/views.py:42 (filter empresa=...)
  T-04 (mass_assignment): MISSING — fields = '__all__' at backend/apps/financeiro/serializers.py:18

→ Frontend retro audit (release-react-security-retro)...
  T-08 (token_storage): MITIGATED — no localStorage.setItem token found
  T-03 (csrf): PARTIAL — X-CSRFToken sent on JSON but absent on multipart at src/api/upload.ts:24

→ Cross-cutting:
  Auth coherence: CONSISTENT
  Drift: T-04 was CLOSED at author-time SECURITY.md → MISSING now (regression)

→ SECURITY.md written
   Verdict: BLOCK (1 MISSING, 1 PARTIAL, 1 REGRESSION)
   Action items: 2
```


---

## Stack dispatch

This skill spawns merged `release-*` agents. Stack is inferred from `.release-planning/PROJECT.md` `stack:` field (`django` | `react` | `fullstack`). For fullstack phases, per-phase stack is read from the phase frontmatter. Agents apply matching stack-specific rules.
