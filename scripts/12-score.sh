#!/usr/bin/env bash
# 채점 집계 (docs/01)
#   scripts/12-score.sh [--primary-track A|B]
. "$(dirname "$0")/lib/common.sh"
require_env; require_venv
banner "12 채점 집계"

for f in results/operability/operability_scores.csv \
         results/operability/fault_injection.csv \
         results/operability/scalability.csv \
         results/cost/cost_tco.csv \
         results/scoring/knockout.csv; do
  [[ -f "$ROOT/$f" ]] || warn "수동 입력 파일 없음: $f (results/templates/ 에서 복사할 것)"
done

cd "$ROOT"
"$PY" -m bench.score "$@"
