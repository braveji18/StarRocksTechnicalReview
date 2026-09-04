#!/usr/bin/env bash
# P6 자원 효율 (docs/05 §P6). 워크로드 실행 구간의 Prometheus 지표를 적분한다.
#   scripts/09-run-p6.sh <engine> <track> [selector]
. "$(dirname "$0")/lib/common.sh"
require_env; require_venv

ENGINE="${1:?engine (trino|starrocks)}"
TRACK="${2:-A}"
SELECTOR="${3:-}"

banner "09 P6 자원 효율 - $ENGINE / Track $TRACK"
curl -sf "${PROMETHEUS_URL}/-/healthy" >/dev/null 2>&1 \
  || warn "Prometheus 응답 없음 (${PROMETHEUS_URL}). 자원 지표가 비게 된다."

cd "$ROOT"
"$PY" -m bench.run_resource --engine "$ENGINE" --track "$TRACK" \
      --label "p1-warm-tpch" ${SELECTOR:+--selector "$SELECTOR"} -- \
      "$PY" -m bench.run_latency --engine "$ENGINE" --track "$TRACK" \
            --cache warm --suite tpch
