#!/usr/bin/env bash
# release-economy-lib.sh — shared cost/rigor policy for release-sdk workflows.
#
# The default path is intentionally small. Expensive agents, broad test sweeps and
# independent review are selected by risk/complexity instead of being universal.

release_complexity_normalize() { # [C0-C4|0-4|lean|standard|strict]
  case "${1:-C2}" in
    C0|c0|0|lean) printf 'C0' ;;
    C1|c1|1) printf 'C1' ;;
    C2|c2|2|standard) printf 'C2' ;;
    C3|c3|3|strict) printf 'C3' ;;
    C4|c4|4) printf 'C4' ;;
    *) printf 'C2' ;;
  esac
}

release_delivery_profile() { # [complexity]
  case "$(release_complexity_normalize "${1:-}")" in
    C0|C1) printf 'lean' ;;
    C2) printf 'standard' ;;
    C3|C4) printf 'strict' ;;
  esac
}

release_risk_floor() { # <complexity> [risk words...]
  local level risk
  level="$(release_complexity_normalize "${1:-}")"; shift 2>/dev/null || true
  risk=" $(printf '%s ' "$@" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]-' ' ') "
  case "$risk" in
    *" destructive migration "*|*" data loss "*|*" production incident "*|*" cross-service transaction "*) printf 'C4'; return ;;
    *" auth "*|*" authorization "*|*" payment "*|*" crypto "*|*" secret "*|*" privacy "*|*" tenancy "*|*" multi-tenant "*)
      case "$level" in C0|C1|C2) printf 'C3'; return;; esac
      ;;
  esac
  printf '%s' "$level"
}

release_should_parallelize() { # <complexity> <independent_tasks> <files_disjoint:0|1>
  local profile tasks="${2:-0}" disjoint="${3:-0}"
  profile="$(release_delivery_profile "${1:-}")"
  [ "$profile" = strict ] && [ "$tasks" -ge 3 ] 2>/dev/null && [ "$disjoint" = 1 ]
}

release_should_check() { # <complexity> [risk-present:0|1]
  [ "$(release_delivery_profile "${1:-}")" = strict ] || [ "${2:-0}" = 1 ]
}

release_loop_default_iters() { # [complexity]
  case "$(release_delivery_profile "${1:-}")" in
    lean) printf '1' ;;
    standard) printf '2' ;;
    strict) printf '3' ;;
  esac
}

release_test_scope() { # [complexity]
  case "$(release_delivery_profile "${1:-}")" in
    lean) printf 'focused' ;;
    standard) printf 'focused+final-gate' ;;
    strict) printf 'focused+final-gate+independent-check' ;;
  esac
}
