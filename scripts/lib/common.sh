#!/usr/bin/env bash
# 모든 스크립트가 source 하는 공통 함수/변수
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_DIR="$ROOT/env"
ENV_FILE="$ENV_DIR/.env"
VENV="$ROOT/.venv"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$ENV_DIR/docker-compose.yml")

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

require_env() {
  [[ -f "$ENV_FILE" ]] || die "env/.env 가 없다. 'cp env/.env.example env/.env' 후 값을 확인할 것."
  set -a; . "$ENV_FILE"; set +a
}

PYLIBS="$ROOT/.pylibs"

# 측정 하네스 실행용 파이썬을 결정한다.
#   1순위: .venv (python3-venv 가 있는 환경)
#   2순위: .pylibs (venv 를 만들 수 없는 환경에서 --target 설치한 의존성)
require_venv() {
  if [[ -x "$VENV/bin/python" ]]; then
    PY="$VENV/bin/python"
  elif [[ -d "$PYLIBS" ]]; then
    PY="python3"
    export PYTHONPATH="$PYLIBS${PYTHONPATH:+:$PYTHONPATH}"
  else
    die "측정 하네스 의존성이 없다. 먼저 scripts/00-preflight.sh 를 실행할 것."
  fi
}

# 엔진 접속 대기
wait_for_http() {
  local url="$1" name="$2" tries="${3:-60}"
  for ((i=1; i<=tries; i++)); do
    if curl -sf "$url" >/dev/null 2>&1; then log "$name 준비 완료"; return 0; fi
    sleep 5
  done
  die "$name 가 준비되지 않았다: $url"
}

wait_for_starrocks() {
  require_venv
  for ((i=1; i<=60; i++)); do
    if "$PY" - <<'PY' >/dev/null 2>&1
import sys
sys.path.insert(0, ".")
from bench import config
import pymysql
pymysql.connect(host=config.get("SR_HOST"), port=config.get_int("SR_PORT"),
                user=config.get("SR_USER"), password=config.get("SR_PASSWORD"),
                connect_timeout=5).close()
PY
    then log "StarRocks FE 준비 완료"; return 0; fi
    sleep 5
  done
  die "StarRocks FE 에 접속할 수 없다 ($SR_HOST:$SR_PORT)"
}

# ---------------------------------------------------------------------------
# 콜드 캐시 준비 (docs/05 §2)
#   측정 오염을 막기 위해 엔진 재시작 + OS 페이지 캐시 드롭을 수행한다.
#   페이지 캐시 드롭은 root 권한이 필요하므로 ALLOW_DROP_CACHES=1 일 때만 시도하고,
#   실패하면 그 사실을 경고로 남긴다 (측정 기록에 반영할 것).
# ---------------------------------------------------------------------------
cold_prepare() {
  local engine="$1"
  log "콜드 캐시 준비: $engine"
  case "$engine" in
    trino)     "${COMPOSE[@]}" --profile trino restart >/dev/null 2>&1 || warn "Trino 재시작 실패(원격 클러스터?)" ;;
    starrocks) "${COMPOSE[@]}" --profile starrocks restart >/dev/null 2>&1 || warn "StarRocks 재시작 실패(원격 클러스터?)" ;;
  esac
  if [[ "${ALLOW_DROP_CACHES:-0}" == "1" ]]; then
    if sudo -n sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null; then
      log "OS 페이지 캐시 드롭 완료"
    else
      warn "OS 페이지 캐시 드롭 실패 (sudo 불가). 콜드 조건이 불완전함을 결과표에 기록할 것."
    fi
  else
    warn "ALLOW_DROP_CACHES=1 이 아니므로 페이지 캐시를 드롭하지 않았다. 콜드 조건 불완전."
  fi
  sleep 20
}

banner() {
  echo
  echo "==============================================================="
  echo "  $*"
  echo "==============================================================="
}
