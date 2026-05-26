---
name: eval-review
description: >
  Audit an executed AI phase's evaluation coverage against its AI-SPEC.md eval plan. Spawns
  release-eval-auditor to score COVERED/PARTIAL/MISSING per dimension and produce EVAL-REVIEW.md
  with remediation plan.
  Use when: AI phase shipped but eval coverage is uncertain.
allowed_tools: Agent, Read, Write, Bash, Grep, Glob
---

# /release:eval-review — Retroactive Eval Coverage Audit

Runs AFTER an AI phase is implemented (and typically committed). Verifies that every eval
dimension declared in `{NN}-AI-SPEC.md` (or companion `{NN}-AI-EVAL.md`) has actual
implementation in the shipped code — tests exist, datasets are populated, judges are written,
guardrails are wired, monitoring fields are logged.

Distinct from `/release:ai-phase` (author-time eval planning, runs BEFORE implementation) and
distinct from `/release:verify` (truth-backward code audit, not eval-aware).

## Relationship to other release-* skills

| Skill | Mode | Question answered |
|---|---|---|
| `/release:ai-phase` | Author-time eval planning | "What evals SHOULD this AI phase have?" |
| `/release:eval-review` | Retroactive eval audit | "Was the declared eval plan actually shipped?" |
| `/release:verify` | Static truth audit | "Does code match PLAN.md truths?" |
| `/release:validate-phase` | Test sampling audit | "Is every requirement covered by ≥2 tests?" |
| `/release:secure-phase` | Retroactive threat audit | "Is every declared threat mitigated in shipped code?" |

`/release:eval-review` is the eval-domain analogue of `/release:secure-phase` — both are
retroactive contract verifiers that produce a scored audit artifact with a remediation plan.

## Usage

```
/release:eval-review {NN}                # default — full audit against AI-SPEC.md
/release:eval-review {NN} --eval-spec    # force read from {NN}-AI-EVAL.md (companion mode)
/release:eval-review {NN} --strict       # MISSING anywhere → BLOCK verdict + non-zero exit
/release:eval-review {NN} --diff main..HEAD   # constrain probes to shipped diff range
```

If `{NN}-AI-EVAL.md` exists alongside `{NN}-AI-SPEC.md`, the skill auto-routes to the EVAL file
(the planner only writes a companion when AI-SPEC is locked). `--eval-spec` forces that route.

## Pre-checks

Abort with an actionable message on failure:

1. `.release-planning/` directory exists at repo root.
2. Phase dir `.release-planning/phases/{NN}-{slug}/` exists.
3. `{NN}-AI-SPEC.md` exists in the phase dir.
   - If only `{NN}-SPEC.md` exists → abort: "Phase {NN} is not an AI phase. Use /release:verify or /release:secure-phase instead."
4. AI-SPEC.md (or companion AI-EVAL.md) has a `## Evaluation Strategy` section with declared dimensions.
   - If absent → abort: "No eval plan present. Run /release:ai-phase {NN} to design eval strategy before auditing."
5. Phase stage in `.release-planning/STATE.md` is one of: `executing`, `verified`, `shipped`.
   - Reject `discussing` / `planning` → eval implementation does not yet exist; audit would be empty.

## Execution

```
1. Resolve plan source:
     - Prefer {NN}-AI-EVAL.md if present (companion mode)
     - Otherwise {NN}-AI-SPEC.md (append mode)
     - --eval-spec flag forces AI-EVAL.md
2. Spawn release-eval-auditor with:
     phase_number: NN
     phase_dir: .release-planning/phases/{NN}-{slug}/
     ai_spec_path: absolute path to AI-SPEC.md
     ai_eval_path: absolute path to AI-EVAL.md (or null)
     audit_path: {phase_dir}/{NN}-EVAL-REVIEW.md
3. Auditor reads plan, probes implementation, scores each dim COVERED/PARTIAL/MISSING/N/A,
   audits dataset + judge prompts + guardrails + monitoring, computes overall verdict.
4. Auditor writes {phase_dir}/{NN}-EVAL-REVIEW.md (read-only on source code).
5. Skill prints summary table to stdout.
6. Skill commits the audit artifact (auditor never commits):
     chore(eval-review): retroactive audit phase {NN}
7. If --strict and any MISSING → exit non-zero (CI gating use case).
```

## Verdict semantics

Reported in EVAL-REVIEW.md frontmatter and stdout:

- `PASS` — every dim COVERED, dataset COVERED, all guardrails COVERED, monitoring COVERED.
- `PASS_WITH_GAPS` — `overall_score ≥ 80%` AND no CRITICAL-severity dim is MISSING (PII, injection, schema_validity for structured_output).
- `GAPS_FOUND` — `50% ≤ overall_score < 80%` OR ≥ 1 non-critical dim MISSING.
- `CRITICAL` — `overall_score < 50%` OR any CRITICAL-severity dim is MISSING.

In `--strict` mode, ANY MISSING (regardless of severity) elevates verdict to BLOCK and exits non-zero.

## What the auditor checks

For each declared dimension, three levels of evidence:

| Level | Check |
|---|---|
| L1 ARTIFACT | Test / dataset / judge file dedicated to this dim exists |
| L2 SUBSTANTIVE | File body matches plan (right rubric, threshold, dataset size, ≥ 20% adversarial cases) |
| L3 WIRED | Eval runs in CI on PR AND regression bar enforced (failing eval blocks merge) |

