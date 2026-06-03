---
name: auto
description: >
  Freeform-intent router for release-sdk. Reads the user's prompt + `.release-planning/`
  state and dispatches to the right `/release:*` skill (or proposes inline execution for
  trivial work). Always prints the chosen route + a 1-line reason before invoking, so the
  user can abort. Falls back to `AskUserQuestion` when classification confidence is low.
  Use when: the user describes an intent without specifying a command, or invokes
  `/release:auto <freeform prompt>`.
---

## Agent Policy (LOCKED — applies to all routed skills)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. This applies to every skill this router dispatches to.

**Substitution map** (`gsd-<x>` → `release-<x>`):
- `gsd-debugger` → `release-debugger`
- `gsd-planner` → `release-planner`
- `gsd-executor` → `release-executor`
- `gsd-code-reviewer` → `release-code-reviewer`
- `gsd-verifier` → `release-verifier`
- `gsd-phase-researcher` → `release-phase-researcher`
- `gsd-pattern-mapper` → `release-pattern-mapper`
- `gsd-plan-checker` → `release-plan-checker`
- `gsd-ui-researcher` → `react-ui-researcher`
- `gsd-ui-checker` → `react-ui-checker`
- `gsd-ui-auditor` → `react-ui-auditor`
- `gsd-code-fixer` → `release-code-fixer`
- `gsd-security-auditor` → `release-security-auditor`
- `gsd-doc-writer` → `release-doc-writer`
- `gsd-roadmapper` → `release-roadmapper`
- (general rule) `gsd-<name>` → `release-<name>`

Substituting `gsd-*` bypasses release-sdk hooks/audit/stack-dispatch and corrupts plugin isolation. If the matching `release-*` agent is missing, abort and surface the gap — do **not** fall back.

---

# /release:auto — Intent Router

One entry point. User describes what they want; this skill picks the right
`/release:*` command, shows reasoning, dispatches.

## Usage

```
/release:auto fix the bug where invoice export crashes on PDFs >10MB
/release:auto add a new endpoint to list archived projects
/release:auto where am I
/release:auto tela de configurações de empresa
/release:auto import this GSD repo
```

The arg is freeform — no syntax, no flags. Empty arg = same as `/release:status`.

---

## Execution flow

### Step 1 — State scan (always, parallel)

Run these reads in parallel (Bash + Read). Skip gracefully if a path is missing:

| Probe | Purpose |
|---|---|
| `test -d .release-planning && ls .release-planning/` | release-sdk initialized? |
| `test -d .planning && ls .planning/` | GSD source present? (import signal) |
| Read `.release-planning/STATE.md` (first 60 lines) | active phase, stage, cursor |
| `git status --short \| head -20` | uncommitted work? |
| `git log --oneline -3` | recent activity |

Record:
- `release_initialized` (bool)
- `gsd_present` (bool)
- `active_phase` (NN or null)
- `active_stage` (string or null) — one of: `spec`, `discussed`, `planned`, `executing`, `verified`, `shipped`
- `dirty_worktree` (bool)

### Step 2 — Classify intent

Apply rules in order. First match wins. Cite the rule that fired in the dispatch line.

