#!/usr/bin/env bash
# P2 대시보드 응답 시간 (docs/05 §P2). 결과 p95 를 SLA(K2)와 대조한다.
#   scripts/07-run-p2.sh <engine> <track>
. "$(dirname "$0")/lib/common.sh"
require_env; require_venv

ENGINE="${1:?engine (trino|starrocks)}"
TRACK="${2:-A}"
banner "07 P2 대시보드 응답 - $ENGINE / Track $TRACK (SLA p95 ${SLA_DASHBOARD_P95_MS}ms)"
cd "$ROOT"
"$PY" -m bench.run_latency --engine "$ENGINE" --track "$TRACK" \
      --cache warm --suite dashboard \
      --out "results/performance/p2_dashboard.csv"