L1 + L2 + L3 → COVERED. Any two → PARTIAL. None → MISSING.
Automated-but-`automated:no` dims require a documented manual cadence for L3.
Conditional dims (e.g. `vision` when `vision: false`) → N/A.

In parallel the auditor verifies:
- **Dataset** — path exists, size ≥ `v1_minimum`, ≥ 20% adversarial tags, metadata fields, PII-scrub utility (if production-log sourced).
- **Judge prompts** — scale matches plan, step-by-step rubric, judge model pinned.
- **Guardrails** — every row from the plan's Guardrails table → file:line evidence.
- **Monitoring** — every required `AILog` field declared AND populated in view code; alerts configured; sampling re-eval job present.

## Routing

Single agent (no stack dispatch — eval audits are use-case-level, not stack-level):

- `release-eval-auditor` — read-only audit, produces EVAL-REVIEW.md.

If the AI phase shipped fullstack components (Django proxy + React consumer), the auditor still
runs once but probes both `backend/` and `frontend/` paths as the plan demands (e.g. Zod schema
for `schema_validity`, `ToolConfirmDialog` for the confirmation-gate guardrail).

## Output

```
.release-planning/phases/{NN}-{slug}/{NN}-EVAL-REVIEW.md
```

Frontmatter fields:

```yaml
audited_at: {iso}
phase: {NN}
plan_source: {NN}-AI-SPEC.md | {NN}-AI-EVAL.md
dim_count: {N}
covered_count: {N}
partial_count: {N}
missing_count: {N}
na_count: {N}
overall_score: {pct}
dataset_status: COVERED | PARTIAL | MISSING
monitoring_status: COVERED | PARTIAL | MISSING
verdict: PASS | PASS_WITH_GAPS | GAPS_FOUND | CRITICAL
```

Body sections: Dimension Coverage Matrix · Failure-mode Coverage · Dataset Audit · Judge Prompts
Audit · Guardrail Coverage · Production Monitoring Coverage · Remediation Plan · Drift vs Plan ·
Verdict & Next Steps.

## Commit

```
chore(eval-review): retroactive audit phase {NN}
```

Standalone commit — does not amend prior phase commits. Audit artifact lands on the working
tree even when verdict is CRITICAL (the artifact IS the deliverable; remediation is follow-up).

## Stdout summary

```
Eval Coverage Audit — phase {NN}
══════════════════════════════════════════════
Plan source: {NN}-AI-SPEC.md (or {NN}-AI-EVAL.md)
Output:      {NN}-EVAL-REVIEW.md

Dimensions:  {covered}/{total} COVERED ({pct}%)
             {partial} PARTIAL · {missing} MISSING · {na} N/A
Dataset:     {COVERED|PARTIAL|MISSING}
Monitoring:  {COVERED|PARTIAL|MISSING}

Verdict:     {PASS|PASS_WITH_GAPS|GAPS_FOUND|CRITICAL}

CRITICAL gaps: {n} → must fix before production rollout
PARTIAL gaps:  {n} → close before next release
MISSING:       {n} → track or accept with documented rationale

Next: {recommended action based on verdict}
```

## Example

```
/release:eval-review 04
→ Phase 04-invoice-summarize (stage=shipped, plan=04-AI-SPEC.md, append mode)
→ Spawning release-eval-auditor; probing tests/eval/, golden.jsonl, judges, AILog, workflows...
→ 8 dims: 4 COVERED, 2 PARTIAL, 2 MISSING (E-03 pii_leakage CRITICAL, E-08 tone_fit LOW)
→ Dataset: 12/20 cases, 0% adversarial → PARTIAL
→ Monitoring: AILog missing ttft_ms + eval_dim_scores; redaction_count never populated → PARTIAL
→ EVAL-REVIEW.md written; verdict CRITICAL (E-03 MISSING + adversarial threshold breach)
→ Commit: chore(eval-review): retroactive audit phase 04
Next: follow-up phase for R-01 (PII test+guardrail), R-02 (adversarial cases),
      R-03 (schema_validity merge-block). Re-run after fixes land.
```

## What this skill does NOT do

- Does NOT write or modify test files, datasets, judge prompts, source code, migrations, or CI configs.
- Does NOT advance `STATE.md` cursor — eval audit is post-shipping, no phase state change.
- Does NOT regenerate the eval plan — that is `/release:ai-phase {NN} --revise`.
- Does NOT auto-fix gaps — remediation goes into a follow-up phase (typically via `/release:plan {NN} --gaps` or a new phase).
- Does NOT replace `/release:verify` — runs alongside it as the AI-domain audit gate.

## Constraints

- Read-only on source: never edits source, migrations, tests, datasets, judge prompts, CI configs.
- Evidence must be `file:line`. No claims without grep proof.
- Status values restricted to: `COVERED`, `PARTIAL`, `MISSING`, `N/A`.
- Auditor never commits — this skill owns the single commit of the audit artifact.

---

## Stack dispatch

This skill is stack-agnostic. Eval audits operate at the use-case layer (failure modes, judges,
dataset), not the stack layer. The auditor probes both backend and frontend paths as the plan
demands (Django for AILog + DRF throttle; React for Zod schema + ToolConfirmDialog).
