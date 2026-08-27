---
name: auto
description: >
  Cheap freeform router for release-sdk. Classifies the user's intent, reads only the state needed
  to break a tie, prints one route/reason line, and dispatches exactly one release skill.
---

## Codex runtime contract

This generated Codex skill preserves the source workflow with these overrides:

- Use current Codex tools: targeted reads, `rg`, `apply_patch`, and shell commands. Never look for
  Claude-only tool names or runtime state (`~/.claude`, `.claude*`, `CLAUDE.md`). Release artifacts
  stay in `.release-planning/`; project guidance comes from the applicable `AGENTS.md` chain.
- Before a write, a root `AGENTS.md` must exist. The hook returns `AGENTS_MD_REQUIRED`; in bootstrap
  mode only `release-agents-md-builder` may draft it, after which the user reruns the task.
- Score C0-C4 and apply risk floors before spawning. Default is no child. Spawn only when a bounded
  independent/specialist/noisy subtask avoids more context than it costs. C0/C1 stays inline; C2 uses
  at most one normal worker/planner; C3/C4 may use the strict fleet with disjoint ownership.
- Map source `release:<name>` agents to Codex `release-<name>` custom agents. Pass paths and task
  deltas, never the transcript, copied files, full logs, or `AGENTS.md` contents. Writers preserve
  concurrent work and own non-overlapping paths.
- Custom agents already pin their model/effort. Ignore Claude model names and `CLAUDE_EFFORT`; do not
  increase effort unless the C3/C4 risk actually requires it.
- A child returns compact `SubagentResultV1`; the parent decides completion. User input stays in the
  parent. Retry once at most, then narrow/stop instead of grinding.

`/release:<name>` is the source workflow label; in Codex select the corresponding release skill.

# /release:auto — lightweight intent router

`/release:auto <intent>` routes; it never implements, spawns workers, edits state or commits.
Downstream skills own complexity, models and execution. Use `release-*` agents only.

## Routing

1. If the prompt names `/release:X`, dispatch X unchanged.
2. Match the first clear intent group below. Do not scan the repository when words alone decide it.
3. Read at most the first 80 lines of `.release-planning/STATE.md` only when active phase/stage is
   needed. Check directory existence only for `init` versus `import`.
4. Print `→ /release:{skill} — {short reason}` and dispatch exactly once with the original args.
5. If two materially different routes remain plausible, ask one question with the two candidates.

| Intent | Route |
|---|---|
| empty, status, where/onde, next/próximo | `status` |
| import GSD / `.planning` exists but release is not initialized | `import` |
| init/bootstrap/new project | `init` |
| bug, crash, traceback, broken, investigate | `debug` |
| UI/screen/page/modal/component design | `ui-phase` |
| LLM/prompt/RAG/embedding/provider model | `ai-phase` |
| security/vulnerability/threat/OWASP | `secure-phase` if the phase is already built; else `security` |
| review diff/code | `review` |
| UAT/did it work/validate behavior | `verify-work` |
| missing/add tests or coverage gap | `add-tests`; use `validate-phase` only for a phase-wide audit |
| execute/run plan/finish phase | `execute`; add `--loop` only if autonomy is explicit |
| plan/break into tasks | `plan` |
| discuss/open questions/tradeoffs | `discuss` |
| explicit keep-fixing/loop on bounded goal | `loop` |
| ship/PR | `ship` |
| parallel session/worktree | `session` |
| land/merge back held work | `land` |
| docs/README | `docs-update` |
| pause/save context | `pause-work` |
| resume/continue saved session | `resume-work` |
| undo/revert/rollback | `undo` |
| run all remaining phases | `autonomous` |
| milestone start/finish/audit | `new-milestone`, `complete-milestone`, or `audit-milestone` |
| map/analyze repository | `map-codebase` |
| bounded audit-finding cleanup | `audit-fix` |
| post-mortem/what went wrong | `forensics` |

## Feature-size fallback

When no intent row matches, classify the requested change without estimating the whole repository:

- C0: obvious single-file/docs/rename/import cleanup, roughly under 30 LOC → `fast`.
- C1/C2: bounded behavior, normally up to 10 related files, no unresolved product/architecture
  choice and no risk floor → `quick`.
- C3/C4, broad feature, unknown public behavior, architecture, auth/authorization, payments,
  privacy, tenancy, destructive migration or data-loss risk → `spec`.

Confidence is HIGH when scope or two independent signals agree, MED for one clear signal, LOW when
the candidates imply different scopes. Dispatch HIGH/MED; ask only for LOW. Never run a five-command
state probe, paste state into the downstream prompt, invoke two skills, or make `execute` loop unless
the user explicitly requested autonomous correction.
