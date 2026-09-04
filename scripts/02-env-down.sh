#!/usr/bin/env bash
# 로컬 스택 중지. --purge 지정 시 데이터 볼륨까지 삭제한다.
. "$(dirname "$0")/lib/common.sh"
require_env
banner "02 환경 중지"

if [[ "${1:-}" == "--purge" ]]; then
  warn "볼륨을 포함해 전부 삭제한다 (적재 데이터 소실)."
  read -r -p "정말 진행하는가? [yes/N] " ans
  [[ "$ans" == "yes" ]] || die "취소됨"
  "${COMPOSE[@]}" --profile lake --profile trino --profile starrocks --profile monitoring down -v
else
  "${COMPOSE[@]}" --profile lake --profile trino --profile starrocks --profile monitoring down
fi
log "중지 완료"
