---
description: >
  Cross-AI plan convergence loop. Requests peer review of {NN}-PLAN.md from external AI CLIs
  (codex, gemini) and replans with the feedback until no HIGH concerns remain (or max iterations).
  Each iteration commits separately. Conservative convergence: HIGH=0 AND MED<=2.
  Use when: a phase plan is high-stakes and you want a multi-AI critique loop before execution.
allowed_tools: Agent, Read, Write, Bash, Grep, Glob
---

# /release:plan-review-convergence — Cross-AI Plan Convergence Loop

Iteratively hardens `{NN}-PLAN.md` by asking external AI CLIs (codex, gemini) for adversarial review, then re-spawning `release-feature-planner` with the aggregated concerns until convergence.

## Usage

```
/release:plan-review-convergence 01                            # default reviewers: codex + gemini, max-iters 5
/release:plan-review-convergence 01 --reviewers codex,gemini   # explicit reviewer list
/release:plan-review-convergence 01 --reviewers codex          # single reviewer
/release:plan-review-convergence 01 --max-iters 3              # cap iterations (default 5)
```

## Pre-checks

Run before entering the loop. Abort with a clear message if any fails:

1. `.release-planning/` directory exists at repo root.
2. Phase `NN` directory resolves to `.release-planning/phases/{NN}-{slug}/` and contains `{NN}-PLAN.md` at stage `planned` (frontmatter `stage:` field or default if absent).
3. At least one of `codex` / `gemini` CLIs is installed on PATH (`command -v codex`, `command -v gemini`).
   - If neither installed: report exact install hints (`npm i -g @openai/codex` / `npm i -g @google/gemini-cli` — names illustrative; use whatever the user has documented) and exit.
4. Required API key env vars present for each requested reviewer:
   - `codex` → `OPENAI_API_KEY` (or `CODEX_API_KEY` if user uses that)
   - `gemini` → `GEMINI_API_KEY` (or `GOOGLE_API_KEY`)
   - Missing key → drop that reviewer from this run with a warning, do not abort.
5. If `--reviewers` lists a CLI not installed → warn and continue with the remaining installed reviewers. Abort only if zero usable reviewers remain.

## Execution loop

State variables held across iterations:
- `iter` (starts at 1)
- `max_iters` (from flag, default 5)
- `phase_dir` = `.release-planning/phases/{NN}-{slug}/`
- `plan_path` = `${phase_dir}/{NN}-PLAN.md`
- `log_path` = `${phase_dir}/{NN}-CONVERGENCE-LOG.md`

### Step 1 — Read current plan

Read `${plan_path}` (full content). Capture pre-iteration SHA via `git rev-parse HEAD` for the iteration log.

### Step 2 — Invoke configured reviewer CLIs (Bash)

For each reviewer in the active list, run in parallel-friendly Bash calls:

```bash
# codex
cat "${plan_path}" | codex "Review this release-sdk phase plan as an adversarial senior engineer. \
List concerns tagged HIGH / MEDIUM / LOW (one per line). Be terse — bullet form only. \
Focus: missing tests, security gaps, ambiguous tasks, untestable acceptance criteria, \
contract mismatches, RC1-RC7 / Q1-Q7 coverage." \
  > "${phase_dir}/.review-codex-iter${iter}.txt" 2>&1 || echo "codex failed"

# gemini
cat "${plan_path}" | gemini "Review this release-sdk phase plan as an adversarial senior engineer. \
List concerns tagged HIGH / MEDIUM / LOW (one per line). Be terse — bullet form only. \
Focus: missing tests, security gaps, ambiguous tasks, untestable acceptance criteria, \
contract mismatches, RC1-RC7 / Q1-Q7 coverage." \
  > "${phase_dir}/.review-gemini-iter${iter}.txt" 2>&1 || echo "gemini failed"
```

If a CLI invocation fails (non-zero exit) → log as `[REVIEWER ERROR]` in the iteration log and continue with whatever responses we got. Do not abort the loop on a single CLI failure.

### Step 3 — Parse concerns per reviewer

For each reviewer transcript, extract bullets. Tag severity from each line's leading marker (`HIGH`, `MED` / `MEDIUM`, `LOW`). Normalize to `HIGH` / `MED` / `LOW`. Anything unrecognized → bucket as `LOW`.

### Step 4 — Aggregate + dedupe

Merge all reviewer concerns into one list. Dedupe by semantic overlap (heuristic: lowercase + strip punctuation; substrings of >=70% Jaccard token similarity collapse into one entry with `sources: [codex, gemini]`). When two reviewers disagree on severity, keep the higher severity.

Produce counts: `high_count`, `med_count`, `low_count`.

### Step 5 — Convergence check

```
if high_count == 0 and med_count <= 2:
    verdict = CONVERGED
elif iter >= max_iters:
    verdict = STUCK
else:
    verdict = CONTINUE
```

### Step 6 — On CONVERGED

- Append final entry to `${log_path}` with verdict `CONVERGED`.
- Print summary (totals, iterations consumed, reviewers used).
- Exit loop. Do not spawn the planner again.

### Step 7 — On CONTINUE

Spawn `release-feature-planner` agent with these inputs:
- Current `{NN}-PLAN.md` (full)
- Aggregated concerns (HIGH first, MED second; LOW listed but explicitly marked optional)
- Explicit directive: "Revise the PLAN in-place. Address every HIGH concern. Resolve MED concerns where they do not conflict with project LOCKs. Acknowledge LOW concerns inline as comments if not addressed."

