#!/usr/bin/env bash
# release-loop-lib.sh — the budget + guardrail substrate for /release:* loop engineering.
#
# SINGLE SOURCE OF TRUTH for "should the loop run another iteration?". Sourced by:
#   - skills/loop/SKILL.md                  (the closed maker→gate→checker→land loop)
#   - skills/audit-fix/SKILL.md             (no-progress + iter cap)
#   - skills/plan-review-convergence/SKILL.md (replan convergence cap)
#   - bin/test-loop-lib.sh                  (the contract test SOURCES this file — no drift)
#
# The two classic ways to burn money on an agent loop are (1) no stop condition and (2) an
# objective so vague the loop thrashes. This lib supplies the deterministic stop conditions so a
# skill never has to hand-roll them: a hard iteration cap, no-progress detection (two iterations
# that produce the SAME evidence ⇒ the maker is stuck), and a best-effort token-spend ceiling
# wired to the /release:tokens daemon (:47777). Every loop sources THIS — guardrails never drift.
#
# Public API (all echo a verdict and ALWAYS return 0 — house style; callers parse the echo):
#   loop_signature [text...]            stdin or args → a stable short hash of the iteration's
#                                       evidence, with volatile temp-paths normalized out, so two
#                                       structurally-identical failures hash EQUAL across runs.
#   loop_guard <iter> <max> <prev_sig> <cur_sig>
#                                       echoes `LOOP=continue` or `LOOP=stop reason=<no-progress|
#                                       budget-iters>`. Call AFTER completing iteration <iter> with
#                                       signature <cur_sig>; <prev_sig> is the prior iteration's.
#   loop_token_spend [ceiling_usd]      echoes `TOKENS=<usd|''>` from the daemon's current-session
#                                       cost; if a ceiling is given and exceeded, also echoes
#                                       `LOOP=stop reason=budget-tokens`. Daemon down ⇒ TOKENS= and
#                                       never blocks (an absent budget meter must not stop work).

# ── public: stable per-iteration signature (for no-progress detection) ───────────────────────────
loop_signature() {  # [text...]  (else reads stdin)
  local input h
  if [ "$#" -gt 0 ]; then input="$*"; else input="$(cat)"; fi
  # Normalize ONLY truly volatile bits — temp-file paths change every run even for an identical
  # failure. Line numbers / counts are KEPT: they carry "did anything change?" signal.
  h="$(printf '%s' "$input" | sed -E \
        -e 's#release-gate-[A-Za-z0-9]+#GATE_TMP#g' \
        -e 's#/(private/)?(tmp|var/folders)/[A-Za-z0-9._/-]+#TMP#g')"
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$h" | shasum   | awk '{print $1}'
  else                                       printf '%s' "$h" | md5sum   | awk '{print $1}'
  fi
}

# ── public: the iteration guard (hard cap + no-progress) ─────────────────────────────────────────
loop_guard() {  # <iter> <max> <prev_sig> <cur_sig>
  local iter="${1:-0}" max="${2:-6}" prev="${3:-}" cur="${4:-}"
  # no-progress first — it is the more actionable reason ("the maker is stuck", not just "out of tries")
  if [ -n "$prev" ] && [ "$prev" = "$cur" ]; then echo "LOOP=stop reason=no-progress"; return 0; fi
  if [ "$iter" -ge "$max" ] 2>/dev/null;      then echo "LOOP=stop reason=budget-iters"; return 0; fi
  echo "LOOP=continue"; return 0
}

# ── public: best-effort token-spend ceiling (wired to the :47777 tracker) ────────────────────────
loop_token_spend() {  # [ceiling_usd]
  local ceiling="${1:-}" host="${RELEASE_TOKEN_HOST:-127.0.0.1}" port="${RELEASE_TOKEN_PORT:-47777}" body spent
  command -v curl >/dev/null 2>&1 || { echo "TOKENS="; return 0; }
  body="$(curl -s --max-time 1 "http://$host:$port/api/stats" 2>/dev/null)" || true
  # session is the FIRST key the daemon emits ⇒ its cost_usd is the first match.
  spent="$(printf '%s' "$body" | grep -o '"cost_usd":[0-9.]*' | head -1 | sed 's/.*://')" || true
  echo "TOKENS=${spent}"
  [ -n "$ceiling" ] && [ -n "$spent" ] || return 0
  awk -v a="$spent" -v c="$ceiling" 'BEGIN{exit !(a+0 >= c+0)}' && echo "LOOP=stop reason=budget-tokens"
  return 0
}