| # | Signal in prompt | State condition | Route |
|---|---|---|---|
| 1 | "import GSD", "port .planning", "switch from GSD" | `gsd_present == true` AND `release_initialized == false` | `/release:import` |
| 2 | empty arg OR "where am I", "status", "what's next", "onde estou", "próximo" | — | `/release:status` |
| 3 | "new project", "bootstrap", "init", "comecei do zero" | `release_initialized == false` | `/release:init` |
| 4 | "ship", "merge", "PR", "publica", "abre PR" | `active_stage == verified` | `/release:ship` |
| 5 | "bug", "broken", "fails", "investigate", "stack trace", "crash", "quebra", "falha", contains pasted error/traceback | — | `/release:debug` |
| 6 | "tela", "screen", "modal", "página", "component", "UI design" | — | `/release:ui-phase` |
| 7 | "LLM", "GPT", "prompt", "embedding", "Claude", "Anthropic", "OpenAI", "RAG" | — | `/release:ai-phase` |
| 8 | "security", "vulnerab", "audit", "OWASP", "auth bypass", "threat" | `active_stage in {executing, verified, shipped}` | `/release:secure-phase` |
| 9 | "security", "vulnerab" — without a shipped/verified phase | — | `/release:security` |
| 9a | advanced threat surface: "race condition", "TOCTOU", "SSRF", "deserialization", "pickle", "command injection", "SSTI", "XXE", "JWT forgery", "alg confusion", "SQL injection", "image bomb", "decompression bomb", "pixel flood", "ImageTragick", "zip slip", "AWS", "S3", "IAM", "IMDS", "169.254", "presigned URL", "cloud security", "subdomain takeover" | — | `/release:security` — advanced threat surface → full security audit (incl. release-advanced-threat-auditor A1-A13 / RA1-RA5) |
| 10 | "review", "code review", "diff review" | `active_stage in {executing, verified}` | `/release:review` |
| 11 | "test gap", "missing tests", "UAT failed", "add tests" | `active_phase != null` | `/release:verify` |
| 12 | "verify", "UAT", "did it work", "validar" | `active_phase != null` | `/release:verify-work` |
| 13 | "parallel", "session", "paralelo", "domínio", "worktree", "branch off", "sessões simultâneas" | — | `/release:session` |
| 14 | "checklist", "RC1", "RC7", "Q1", "Q7" | — | `/release:checklist` |
| 15 | "execute", "run plan", "roda fase", "termina" | `active_stage == planned` | `/release:execute` |
| 16 | "plan", "break into tasks", "task list", "RC1-RC7" | `active_stage == discussed` | `/release:plan` |
| 17 | "discuss", "explore tradeoffs", "open questions" | `active_stage == spec` | `/release:discuss` |
| 18 | "new feature", "design", "spec", "como modelar", "what should X do" | — | `/release:spec` |
| 19 | bounded multi-file change (3-10 files, no new design): "add field X to model + migration + serializer", "swap library X for Y in {dirs}", "wire CSRF passthrough" | — | `/release:quick` |
| 20 | trivial single-file edit: "rename X to Y", "add log line", "fix typo", "tweak comment", "change variable", "remove unused import" — single-file feel, <30 LOC | — | `/release:fast` |
| 21 | "run all remaining phases", "executa tudo", "termina o milestone", "walk away and finish" | `active_stage in {verified, shipped}` and ROADMAP has more phases | `/release:autonomous` |
| 22 | "analyze repo", "map codebase", "scan stack", "what's in this repo" | — | `/release:map-codebase` |
| 23 | "add test", "regression test for", "coverage for", "test gap fill" — additive testing on existing code | — | `/release:add-tests` |
| 24 | "nyquist", "coverage audit", "validate coverage", "≥2 tests per req" | `active_phase != null` | `/release:validate-phase` |
| 25 | "peer review plan", "cross-AI plan", "convergence", "have codex/gemini review the plan" | `active_stage == planned` | `/release:plan-review-convergence` |
| 26 | "audit UI", "review UI debt", "UI quality scorecard", "6-pillar UI" | `active_phase != null` AND phase has UI | `/release:ui-review` |
| 27 | "audit eval", "AI eval coverage", "eval-review", "are the rubrics covered" | `active_phase != null` AND phase has AI | `/release:eval-review` |
| 28 | "post-mortem", "what went wrong", "diagnose the failure", "forensics" | something in STATE history shows failure | `/release:forensics` |
| 29 | "burn down debt", "fix all issues", "audit-to-fix loop", "clean up the auditor findings" | `active_stage in {verified, shipped}` | `/release:audit-fix` |
| 30 | "UAT status", "outstanding UATs", "cross-phase UAT", "which UATs still pending" | — | `/release:audit-uat` |
| 31 | "update README", "regenerate docs", "refresh ARCHITECTURE.md", "docs out of date" | — | `/release:docs-update` |
| 32 | "pause", "save state", "context handoff", "stopping for the day", "before /clear", "wrap for now" | — | `/release:pause-work` |
| 33 | "resume", "pick up where I left off", "continue from yesterday", "restore session", session-id pattern `YYYY-MM-DD-HHhMM` | `.release-planning/sessions/` exists with ≥1 dir | `/release:resume-work` |
| 34 | "undo", "rollback", "revert", "desfaz fase", "revert plan", "rollback phase" | `dirty_worktree == false` | `/release:undo` |
| 35 | "MVP", "vertical slice", "thin slice", "user story", "SPIDR", "narrow scope", "smallest viable" | `active_phase != null` AND phase status is `not-started` | `/release:mvp-phase` |
| 36 | "new milestone", "next version", "start v1.1", "start v2.0", "começar próximo release", "kick off milestone" | current milestone has 0 phases in `executing`/`planned` | `/release:new-milestone` |
| 37 | "complete milestone", "close milestone", "finish v1.0", "fechar milestone", "ship milestone" | all phases in current milestone at stage `shipped` | `/release:complete-milestone` |
| 38 | "milestone health", "audit milestone", "milestone status", "REQ coverage", "is the milestone ready" | current milestone has ≥1 phase | `/release:audit-milestone` |
| 39 | anything else | — | `<ambiguous>` (Step 3 fallback) |

