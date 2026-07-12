#!/usr/bin/env bash
# release-model-lib.sh — the model-tier orchestration substrate for /release:* loop engineering.
#
# SINGLE SOURCE OF TRUTH for "which model runs this role?". Sourced by:
#   - skills/auto/SKILL.md      (LOCKED doctrine block — inherited by every routed skill)
#   - skills/execute/SKILL.md   (main loop: orchestrator → fan-out → workers → checker)
#   - skills/loop/SKILL.md      (freeform loop: worker maker + checker)
#   - skills/quick/SKILL.md     (bounded task: worker maker)
#   - skills/security/SKILL.md  (audit loop: worker auditors + orchestrator evaluation)
#   - skills/debug/SKILL.md     (worker debugger loop)
#   - skills/models/SKILL.md    (view / pin the active profile)
#   - bin/test-model-lib.sh     (the contract test SOURCES this file — no drift)
#
# THE TOPOLOGY (see README "Model-tier orchestration"):
#   Orchestrator (main loop: plan → fan out → evaluate → re-dispatch)  ── Fable  ── evaluates ↓
#       └─ fan out → N Workers (each with its own worker loop: build → self-check → fix) ── Opus
#   The orchestrator NEVER authors code; workers NEVER decide "done". The checker runs on the
#   ORCHESTRATOR tier (a different model than the maker) so "Fable evaluates Opus's work" is literal
#   AND the maker≠checker anti-confirmation-bias invariant holds by construction.
#
# TWO PROFILES, derived from the SESSION model (the running orchestrator self-identifies):
#   fable-opus  (primary)   orchestrator=Fable   worker=Opus     ← session is running on Fable
#   opus-sonnet (fallback)  orchestrator=Opus    worker=Sonnet   ← Fable unavailable; session on Opus
# This guarantees we NEVER spawn a tier the user lacks: workers are always exactly one rung BELOW the
# orchestrator, and the orchestrator is the session the user already chose in Claude Code (`/model`).
#
# The orchestrator (the LLM running the skill) sets the profile because bash cannot read the session
# model — there is no session-model env var (only CLAUDE_EFFORT). Resolution order, most-specific first:
#   1. RELEASE_MODEL_PROFILE env         — explicit override; the orchestrator exports this from
#                                          self-knowledge ("I am Fable" → fable-opus; "I am Opus" → opus-sonnet).
#   2. .release-planning/MODELS.yml       — `profile: fable-opus|opus-sonnet` pin (survives across sessions).
#   3. default                            — fable-opus (assume the best tier is available; the
#                                          orchestrator downgrades to opus-sonnet when it is Opus).
#
# Public API (all echo a value and return 0 — house style; callers capture the echo):
#   release_model_profile               → `fable-opus` | `opus-sonnet`
#   release_orchestrator_model          → `fable` | `opus`     (the main-loop driver + fan-out coordinator)
#   release_worker_model                → `opus`  | `sonnet`   (makers, fixers, auditors, debuggers)
#   release_checker_model               → = orchestrator tier  (Fable evaluates Opus; Opus evaluates Sonnet)
#   release_mechanical_model            → `haiku`              (collection-only agents; the ONE effort exception)
#   release_model_effort                → `max` (or $CLAUDE_EFFORT) — every role runs at maximum effort
#   release_model_summary               → one human-readable line of the active mapping (for skill preambles)

# ── internal: valid profiles ─────────────────────────────────────────────────────────────────────
_release_model_valid_profile() {  # $1 → 0 if a known profile, else 1
  case "$1" in fable-opus|opus-sonnet) return 0;; *) return 1;; esac
}

# ── public: resolve the active profile ───────────────────────────────────────────────────────────
release_model_profile() {
  local p="${RELEASE_MODEL_PROFILE:-}"
  if [ -n "$p" ]; then
    if _release_model_valid_profile "$p"; then printf '%s' "$p"; return 0; fi
    printf 'release-model-lib: ignoring invalid RELEASE_MODEL_PROFILE=%s (want fable-opus|opus-sonnet)\n' "$p" >&2
  fi
  # config pin — look up from cwd's repo, then cwd itself
  local root cfg
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  cfg="$root/.release-planning/MODELS.yml"
  [ -f "$cfg" ] || cfg=".release-planning/MODELS.yml"
  if [ -f "$cfg" ]; then
    p="$(grep -m1 '^[[:space:]]*profile:' "$cfg" 2>/dev/null | sed -E 's/^[[:space:]]*profile:[[:space:]]*//; s/[[:space:]]*$//')"
    if [ -n "$p" ] && _release_model_valid_profile "$p"; then printf '%s' "$p"; return 0; fi
  fi
  printf 'fable-opus'   # default: assume the best tier; the orchestrator downgrades when it is Opus
  return 0
}

# ── public: concrete model per role ──────────────────────────────────────────────────────────────
release_orchestrator_model() {
  case "$(release_model_profile)" in opus-sonnet) printf 'opus';; *) printf 'fable';; esac
  return 0
}

release_worker_model() {
  case "$(release_model_profile)" in opus-sonnet) printf 'sonnet';; *) printf 'opus';; esac
  return 0
}

# The checker is the orchestrator tier by design: a model ABOVE the maker evaluates the maker's work.
# This is both "Fable loops to evaluate Opus" (the user's intent) and the maker≠checker invariant.
release_checker_model() { release_orchestrator_model; }

# Collection-only agents (e.g. `pytest --collect-only`) carry no judgment that a bigger model improves.
# They are the ONE documented exception to "every role at the worker tier" — kept cheap on purpose.
release_mechanical_model() { printf 'haiku'; return 0; }

# ── public: effort — every role at maximum ───────────────────────────────────────────────────────
release_model_effort() { printf '%s' "${CLAUDE_EFFORT:-max}"; return 0; }

# ── public: human-readable one-liner for skill preambles + /release:models ────────────────────────
release_model_summary() {
  local prof orch work
  prof="$(release_model_profile)"; orch="$(release_orchestrator_model)"; work="$(release_worker_model)"
  printf 'profile=%s  orchestrator/checker=%s  worker=%s  effort=%s' \
    "$prof" "$orch" "$work" "$(release_model_effort)"
  return 0
}
