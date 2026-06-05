---
name: ship
description: >
  Create a PR for the active phase after verification passes. Runs a final review pass
  (via `release-code-reviewer`), drafts a PR title + body grounded in the phase's
  `{NN}-SPEC.md` / `{NN}-PLAN.md` / `{NN}-UAT.md`, then opens the PR via `gh`. Updates
  `.release-planning/STATE.md` cursor to `shipped` on success. Does NOT auto-merge.
  Use when: phase is at `active_stage: verified` and you're ready to publish.
---

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation.

---

# /release:ship — Publish a Verified Phase

Final review → PR draft → `gh pr create` → cursor moves to `shipped`. No merge.

## Usage

```
/release:ship                         # ship the active phase
/release:ship 03                      # ship a specific phase (must be verified)
/release:ship --draft                 # open as draft PR
/release:ship --skip-review           # skip pre-ship review (not recommended)
```

## Pre-checks (hard gates)

1. `.release-planning/STATE.md` exists. Else: "Run `/release:init` first."
2. Target phase exists at `.release-planning/phases/{NN}-{slug}/`.
3. `active_stage` for target phase MUST be `verified`. Else abort with:
   > "Phase {NN} is at stage {stage}. Run `/release:verify-work {NN}` first."
4. Worktree clean (`git status --short` empty). Else: "Commit or stash open work."
5. Current branch is NOT `main` / `master`. Else abort with:
   > "Refusing to ship from main. Create a phase branch first."
6. `gh` CLI authenticated (`gh auth status` succeeds). Else: print login instructions.

## Execution flow

### Step 1 — Pre-ship review (skippable with `--skip-review`)

Spawn `release:release-code-reviewer` against the phase diff:

```
Agent({
  subagent_type: "release:release-code-reviewer",
  description: "Pre-ship review of phase {NN}",
  prompt: "Review diff for phase {NN}-{slug}. Scope: `git diff main...HEAD`. Focus: blockers only — bugs, security, broken contracts. Skip nits.",
  metadata: { stack, phase_path: ".release-planning/phases/{NN}-{slug}/" }
})
```

If reviewer returns any `severity: BLOCKER` findings → abort ship, write findings to
`.release-planning/phases/{NN}-{slug}/{NN}-SHIP-REVIEW.md`, exit with:
> "{N} blockers found. Fix and re-run /release:ship."

### Step 2 — Draft PR title + body

Read:
- `{NN}-SPEC.md` → goal, scope
- `{NN}-PLAN.md` → task list, decisions
- `{NN}-UAT.md` → user-facing acceptance checks (verified items only)
- `{NN}-CONTEXT.md` → D-XX decisions

Construct:

- **Title** (< 70 chars): `{type}({scope}): {goal-condensed}` where type is derived from
  the phase commits (feat / fix / refactor / chore).
- **Body**:

```markdown
## Summary
{2-3 bullets — what + why, grounded in SPEC goal}

## Decisions
{D-XX list from CONTEXT.md, one-liner each}

## Test plan
{UAT items, as a markdown checklist — pre-checked since verified}

## Phase artifacts
- `.release-planning/phases/{NN}-{slug}/{NN}-SPEC.md`
- `.release-planning/phases/{NN}-{slug}/{NN}-PLAN.md`
- `.release-planning/phases/{NN}-{slug}/{NN}-VERIFICATION.md`
- `.release-planning/phases/{NN}-{slug}/{NN}-UAT.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### Step 3 — Open PR

If `--draft` was passed, add `--draft` to the `gh` call.

```bash
git push -u origin "$(git branch --show-current)"
gh pr create \
  --title "{title}" \
  --body "$(cat /tmp/release-ship-body-{NN}.md)" \
  ${DRAFT_FLAG}
```

Capture PR URL from `gh` output.

### Step 4 — Update STATE.md

In `.release-planning/STATE.md`:
- Set `cursor.active_stage = shipped` for phase {NN}
- Append history: `{ISO timestamp} — phase {NN} shipped, PR: {url}`

Print PR URL to user.

## Constraints

- **No auto-merge.** Only opens the PR. Merge is a human decision.
- **Verified required.** Refuses to ship anything else.
- **Clean worktree.** No silent staging.
- **Review by default.** `--skip-review` is opt-out, not default.
- **One phase per invocation.** Multi-phase ship → call repeatedly.
- **No `.planning/` writes.** Only release-sdk paths.

## Example

```
/release:ship

→ Target: phase 03-invoice-pdf-export (active_stage: verified) ✓
→ Worktree clean ✓
→ Branch: feat/03-invoice-pdf-export (not main) ✓
→ gh auth ✓
→ Pre-ship review: release:release-code-reviewer…
  [no blockers]
→ Drafting PR title + body from SPEC + PLAN + UAT
→ Pushing branch + opening PR…
→ PR opened: https://github.com/acme/billing/pull/142
→ STATE.md: phase 03 → shipped
```

---

_Final gate before `git push origin main`. Reviewer-checked, SPEC-grounded, cursor-tracked._
