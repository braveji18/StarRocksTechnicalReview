#!/usr/bin/env bash
# 로컬 스모크 스택 기동 (docs/02)
#   사용: scripts/01-env-up.sh [all|trino|starrocks|lake|monitoring]
#   실 클러스터 측정 시에는 이 스크립트를 쓰지 않고 env/.env 의 호스트만 바꾼다.
. "$(dirname "$0")/lib/common.sh"
require_env

TARGET="${1:-all}"
banner "01 환경 기동 ($TARGET)"

case "$TARGET" in
  all)        PROFILES=(--profile lake --profile trino --profile starrocks --profile monitoring) ;;
  trino)      PROFILES=(--profile lake --profile trino) ;;
  starrocks)  PROFILES=(--profile lake --profile starrocks) ;;
  lake)       PROFILES=(--profile lake) ;;
  monitoring) PROFILES=(--profile monitoring) ;;
  *) die "알 수 없는 대상: $TARGET" ;;
esac

"${COMPOSE[@]}" "${PROFILES[@]}" up -d

if [[ "$TARGET" == "all" || "$TARGET" == "lake" || "$TARGET" == "trino" || "$TARGET" == "starrocks" ]]; then
  wait_for_http "http://localhost:8181/v1/config" "Iceberg REST Catalog" 40 || true
fi

if [[ "$TARGET" == "all" || "$TARGET" == "trino" ]]; then
  wait_for_http "http://${TRINO_HOST}:${TRINO_PORT}/v1/info" "Trino Coordinator"
fi

if [[ "$TARGET" == "all" || "$TARGET" == "starrocks" ]]; then
  wait_for_starrocks
  log "StarRocks BE 등록 확인/수행"
  require_venv
  cd "$ROOT" && "$PY" - <<'PY'
from bench import config, engines
with engines.StarRocksEngine(track=engines.TRACK_RAW) as eng:
    res = eng.execute("SHOW BACKENDS")
    known = {str(r[1]) for r in res.rows} if res.ok else set()
    for host in ("starrocks-be-1", "starrocks-be-2"):
        if host in known:
            print(f"  이미 등록됨: {host}")
            continue
        r = eng.execute(f"ALTER SYSTEM ADD BACKEND '{host}:9050'", fetch=False)
        print(f"  ADD BACKEND {host}: {'OK' if r.ok else r.error[:160]}")
PY
fi

log "기동 완료. 상태 확인: docker compose -f env/docker-compose.yml ps"