### Step 3 — Confidence + fallback

After Step 2 picks a route, score confidence:

- **HIGH**: at least 2 signals from rule body matched (e.g., both keyword AND state condition) → dispatch directly.
- **MED**: single keyword match with no state condition → dispatch but print a softer reason ("matched keyword X; if wrong, abort and re-run with explicit command").
- **LOW** OR route == `<ambiguous>`: do NOT dispatch. Use `AskUserQuestion` with the top 2 candidate routes + an "Other (type command)" escape:

```
Question: "Intent unclear. Which /release:* command?"
Options:
  - "/release:spec — define a new feature"  (description: "...")
  - "/release:status — show current state"  (description: "...")
  - "Other — let me type the command"       (description: "...")
```

User pick → dispatch. "Other" → exit cleanly with the candidate list printed.

### Step 4 — Dispatch protocol

Before invoking the chosen skill, print ONE line:

```
→ /release:auto routing to {chosen_skill} — reason: {rule N, "signal: ...", state: "..."}
```

Then invoke via the `Skill` tool with the chosen skill name and the original freeform arg
as `args`. Do NOT modify the user prompt. Do NOT inject extra context. The downstream skill
reads `.release-planning/STATE.md` on its own.

(Inline execution is no longer a route in this skill — rule 19 dispatches to `/release:quick`
and rule 20 dispatches to `/release:fast`, both of which own their own inline / agent flow.
`/release:auto` itself never does the work directly.)

---

## Constraints

- **One dispatch per invocation.** Never call two `Skill` tools in a row. If the chosen
  skill needs follow-up, the user re-invokes `/release:auto` after it finishes.
- **Never auto-commit on routing.** The chosen skill owns its own commits — including
  `/release:fast` and `/release:quick`. `/release:auto` itself never touches the worktree.
- **Never modify `.release-planning/STATE.md` directly.** State transitions belong to the
  dispatched skill.
- **Never write to `.planning/`.** That's GSD-owned (see `release-import-orchestrator`).
- **Print the route before dispatch.** No silent routing — the user must always see the
  decision and have time to abort.
- **Fall back loudly.** LOW confidence → `AskUserQuestion`, never a silent guess.
- **No infinite loops.** If the chosen skill itself ends up re-invoking `/release:auto`,
  abort with: `"Route loop detected: {chosen_skill} → /release:auto. Exiting."`

