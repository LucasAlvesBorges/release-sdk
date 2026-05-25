---
description: >
  Verifies Author Checklist Q1-Q7 applied to implemented Django code — select_related (Q1),
  prefetch_related (Q2), annotate Count (Q3), Subquery/OuterRef (Q4), F()/select_for_update (Q5),
  .delay_on_commit() (Q6, LOCKED), .iterator() (Q7). Produces CHECKLIST.md with PASS/FAIL.
  Use when: pre-merge verification, audit existing feature, ensure Q1-Q7 compliance.
allowed_tools: Agent, Read, Bash, Grep, Glob
---

# /django:checklist — Author Checklist Q1-Q7 Verification

Verifies each Q1-Q7 question is applied OR has valid N/A justification. Not opinion — grep-based evidence.

## Usage

```
/django:checklist backend/apps/financeiro/
/django:checklist --feature=baixa_parcela
```

## Arguments

- `$ARGUMENTS` — Feature scope (app dir or files)
- `--checklist-path=PATH` — Output (default: `./CHECKLIST.md`)

## The 7 Questions

| Q | Pattern |
|---|---------|
| Q1 | `select_related()` for every FK accessed in serializer |
| Q2 | `prefetch_related()` for every M2M/reverse-FK iterated |
| Q3 | `annotate(x_count=Count())` not `get_x_count` method |
| Q4 | `Subquery + OuterRef` for per-row aggregation |
| Q5 | `F()` OR `transaction.atomic() + select_for_update()` for numeric mutation |
| Q6 | `.delay_on_commit()` always — LOCKED, never `.delay()` |
| Q7 | `.iterator(chunk_size=N)` for queryset >1000 rows |

## Workflow

1. Spawn `django-checklist-verifier` agent
2. Agent greps for each Q's pattern in implementation
3. Each Q: PASS (pattern present) | FAIL (pattern absent + trigger present) | PARTIAL (test missing) | N/A (no trigger)
4. Q5 requires accompanying race test (`tests/test_*_race.py`)
5. Q7 requires accompanying memray test (`tests/test_*_memray.py`)

## Output

```yaml
questions:
  Q1_select_related: PASS
  Q2_prefetch_related: PASS
  Q3_annotate_count: FAIL    # uses get_x_count method
  Q4_subquery_outerref: N/A
  Q5_f_or_select_for_update: PARTIAL   # F() present, race test missing
  Q6_delay_on_commit: PASS
  Q7_iterator_chunk_size: N/A
score: 3 PASS, 1 FAIL, 1 PARTIAL, 2 N/A
status: NON_COMPLIANT
```
