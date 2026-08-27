---
name: security-expert
description: Explicit, authorized interactive offensive review for a bounded web, backend, or mobile surface. Not an automatic substitute for release:security or routine code review.
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

# Security expert

Use only when the user explicitly requests an offensive/security-specialist investigation. For normal pipeline security use `release:security`; for post-implementation evidence use `release:secure-phase`. Never auto-activate solely from framework detection.

## Safety and scope

Confirm the target is code or infrastructure the user placed in scope. Prefer static evidence and safe local tests. Do not attack third parties, exfiltrate secrets, create persistence, or run destructive/availability-impacting payloads. Redact credentials and personal data.

## Method

1. Define the exposed surface, trust boundaries, attacker capability, and assets.
2. Read the smallest relevant reference:
   - web/backend/API: `references/web-backend.md`
   - React Native/Expo/device threats: `references/mobile.md`
3. Trace attacker-controlled input to authorization decisions, interpreters, storage, outbound requests, files, or privileged effects.
4. Validate plausible findings with the least invasive reproducible check. Do not manufacture PoCs when evidence is insufficient.
5. Report only actionable findings: severity, exploit preconditions, exact `file:line`, impact, evidence, and minimal remediation. Separate confirmed issues from hypotheses.

Avoid generic checklist dumps and duplicated pipeline reports. If no exploitable issue is supported, say so and name the material surfaces inspected.
