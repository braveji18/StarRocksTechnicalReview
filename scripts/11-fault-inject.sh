#!/usr/bin/env bash
# 장애 주입 시나리오 F1~F6 (docs/06 §5, 안정성 10점)
#
#   scripts/11-fault-inject.sh <engine> <F1|F2|F3|F4|F5|F6> [docker|k8s]
#
#   모든 시나리오는 지속 부하 인가 상태에서 수행한다 (무부하 장애 테스트는 무의미).
#   스크립트는 다운타임을 헬스 폴링으로 자동 측정하고, 판정(verdict)은 검토자가 채운다.
. "$(dirname "$0")/lib/common.sh"
require_env; require_venv

ENGINE="${1:?engine (trino|starrocks)}"
SCENARIO="${2:?F1~F6}"
DRIVER="${3:-docker}"
LOAD_USERS="${FAULT_LOAD_USERS:-10}"
TOTAL_SEC="${FAULT_TOTAL_SEC:-180}"
INJECT_AT="${FAULT_INJECT_AT:-30}"

case "$ENGINE" in
  trino)     HEALTH="http://${TRINO_HOST}:${TRINO_PORT}/v1/info" ;;
  starrocks) HEALTH="http://${SR_HOST}:${SR_HTTP_PORT}/api/health" ;;
  *) die "알 수 없는 엔진: $ENGINE" ;;
esac

# --- 시나리오별 주입 명령 ---------------------------------------------------
inject() {
  case "$SCENARIO" in
    F1)  # 연산 노드 1대 다운
      case "$ENGINE-$DRIVER" in
        trino-docker)     docker kill srtr-bench-trino-worker-1-1 ;;
        starrocks-docker) docker kill srtr-bench-starrocks-be-1-1 ;;
        trino-k8s)        kubectl delete pod -l app=trino,role=worker --field-selector status.phase=Running --wait=false | head -1 ;;
        starrocks-k8s)    kubectl delete pod starrocks-be-0 --wait=false ;;
      esac ;;
    F2)  # 제어 노드 리더 다운
      case "$ENGINE-$DRIVER" in
        trino-docker)     docker kill srtr-bench-trino-coordinator-1 ;;
        starrocks-docker) docker kill srtr-bench-starrocks-fe-1 ;;
        trino-k8s)        kubectl delete pod -l app=trino,role=coordinator --wait=false ;;
        starrocks-k8s)    kubectl delete pod starrocks-fe-0 --wait=false ;;
      esac ;;
    F3)  # 메타스토어 / 카탈로그 다운
      [[ "$DRIVER" == "docker" ]] && docker kill srtr-bench-iceberg-rest-1 \
        || kubectl delete pod -l app=iceberg-rest --wait=false ;;
    F4)  # 오브젝트 스토리지 장애
      [[ "$DRIVER" == "docker" ]] && docker network disconnect srtr-bench srtr-bench-minio-1 \
        || kubectl delete pod -l app=minio --wait=false ;;
    F5)  # 노드 네트워크 분리
      case "$ENGINE-$DRIVER" in
        trino-docker)     docker network disconnect srtr-bench srtr-bench-trino-worker-2-1 ;;
        starrocks-docker) docker network disconnect srtr-bench srtr-bench-starrocks-be-2-1 ;;
        *) warn "F5 는 대상 환경에 맞춰 직접 주입할 것 (디스크 고갈/네트워크 분리)" ;;
      esac ;;
    F6)  # 폭주 쿼리 (OOM 유발) - 다른 쿼리가 영향을 받는지가 관찰 포인트
      ( cd "$ROOT" && FAULT_ENGINE="$ENGINE" "$PY" -m bench.runaway_query ) &
      ;;
    *) die "알 수 없는 시나리오: $SCENARIO" ;;
  esac
}

banner "11 장애 주입 $SCENARIO - $ENGINE (driver=$DRIVER)"
STAMP="$(date +%Y%m%d-%H%M%S)"
PROBE="$ROOT/results/operability/probe_${ENGINE}_${SCENARIO}_${STAMP}.csv"
mkdir -p "$(dirname "$PROBE")"
echo "epoch,available" > "$PROBE"

log "지속 부하 인가 (동시 ${LOAD_USERS} 사용자, ${TOTAL_SEC}s)"
cd "$ROOT"
"$PY" -m bench.run_concurrency --engine "$ENGINE" --track B \
      --users "$LOAD_USERS" --duration "$TOTAL_SEC" --warmup 0 \
      > "$ROOT/results/operability/load_${ENGINE}_${SCENARIO}_${STAMP}.log" 2>&1 &
LOAD_PID=$!

log "헬스 폴링 시작 (${HEALTH})"
( END=$(( $(date +%s) + TOTAL_SEC ))
  while [[ $(date +%s) -lt $END ]]; do
    if curl -sf --max-time 2 "$HEALTH" >/dev/null 2>&1; then echo "$(date +%s),1"; else echo "$(date +%s),0"; fi
    sleep 1
  done ) >> "$PROBE" &
PROBE_PID=$!

log "${INJECT_AT}s 후 장애 주입"
sleep "$INJECT_AT"
INJECT_TS=$(date +%s)
inject || warn "주입 명령이 실패했다 (대상 컨테이너명을 확인할 것: docker ps)"
log "주입 완료 (epoch=$INJECT_TS)"

wait "$PROBE_PID" 2>/dev/null || true
wait "$LOAD_PID" 2>/dev/null || true

log "다운타임 산출"
awk -F, -v inj="$INJECT_TS" '
  NR>1 && $2==0 { if (start=="") start=$1; last=$1; total++ }
  NR>1 && $2==1 && start!="" { if (last-start+1 > maxdown) maxdown=last-start+1; start=""; }
  END {
    if (start!="" && last-start+1 > maxdown) maxdown=last-start+1;
    printf "  주입 시각 epoch      : %s\n", inj;
    printf "  불가용 폴링 샘플 수  : %d\n", total+0;
    printf "  최대 연속 다운타임   : %d s\n", maxdown+0;
  }' "$PROBE"

OUT="$ROOT/results/operability/fault_injection.csv"
[[ -f "$OUT" ]] || echo "code,engine,verdict,downtime_sec,running_query,new_query,data_loss,manual_intervention,error_message_quality,note" > "$OUT"
DOWN=$(awk -F, 'NR>1 && $2==0 {c++} END {print c+0}' "$PROBE")
echo "${SCENARIO},${ENGINE},,${DOWN},,,,,,probe=${PROBE##*/}" >> "$OUT"

cat <<NOTE

  기록: $OUT
  아래 열을 직접 채울 것 (docs/06 §5.2):
    verdict  : 무중단+쿼리보존 | 무중단+쿼리실패 | 자동복구+일시중단 | 수동개입필요 | 데이터유실
    running_query / new_query / data_loss / manual_intervention / error_message_quality

  부하 로그: results/operability/load_${ENGINE}_${SCENARIO}_${STAMP}.log
  복구: scripts/01-env-up.sh $ENGINE   (F4/F5 는 docker network connect 로 원복)

  데이터 유실이 확인되면 결격 조건 K3 에 해당한다. 즉시 보고할 것.
NOTE