---

## Example — HIGH confidence dispatch

```
/release:auto fix the bug where invoice export crashes on PDFs >10MB

→ State: release_initialized=true, active_phase=03-invoice-pdf-export,
         active_stage=executing, dirty_worktree=false
→ Match: rule 5 (signal: "bug" + "crashes")
→ Confidence: HIGH (keyword × 2)
→ /release:auto routing to /release:debug — reason: bug report with crash signal during active phase
[dispatches to /release:debug with the original prompt as args]
```

## Example — MED confidence dispatch

```
/release:auto add archive endpoint

→ State: release_initialized=true, active_phase=null
→ Match: rule 18 (signal: "add" + implicit "new feature")
→ Confidence: MED (single keyword; no active phase context)
→ /release:auto routing to /release:spec — reason: looks like a new feature request;
  if wrong, abort and run /release:auto with a clearer intent
[dispatches to /release:spec]
```

## Example — LOW confidence fallback

```
/release:auto check the celery thing

→ State: release_initialized=true, active_phase=02-celery-tasks, active_stage=executing
→ Match: no clear rule (could be debug, review, verify, secure-phase)
→ Confidence: LOW
→ AskUserQuestion: "Intent unclear. Which /release:* command?"
   Options:
     - "/release:review — code-review the active phase"
     - "/release:verify-work — run UAT against the phase"
     - "Other — let me type the command"
```

## Example — Import detection

```
/release:auto onde estou

→ State: release_initialized=false, gsd_present=true
→ Match: rule 1 (gsd source detected, release-sdk not initialized — bridge needed first)
→ Confidence: HIGH (state-driven)
→ /release:auto routing to /release:import — reason: GSD .planning/ present but
  .release-planning/ missing; run import before any other /release:* command
[dispatches to /release:import]
```

## Example — Trivial single-file edit

```
/release:auto rename `EmpresaSerializer.user_email` to `owner_email`

→ State: release_initialized=true, dirty_worktree=false
→ Match: rule 20 (trivial rename; single-symbol scope)
→ Confidence: HIGH
→ /release:auto routing to /release:fast — reason: single-file rename, < 30 LOC
[dispatches to /release:fast]
```

## Example — Bounded multi-file change

```
/release:auto add `archived_at` to Invoice model + migration + serializer + admin

→ State: release_initialized=true, active_phase=03-invoice-pdf-export, active_stage=executing
→ Match: rule 19 (bounded scope: 4 files, no new design)
→ Confidence: HIGH
→ /release:auto routing to /release:quick — reason: multi-file (4) but bounded; no SPEC needed
[dispatches to /release:quick]
```

---

## Notes

- This skill is meta: it does NOT itself plan, execute, or modify project state. It only
  routes. All real work happens in the dispatched skill.
- For users who prefer explicit commands: `/release:auto` is opt-in; nothing else in
  release-sdk depends on it.
- GSD analog: this mirrors `gsd-progress` ("unified situational command"). release-sdk
  now ships native equivalents for the high-traffic verbs (`/release:debug`,
  `/release:quick`, `/release:fast`, `/release:ship`, `/release:autonomous`,
  `/release:map-codebase`, `/release:add-tests`, `/release:validate-phase`,
  `/release:plan-review-convergence`, `/release:ui-review`, `/release:eval-review`,
  `/release:forensics`, `/release:audit-fix`, `/release:audit-uat`,
  `/release:docs-update`, `/release:pause-work`, `/release:resume-work`,
  `/release:undo`, `/release:mvp-phase`, `/release:new-milestone`,
  `/release:complete-milestone`, `/release:audit-milestone`) so routing stays inside the `/release:*` namespace.
  `/gsd:*` is no longer a fallback path here.
- Future work: train a tiny embeddings-based classifier from real routing logs to replace
  the heuristic table. For now, the table is good enough and auditable.
