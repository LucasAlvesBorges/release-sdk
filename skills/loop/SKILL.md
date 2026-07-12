---
name: loop
description: >
  Closed build→gate→check→fix→land loop. You stop being the element inside the loop: set a goal
  (a phase SPEC's acceptance criteria, or — for freeform — your prompt verbatim), and the harness
  drives maker → objective GATE (run_gate) → independent CHECKER → targeted fix, iterating until
  the gate is GREEN and the checker PASSES, then auto-lands on base so you can test the feature.
  Bounded by a hard iteration cap, no-progress detection, and an optional token-spend ceiling.
  Phase mode (`/release:loop NN`) is an alias for `/release:execute {NN}`, which loops by default — this
  skill OWNS the FREEFORM mode (a bounded task with no phase/PLAN, goal = your prompt verbatim).
  Use when: you want a bounded task driven to "done" without re-prompting each round.
---

## Agent Policy (LOCKED)

NEVER spawn `gsd-*` agents — only `release-*`. Orphan `gsd-*` may appear in `subagent_type` list from prior installs or imported projects; ignore them. Rule: `gsd-<x>` → `release-<x>`. Substituting bypasses release-sdk hooks/audit and corrupts plugin isolation.

---

# /release:loop — Closed Maker→Gate→Checker→Land Loop

This is loop engineering made native: instead of you prompting, reading the result, fixing, and
re-prompting every round, `/release:loop` is the harness that does it. It needs the three things a
loop needs and the plugin now supplies all three:

1. **A trigger** — you running `/release:loop` (or `/release:auto` routing to it).
2. **A verifiable goal** — the objective **GATE** (`run_gate` over `.release-planning/VERIFY-GATE.yml`)
   AND the intent **GOAL** (a phase SPEC's acceptance criteria, or your verbatim prompt for freeform).
   Both must hold: a green gate alone is "tests pass", not "the thing we wanted exists".
3. **Budget + guardrails** — a hard iteration cap, no-progress detection, an optional `--budget-usd`
   token ceiling, and a hold-don't-clobber circuit breaker. (Critical safety stays in the PreToolUse
   hooks, not here — the loop runs *under* them.)

> **Phase mode = `/release:execute`.** `/release:loop {NN}` simply invokes `/release:execute {NN}`,
> which **loops by default** (build → gate → `release:phase-verifier` → `release:code-fixer` →
> re-verify → land) using these same engines. There is ONE phase-loop implementation, and it lives in
> `/release:execute`. This skill's own machinery below drives the **freeform** mode: a bounded task with
> no phase/PLAN, goal = your prompt verbatim, checked by `release:loop-goal-verifier`. The protocol is
> identical; only the maker (`tdd-executor` vs `wave-executor`) and the checker differ.

## Usage

```
/release:loop 03                      # phase loop: goal = phase 03 SPEC acceptance criteria
/release:loop                         # phase loop on the active phase (from STATE.md)
/release:loop "make the invoice export honor the ?status= filter"   # freeform: goal = this prompt
/release:loop 03 --max-iters 8        # raise the iteration cap (default 6)
/release:loop 03 --budget-usd 4.00    # also stop if this session's tracked spend crosses $4.00
/release:loop 03 --no-land            # iterate to green+PASS but DON'T land (leave for you to land)
/release:loop "..." --backend         # force stack for a freeform loop
```

## What "done" means (the stop condition)

The loop stops and lands **only** when BOTH are true, with evidence:

- **GATE = GREEN** — every command in `VERIFY-GATE.yml` (or the stack default) exits 0. Objective,
  tool-checked. This is `run_gate` from `bin/release-gate-lib.sh` — the agent does not get to "decide"
  the gate is green.
- **CHECKER = PASS** — an independent agent (the maker never checks its own work) verifies the GOAL is
  observably satisfied (L1 artifact → L2 substantive → L3 wired test) and returns evidence, not a
  claim. Phase mode → `release:phase-verifier` (which now also honors the SPEC's acceptance criteria);
  freeform → `release:loop-goal-verifier` (goal = your prompt).

Anything else is a continue-or-stop decision made by `loop_guard`, never by vibes.

## Pre-flight

1. `.release-planning/` exists (else `/release:init`).
2. **Phase mode**: resolve `NN` (arg, else `active_phase` in STATE.md). The phase should have a PLAN
   (`/release:plan {NN}`); a SPEC (`/release:spec {NN}`) is strongly recommended — its acceptance
   criteria become the loop's intent goal. No SPEC → the loop falls back to PLAN `must_haves` +
   ROADMAP `success_criteria` (still a real goal, just less sharp).
3. **Freeform mode**: the prompt IS the goal. If it implies a feature (> ~10 files, "design", "new
   architecture"), stop and recommend `/release:spec` → a real phase loop instead.
4. Resolve the shared engines (mirror the discovery `/release:execute` uses):

```bash
find_lib() {  # $1 = lib filename → echo absolute path or empty
  local p="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/$1}"
  [ -n "$p" ] && [ -f "$p" ] && { printf '%s' "$p"; return; }
  find "$HOME/.claude" -name "$1" -path '*/bin/*' 2>/dev/null | head -1
}
GATE_LIB="$(find_lib release-gate-lib.sh)"; MERGE_LIB="$(find_lib release-merge-lib.sh)"; LOOP_LIB="$(find_lib release-loop-lib.sh)"
for L in "$GATE_LIB" "$MERGE_LIB" "$LOOP_LIB"; do [ -f "$L" ] || { echo "ABORT: missing engine ($L). Set CLAUDE_PLUGIN_ROOT."; exit 1; }; done
. "$GATE_LIB"; . "$MERGE_LIB"; . "$LOOP_LIB"
MODEL_LIB="$(find_lib release-model-lib.sh)"; [ -f "$MODEL_LIB" ] && . "$MODEL_LIB"
```

**Resolve model tiers ONCE** (see /release:auto → "Model-Tier Orchestration (LOCKED)"). You are the
orchestrator; self-identify: if your session model is Opus (not Fable), `export RELEASE_MODEL_PROFILE=opus-sonnet`
first. Then:
```bash
WORKER_MODEL="$(  [ -f "$MODEL_LIB" ] && release_worker_model  || echo sonnet )"   # tdd-executor (maker), code-fixer (fixer)
CHECKER_MODEL="$( [ -f "$MODEL_LIB" ] && release_checker_model || echo opus   )"   # loop-goal-verifier / phase-verifier, wave-executor
[ -f "$MODEL_LIB" ] && echo "→ models: $(release_model_summary)"
```
Every spawn below carries an explicit `model:` from these; worker prompts also say "operate at maximum rigor / max effort".

## Isolate (ephemeral worktree off base)

Same isolation model as `/release:quick` and `/release:execute`: the loop works in its OWN worktree
off base, so your main checkout stays live and dirty-safe while the loop runs, and N loops/quicks/an
execute never collide. Auto-land is held-not-clobbered if base is dirty.

```bash
MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"
BASE="$(git -C "$MAIN_ROOT" rev-parse --abbrev-ref HEAD)"     # land target = the branch you test on
# phase mode: LABEL="{NN}-{slug}", BRANCH="feat/{NN}-{slug}"  (and take the per-phase lock, exactly as
#   /release:execute does, so a loop and an execute can't both drive the same phase)
# freeform : LABEL="loop-$(date +%Y%m%d-%H%M%S)-<slug>", BRANCH="loop/$LABEL"
LWT="$MAIN_ROOT/../release-worktrees/<phase|loop>/$LABEL"
mkdir -p "$(dirname "$LWT")"; git -C "$MAIN_ROOT" worktree prune
git -C "$MAIN_ROOT" worktree add -q -b "$BRANCH" "$LWT" "$BASE"
```

> **Inside a `/release:session` worktree** (`.release-planning/.session` exists): do NOT nest a
> worktree and do NOT land. Run the loop in place (`cwd: "."`) on the current `session/<label>`
> branch; the session's own `finish` lands the result. (`--no-land` is implied in-session.)

## The loop

`max_iters` default **6** (`--max-iters` to change). All work happens in `$LWT`. The maker NEVER
lands; only this orchestrator lands, and only after GATE=GREEN **and** CHECKER=PASS.

```
prev_sig = ""            # signature of the previous iteration's failure (no-progress detection)
iter = 0

# ── iteration 1: build ──────────────────────────────────────────────────────────────────────
iter = 1
MAKER.build():
  phase mode    → spawn release:wave-executor { model: $CHECKER_MODEL, worker_model: $WORKER_MODEL,
                                                cwd: $LWT, branch: $BRANCH, branch_already_set: true,
                                                no_land: true }     # fan-out sub-orchestrator; builds the PLAN, NO land
  freeform mode → spawn release:tdd-executor  { model: $WORKER_MODEL, cwd: $LWT, quick_mode: true, no_plan: true,
                                                branch_already_set: true, task: "<the prompt>",
                                                instruction_suffix: "operate at maximum rigor / max effort" }

# ── iterate: gate → (fix | check) ───────────────────────────────────────────────────────────
while true:
  # 1. OBJECTIVE GATE (deterministic — the tool decides, not the agent)
  OUT      = run_gate "$LWT"                 # echoes GATE_STEP / GATE_EVIDENCE / GATE=
  verdict  = last "GATE=" value in OUT
  evidence = "GATE_EVIDENCE=" path in OUT    # the failing command's captured output, if RED

  if verdict == "":                          # no gate resolved (no config + unknown stack)
      surface this; ask the user to add .release-planning/VERIFY-GATE.yml; STOP (can't close a loop
      with no objective goal — refusing to guess is the point).

  if verdict == "RED":
      cur_sig = loop_signature < "$evidence file contents"
      G = loop_guard $iter $max_iters "$prev_sig" "$cur_sig"
      if G says stop:  → CIRCUIT BREAK (see below), break
      prev_sig = cur_sig
      surface the evidence (the actual failing command + output — not a paraphrase)
      iter += 1
      MAKER.fix(evidence):
        spawn release:code-fixer { model: $WORKER_MODEL, cwd: $LWT, finding: <gate evidence>,
                                   instruction: "operate at maximum rigor; make `run_gate` green; fix ONLY what this evidence shows" }
      continue                               # re-gate next round

  # verdict == GREEN → the objective half is satisfied; now verify the INTENT half
  # 2. INDEPENDENT CHECKER (maker ≠ checker: checker runs on the orchestrator tier, above the maker)
  CHK = phase mode    → spawn release:phase-verifier   { model: $CHECKER_MODEL, stack, phase_number: NN, phase_dir,
                                                         goal_source: "SPEC acceptance criteria + PLAN must_haves" }
        freeform mode → spawn release:loop-goal-verifier { model: $CHECKER_MODEL, stack, goal: "<the prompt verbatim>", worktree: $LWT }

  if CHK == PASS:
      LAND. break                            # ↓ see "Land"

  # CHK == GAPS / CRITICAL → intent not met though tests are green
  cur_sig = loop_signature < "<the checker's gap findings>"
  G = loop_guard $iter $max_iters "$prev_sig" "$cur_sig"
  if G says stop:  → CIRCUIT BREAK, break
  prev_sig = cur_sig
  surface the gaps (with the checker's evidence)
  iter += 1
  MAKER.fix(gaps):
    spawn release:code-fixer { model: $WORKER_MODEL, cwd: $LWT, finding: <checker gaps>,
                               instruction: "operate at maximum rigor; close these goal gaps; add the missing test+impl" }
  continue

# optional token ceiling — check once per round when --budget-usd is set:
#   loop_token_spend "$BUDGET_USD"  → if it echoes "LOOP=stop reason=budget-tokens", CIRCUIT BREAK.
```

## Land (full-auto on GREEN + PASS)

The chosen autonomy: the loop lands by itself once the gate is green and the checker passes, so the
feature is on your trunk and you can test it. No pre-land approval gate (use `--no-land` if you want
one). Landing is the SAME serialized, conflict-safe, held-dirty-safe `land_branch` every other skill
uses — a dirty live base is never clobbered:

```bash
RESULT="$(land_branch "$BRANCH" "$LWT" "$BASE" | tail -1)"
cd "$MAIN_ROOT"
case "$RESULT" in
  RESULT=merged)     echo "✓ loop done in $iter iters → landed on $BASE (live). Test the feature, then /release:verify." ;;
  RESULT=held-dirty) echo "⏸ green+PASS, but $BASE has uncommitted work — held on $BRANCH. Commit/stash, then /release:land $LABEL." ;;
  RESULT=conflict)   echo "✗ green+PASS, but code conflict vs $BASE. Resolve in $LWT, then /release:land $LABEL." ;;
  *)                 echo "✗ land failed ($RESULT). Worktree kept at $LWT." ;;
esac
```

`--no-land` (or in-session): skip landing; print the branch + worktree and the green/PASS evidence.

## Circuit breaker (budget, no-progress) — hold, don't clobber, ping the human

When `loop_guard` (or the token ceiling) says stop before the goal is met, the loop does NOT land and
does NOT throw work away. It **holds**: the worktree and branch stay exactly as they are, base is
untouched. Then it reports — precisely — where it got stuck and hands the decision back:

```
⚠ loop stopped: <reason: no-progress | budget-iters | budget-tokens> after <iter> iterations.
  Goal:      <SPEC acceptance criteria | your prompt>
  Last gate: <GREEN | RED at step "<name>">
  Stuck on:  <the failing command + evidence path, or the checker's open gaps>
  Worktree:  $LWT   (branch $BRANCH — nothing landed, base clean)
```

Then `AskUserQuestion`: **[ give N more iterations | take it over manually (open $LWT) | discard the
branch + worktree ]**. This is the human-at-the-checkpoint that keeps a runaway loop from becoming a
$400 overnight terminal: the loop pings, it does not silently grind.

- **no-progress** = two consecutive iterations produced the SAME failure signature (the maker is not
  actually changing the outcome). More iterations rarely help — surfaced first because it's the most
  actionable.
- **budget-iters** = hit `--max-iters`. Raise it deliberately, don't reflexively.
- **budget-tokens** = `--budget-usd` crossed (from the `/release:tokens` daemon). Absent daemon ⇒ this
  guard is simply inactive (it never blocks on a missing meter).

## Evidence, always

Every iteration surfaces the REAL artifact — the failing command and its captured output, or the
checker's gap findings with file:line — never "I fixed it" / "looks done". Reviewing evidence is
faster than re-running the check, and it works even for iterations you didn't watch. The gate's
evidence file and the checker's VERIFICATION.md are the durable record.

## Constraints

- **Maker ≠ checker.** The agent that writes code never decides whether the goal is met. The gate is a
  tool; the checker is a different agent. This is the whole anti-confirmation-bias point.
- **The gate is the law for landing.** No land without GATE=GREEN, regardless of what any agent says.
- **No push.** Landing is a local merge onto base; pushing/PR is your call.
- **Bounded by construction.** A loop with no stop condition is a bug; `loop_guard` makes the cap,
  no-progress, and token ceiling non-optional.
- **Safety is in hooks, not prose.** Tenant scope, no-token-in-localStorage, conventional commits,
  prompt-injection scanning all run as PreToolUse hooks during every maker iteration. The loop cannot
  disable them.
- `.planning/` untouched — this plugin owns `.release-planning/` only.

## Example

```
/release:loop 03

→ Goal: phase 03 SPEC acceptance criteria (4 items) + PLAN must_haves
→ Gate: .release-planning/VERIFY-GATE.yml (lint, migrate, test)
→ Worktree feat/03-invoice-export off dev ✓   (max-iters 6)

iter 1  build      → release:wave-executor: 5 commits on feat/03-invoice-export (no land)
        gate       → GATE_STEP=lint PASS · migrate PASS · test FAIL  → RED
        evidence   → tests/test_export.py::test_status_filter  AssertionError: 3 != 1
        guard      → continue (1/6, new failure)
iter 2  fix(gate)  → release:code-fixer: queryset honors ?status=  (commit)
        gate       → lint PASS · migrate PASS · test PASS  → GREEN
        check      → release:phase-verifier: AC-1..AC-3 VERIFIED, AC-4 FAILED (no empty-result UX)
        guard      → continue (2/6, new gap)
iter 3  fix(gap)   → release:code-fixer: empty-state + test for AC-4  (commit)
        gate       → GREEN
        check      → release:phase-verifier: 4/4 VERIFIED · tests 22/22 · 0 LOCK violations → PASS
        land       → land_branch feat/03-invoice-export → dev: ✓ merged (live)

✓ loop done in 3 iters → landed on dev. Test the export, then /release:verify 03.
```

---

_The loop is the back-and-forth between Execute and Review, automated. Maker builds, the gate and an
independent checker decide, the fixer feeds on real evidence, and it lands itself when — and only
when — the goal is objectively met._
