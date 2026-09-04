#!/usr/bin/env bash
# 사전 점검 및 파이썬 측정 하네스 준비 (docs/02 §5)
. "$(dirname "$0")/lib/common.sh"

banner "00 사전 점검"

for cmd in docker curl python3; do
  command -v "$cmd" >/dev/null || die "필수 도구 없음: $cmd"
done
docker compose version >/dev/null 2>&1 || die "docker compose 플러그인이 필요하다"
log "필수 도구 확인 완료"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ENV_DIR/.env.example" "$ENV_FILE"
  log "env/.env 생성 (env/.env.example 복사). 값을 확인할 것."
fi
require_env

install_deps() {
  # 1순위: venv. python3-venv 가 없는 환경도 있으므로 실패를 허용한다.
  if [[ ! -x "$VENV/bin/python" ]]; then
    log "파이썬 가상환경 생성 시도: $VENV"
    if ! python3 -m venv "$VENV" >/dev/null 2>&1; then
      rm -rf "$VENV"
      warn "python3 -m venv 실패 (python3-venv 미설치로 추정)"
      warn "권장 조치: sudo apt install python3-venv"
      warn "대안으로 $PYLIBS 에 의존성을 직접 설치한다"
      mkdir -p "$PYLIBS"
      if ! pip3 install --quiet --target "$PYLIBS" -r "$ROOT/requirements.txt" 2>/dev/null; then
        pip3 install --quiet --target "$PYLIBS" --break-system-packages \
             -r "$ROOT/requirements.txt" \
          || die "의존성 설치 실패. python3-venv 를 설치한 뒤 다시 실행할 것."
      fi
      log "측정 하네스 의존성 설치 완료 (.pylibs)"
      return
    fi
  fi
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet -r "$ROOT/requirements.txt"
  log "측정 하네스 의존성 설치 완료 (.venv)"
}
install_deps

banner "고정된 버전 (docs/02 §3 - 검토 종료까지 변경 금지)"
printf '  Trino          : %s\n' "${TRINO_VERSION:-미설정}"
printf '  StarRocks      : %s\n' "${STARROCKS_VERSION:-미설정}"
printf '  Iceberg REST   : %s\n' "${ICEBERG_REST_VERSION:-미설정}"
printf '  Scale Factor   : %s\n' "${SCALE_FACTOR:-미설정}"
printf '  대시보드 SLA p95: %s ms\n' "${SLA_DASHBOARD_P95_MS:-미설정}"

banner "동일 조건 통제 체크리스트 (docs/02 §5)"
cat <<'CHK'
  측정 착수 전 아래를 확인하고 결과표에 서명 기록할 것.

  [ ] 두 엔진의 총 vCPU / 총 메모리가 동일한가
  [ ] 동일한 Iceberg 테이블(동일 스냅샷)을 조회하는가
  [ ] 파일 포맷/압축/파티셔닝/파일 크기 분포가 동일한가
  [ ] 양쪽 모두 ANALYZE 를 수행했는가
  [ ] 캐시 상태(콜드/웜)가 정의되어 있는가
  [ ] 부하 발생기가 엔진 노드와 분리되어 있는가
  [ ] Prometheus 수집 주기가 동일한가 (5s)
  [ ] 동시 실행 중인 타 워크로드가 없는가
  [ ] 모든 설정 파일이 저장소에 커밋되었는가

  이 체크리스트는 자동 판정할 수 없다. 사람이 확인해야 한다.
CHK
log "사전 점검 완료"
