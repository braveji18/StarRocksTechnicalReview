#!/usr/bin/env bash
# P3 동시성 (docs/05 §P3)
#   scripts/08-run-p3.sh <engine> <track> [users] [duration_sec]
#   부하 발생기는 엔진 노드와 분리된 장비에서 실행할 것.
. "$(dirname "$0")/lib/common.sh"
require_env; require_venv

ENGINE="${1:?engine (trino|starrocks)}"
TRACK="${2:-A}"
USERS="${3:-$P3_USERS}"
DURATION="${4:-$P3_DURATION_SEC}"

banner "08 P3 동시성 - $ENGINE / Track $TRACK / 단계 $USERS / ${DURATION}s"
if [[ -z "${ALLOW_LOCAL_LOADGEN:-}" ]] && [[ "$TRINO_HOST" == "localhost" || "$TRINO_HOST" == "127.0.0.1" ]]; then
  warn "부하 발생기가 엔진과 같은 장비에서 실행되고 있다 (docs/02 §2.1 위반)."
  warn "스모크 검증 목적이면 무시해도 되나, 채점용 측정값으로는 사용할 수 없다."
fi
cd "$ROOT"
"$PY" -m bench.run_concurrency --engine "$ENGINE" --track "$TRACK" \
      --users "$USERS" --duration "$DURATION"
