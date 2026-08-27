---
name: django-expert
description: Opt-in Django/DRF specialist for difficult framework decisions, audits, and implementation details. Do not auto-activate when another release workflow already owns a routine Django task.
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

# Django expert

Use this skill when the user explicitly asks for Django expertise or a task has a genuinely Django-specific uncertainty. In `spec`, `plan`, `execute`, `quick`, or `loop`, keep routine framework work inside that workflow; load this skill only for a narrow specialist question.

## Default rules

- Scope every tenant-owned queryset at its source. Authentication is not object authorization.
- Give every DRF endpoint explicit permissions and every serializer an explicit field list. Treat writable role, ownership, billing, and audit fields as privileged.
- Validate at the boundary; keep domain invariants in a service/model layer that all entry points share.
- Use `select_related` for single-valued relations and `prefetch_related` for collections. Prove query-sensitive changes with query-count tests when material.
- Wrap multi-write invariants in `transaction.atomic`; use locking or database constraints when concurrent requests can violate them. Schedule external effects with `transaction.on_commit`.
- Make migrations deploy-safe: additions before constraints/removals, bounded backfills, reversible operations where practical, and no large table rewrite without an explicit rollout.
- Preserve Django security defaults. Never weaken CSRF, host validation, cookie flags, or CORS to hide a configuration error.
- Run the smallest relevant test set first, then the repository gate. Do not invent a parallel workflow or duplicate an existing review.

## Read only what the task needs

- Authentication, permissions, JWT, object access: `references/auth_patterns.md`
- Input/output exposure and security configuration: `references/security.md`
- ORM, caching, N+1, query budgets: `references/performance.md`
- pytest, factories, API and query tests: `references/testing.md`
- settings, Gunicorn, static files, observability: `references/deployment.md`

## Output

Lead with the concrete decision or patch. For review work, report only actionable findings with severity and exact `file:line`; for implementation, state the invariant protected and verification run. Stop when the requested Django uncertainty is resolved.