The planner overwrites `${plan_path}` with the revised version.

### Step 8 — Diff + commit

```bash
git add "${plan_path}" "${log_path}"
git commit -m "plan({NN}): iter ${iter} convergence — addressed ${high_count} HIGH, ${med_count} MED"
```

Capture commit SHA into the iteration log entry. Each iteration = one revert-able commit.

### Step 9 — Loop or stop

- Increment `iter`. If `iter > max_iters` and verdict was `CONTINUE` → mark as `STUCK` and emit `CONVERGENCE-STUCK.md`.
- Otherwise → return to Step 1.

### Step 10 — On STUCK

Write `${phase_dir}/CONVERGENCE-STUCK.md` containing:
- Final iteration's concern list (HIGH + MED only)
- Per-iteration HIGH count trend (to show if loop was making progress or oscillating)
- Recommended human intervention points (specific lines / tasks in PLAN.md)
- Suggested next move: manually edit PLAN.md, then re-run `/release:plan-review-convergence {NN}` or accept residual risk and proceed to `/release:execute {NN}`.

## Convergence log format

`${phase_dir}/{NN}-CONVERGENCE-LOG.md` is appended once per iteration:

```markdown
## Iter {N} — {YYYY-MM-DD HH:MM} — verdict: {CONVERGED|CONTINUE|STUCK}

**Pre-iter SHA:** abc1234
**Post-iter SHA:** def5678 (commit: "plan({NN}): iter {N} convergence — ...")
**Reviewers:** codex, gemini  (dropped: <list, if any>)

### Concerns (deduped)
- HIGH ({count})
  - [codex,gemini] {concern text}
  - [gemini] {concern text}
- MED ({count})
  - [codex] {concern text}
- LOW ({count})
  - ...

### Planner response
- Addressed: {N} HIGH, {M} MED
- Deferred (LOW or out-of-scope): {K}
- Summary of changes: {1-3 lines describing PLAN.md diffs}
```

## Output artifacts

```
.release-planning/phases/{NN}-{slug}/
  {NN}-PLAN.md                    # updated in-place each iteration
  {NN}-CONVERGENCE-LOG.md         # appended each iteration
  CONVERGENCE-STUCK.md            # only if max_iters hit with HIGH > 0
  .review-codex-iter{N}.txt       # raw reviewer transcripts (kept for audit)
  .review-gemini-iter{N}.txt
```

Raw `.review-*.txt` files are gitignored-by-convention (leading dot, hidden) — keep them locally for audit but don't pollute commits. If they accidentally land in `git status`, the loop's `git add` only targets `{NN}-PLAN.md` and the convergence log, so they remain untracked.

## Example

```
/release:plan-review-convergence 04 --reviewers codex,gemini --max-iters 3

→ Pre-checks: codex installed, gemini installed, both API keys present, PLAN.md found
→ Iter 1
   codex:  4 HIGH, 3 MED, 2 LOW
   gemini: 3 HIGH, 5 MED, 1 LOW
   Aggregated (dedup): 5 HIGH, 6 MED, 3 LOW
   Verdict: CONTINUE
   Spawning release-feature-planner with 5 HIGH + 6 MED concerns...
   commit a1b2c3d: plan(04): iter 1 convergence — addressed 5 HIGH, 6 MED

→ Iter 2
   codex:  1 HIGH, 2 MED, 0 LOW
   gemini: 0 HIGH, 3 MED, 1 LOW
   Aggregated: 1 HIGH, 4 MED, 1 LOW
   Verdict: CONTINUE
   commit e4f5g6h: plan(04): iter 2 convergence — addressed 1 HIGH, 4 MED

→ Iter 3
   codex:  0 HIGH, 1 MED, 2 LOW
   gemini: 0 HIGH, 2 MED, 0 LOW
   Aggregated: 0 HIGH, 2 MED, 2 LOW
   Verdict: CONVERGED  (HIGH=0 AND MED<=2)
   No replan needed.

→ Done. 3 iterations. Final PLAN.md at .release-planning/phases/04-invoice-export/04-PLAN.md
→ Next: /release:execute 04
```

## Constraints

- Only invokes external CLIs the user has installed; never assumes a reviewer is available.
- Each iteration commits separately so any iteration can be reverted with a single `git revert`.
- Never invokes external CLIs without the required API key env var present — silently drop that reviewer for the run.
- If `--reviewers` includes a CLI not installed → warn and continue with available reviewers; abort only if zero remain.
- Convergence definition is conservative: HIGH=0 AND MED<=2. Do not chase perfection — LOW concerns are informational only.
- Never edits `.planning/` (legacy GSD dir). Operates exclusively under `.release-planning/`.
- Never silently overwrites PLAN.md without committing the prior version first.
- Reviewer prompts are terse-by-design — they should not consume more than ~2k tokens of CLI cost per iteration per reviewer.

---

## Stack dispatch

This skill is stack-agnostic. It reviews PLAN.md as plain text regardless of `stack:` (django, react, fullstack). For fullstack phases with split `{NN}-PLAN-BACKEND.md` + `{NN}-PLAN-FRONTEND.md`, run the convergence loop separately per plan file (pass the specific filename via the `NN` arg's resolved phase dir — the skill picks `{NN}-PLAN.md` by default; for split plans, the user should run twice with appropriate file resolution or invoke per-stack manually).
