#!/usr/bin/env bash
# Contract test for the model-tier orchestration substrate (v0.19.0).
#
# SOURCES the real shipped engine — bin/release-model-lib.sh — so there is NO drift: the code under
# test IS the code skills/{auto,execute,loop,quick,security,debug,models} resolve tiers from.
#
# Coverage:
#   #1  default profile is fable-opus (best tier assumed; orchestrator downgrades when it is Opus)
#   #2  fable-opus maps orchestrator/checker→fable, worker→opus
#   #3  opus-sonnet maps orchestrator/checker→opus, worker→sonnet
#   #4  checker == orchestrator tier in BOTH profiles (Fable evaluates Opus; Opus evaluates Sonnet)
#   #5  worker is exactly one rung BELOW the orchestrator in BOTH profiles (never spawns a tier the user lacks)
#   #6  RELEASE_MODEL_PROFILE env overrides everything
#   #7  an invalid RELEASE_MODEL_PROFILE is ignored (falls back to default) + warns on stderr
#   #8  MODELS.yml `profile:` pin is honored when env is unset
#   #9  env pin beats the MODELS.yml pin (most-specific wins)
#   #10 mechanical tier is haiku and profile-invariant (the one effort exception)
#   #11 effort is max by default, honors CLAUDE_EFFORT
#   #12 release_model_summary reflects the active mapping
#
# Run: bash bin/test-model-lib.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-model-lib.sh
source "$HERE/release-model-lib.sh"

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }
ne() { [ "$2" != "$3" ] && ok "$1" || no "$1" "both were [$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1" "missing [$3] in: $2";; esac; }

# Isolate from the developer's real env + any repo MODELS.yml — run each case in a scratch cwd.
SCRATCH="$(mktemp -d)"; trap 'rm -rf "$SCRATCH"' EXIT
cd "$SCRATCH"                                  # no .release-planning here, not a git repo → clean slate
unset RELEASE_MODEL_PROFILE 2>/dev/null || true

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #1 default profile ──"
eq "no env, no config → fable-opus" "fable-opus" "$(release_model_profile)"

echo "── #2 fable-opus role mapping ──"
eq "orchestrator → fable" "fable"  "$(RELEASE_MODEL_PROFILE=fable-opus release_orchestrator_model)"
eq "worker       → opus"  "opus"   "$(RELEASE_MODEL_PROFILE=fable-opus release_worker_model)"
eq "checker      → fable" "fable"  "$(RELEASE_MODEL_PROFILE=fable-opus release_checker_model)"

echo "── #3 opus-sonnet role mapping ──"
eq "orchestrator → opus"   "opus"   "$(RELEASE_MODEL_PROFILE=opus-sonnet release_orchestrator_model)"
eq "worker       → sonnet" "sonnet" "$(RELEASE_MODEL_PROFILE=opus-sonnet release_worker_model)"
eq "checker      → opus"   "opus"   "$(RELEASE_MODEL_PROFILE=opus-sonnet release_checker_model)"

echo "── #4 checker == orchestrator (maker≠checker across tiers) ──"
eq "fable-opus:  checker==orchestrator" \
   "$(RELEASE_MODEL_PROFILE=fable-opus release_orchestrator_model)" \
   "$(RELEASE_MODEL_PROFILE=fable-opus release_checker_model)"
eq "opus-sonnet: checker==orchestrator" \
   "$(RELEASE_MODEL_PROFILE=opus-sonnet release_orchestrator_model)" \
   "$(RELEASE_MODEL_PROFILE=opus-sonnet release_checker_model)"

echo "── #5 worker is one rung below orchestrator (never spawns a tier the session lacks) ──"
ne "fable-opus:  worker != orchestrator" \
   "$(RELEASE_MODEL_PROFILE=fable-opus release_worker_model)" \
   "$(RELEASE_MODEL_PROFILE=fable-opus release_orchestrator_model)"
eq "fable-opus:  worker == opus (below fable)" "opus" "$(RELEASE_MODEL_PROFILE=fable-opus release_worker_model)"
eq "opus-sonnet: worker == sonnet (below opus)" "sonnet" "$(RELEASE_MODEL_PROFILE=opus-sonnet release_worker_model)"

echo "── #6 env override ──"
eq "env forces opus-sonnet" "opus-sonnet" "$(RELEASE_MODEL_PROFILE=opus-sonnet release_model_profile)"

echo "── #7 invalid env ignored + warns ──"
eq "garbage env → default fable-opus" "fable-opus" "$(RELEASE_MODEL_PROFILE=banana release_model_profile 2>/dev/null)"
has "warns on stderr" "$(RELEASE_MODEL_PROFILE=banana release_model_profile 2>&1 >/dev/null)" "ignoring invalid"

echo "── #8 MODELS.yml pin honored ──"
mkdir -p "$SCRATCH/.release-planning"
printf 'profile: opus-sonnet\n' > "$SCRATCH/.release-planning/MODELS.yml"
eq "config pin → opus-sonnet" "opus-sonnet" "$(release_model_profile)"

echo "── #9 env beats config ──"
eq "env fable-opus overrides config opus-sonnet" "fable-opus" "$(RELEASE_MODEL_PROFILE=fable-opus release_model_profile)"
rm -f "$SCRATCH/.release-planning/MODELS.yml"

echo "── #10 mechanical tier ──"
eq "mechanical → haiku (fable-opus)"  "haiku" "$(RELEASE_MODEL_PROFILE=fable-opus release_mechanical_model)"
eq "mechanical → haiku (opus-sonnet)" "haiku" "$(RELEASE_MODEL_PROFILE=opus-sonnet release_mechanical_model)"

echo "── #11 effort ──"
eq "default effort → max" "max" "$(unset CLAUDE_EFFORT; release_model_effort)"
eq "honors CLAUDE_EFFORT" "high" "$(CLAUDE_EFFORT=high release_model_effort)"

echo "── #12 summary reflects mapping ──"
has "summary shows worker=opus under fable-opus" "$(RELEASE_MODEL_PROFILE=fable-opus release_model_summary)" "worker=opus"
has "summary shows worker=sonnet under opus-sonnet" "$(RELEASE_MODEL_PROFILE=opus-sonnet release_model_summary)" "worker=sonnet"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
