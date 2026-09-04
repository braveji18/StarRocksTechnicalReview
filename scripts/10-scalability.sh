#!/usr/bin/env bash
# 확장성 측정 (docs/05 §4, 배점 10)
#
#   scripts/10-scalability.sh <engine> <track> <nodes_before> <nodes_after> "<scale-out 명령>"
#
#   예 (Kubernetes):
#     scripts/10-scalability.sh trino A 3 6 "kubectl scale deploy/trino-worker --replicas=6"
#     scripts/10-scalability.sh starrocks B 3 6 "kubectl scale sts/starrocks-be --replicas=6"
#
#   절차: 기준 QPS 측정 -> 확장 실행 -> 재분배 완료 대기 -> QPS 재측정 -> 선형성 계수 산출
. "$(dirname "$0")/lib/common.sh"
require_env; require_venv

ENGINE="${1:?engine}"; TRACK="${2:-A}"
NODES_BEFORE="${3:?확장 전 연산 노드 수}"; NODES_AFTER="${4:?확장 후 연산 노드 수}"
SCALE_CMD="${5:?확장 실행 명령}"
USERS="${SCALE_TEST_USERS:-$SLA_TARGET_CONCURRENT_USERS}"
DUR="${SCALE_TEST_DURATION:-300}"
REBALANCE_WAIT="${REBALANCE_WAIT_SEC:-600}"

banner "10 확장성 - $ENGINE / ${NODES_BEFORE} -> ${NODES_AFTER} 노드"
cd "$ROOT"

log "1) 확장 전 QPS 측정 (동시 ${USERS}, ${DUR}s)"
"$PY" -m bench.run_concurrency --engine "$ENGINE" --track "$TRACK" \
      --users "$USERS" --duration "$DUR" --warmup 60
QPS_BEFORE=$("$PY" - <<'PY'
from bench import resultio
rows = resultio.read_csv(resultio.results_path("performance", "p3_summary.csv"))
print(rows[-1]["peak_qps"] if rows else "")
PY
)
log "   확장 전 최대 QPS = ${QPS_BEFORE}"

log "2) 확장 실행: $SCALE_CMD"
SCALE_START=$(date +%s)
eval "$SCALE_CMD" || die "확장 명령 실패"
SCALE_END=$(date +%s)
log "   확장 명령 소요 $((SCALE_END - SCALE_START))s"

log "3) 데이터 재분배 완료 대기 (최대 ${REBALANCE_WAIT}s)"
cat <<'NOTE'
   StarRocks shared-nothing 은 노드 증감 시 tablet 재분배가 발생한다.
   재분배 완료 판정 기준을 사전에 정의하고 완료 시각을 기록할 것 (docs/06 §2).
   Trino 워커는 상태를 갖지 않아 즉시 활용되나, 축소 시 진행 중 쿼리 처리 방식을 확인할 것.
NOTE
REB_START=$(date +%s)
read -r -p "   재분배 완료를 확인했으면 Enter (미해당이면 그냥 Enter): " _
REB_END=$(date +%s)

log "4) 확장 후 QPS 재측정"
"$PY" -m bench.run_concurrency --engine "$ENGINE" --track "$TRACK" \
      --users "$USERS" --duration "$DUR" --warmup 60
QPS_AFTER=$("$PY" - <<'PY'
from bench import resultio
rows = resultio.read_csv(resultio.results_path("performance", "p3_summary.csv"))
print(rows[-1]["peak_qps"] if rows else "")
PY
)

OUT="$ROOT/results/operability/scalability.csv"
mkdir -p "$(dirname "$OUT")"
[[ -f "$OUT" ]] || echo "engine,nodes_before,nodes_after,qps_before,qps_after,scale_out_sec,rebalance_sec,nondisruptive,running_query_failed,note" > "$OUT"
echo "${ENGINE},${NODES_BEFORE},${NODES_AFTER},${QPS_BEFORE},${QPS_AFTER},$((SCALE_END-SCALE_START)),$((REB_END-REB_START)),,,확장 중 무중단 여부와 진행 중 쿼리 실패 여부를 직접 채울 것" >> "$OUT"

"$PY" - "$QPS_BEFORE" "$QPS_AFTER" "$NODES_BEFORE" "$NODES_AFTER" <<'PY'
import sys
before, after, nb, na = (float(x) if x else 0 for x in sys.argv[1:5])
if before and nb:
    lin = (after / before) / (na / nb)
    print(f"\n선형성 계수 = {lin:.3f}  (docs/01 §3.4 배점표로 환산)")
else:
    print("\nQPS 측정값이 비어 있어 선형성 계수를 산출할 수 없다.")
PY
log "기록: $OUT  (nondisruptive / running_query_failed 열을 직접 채울 것)"
