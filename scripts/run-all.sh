#!/usr/bin/env bash
# PoC 전체 파이프라인 (README §5)
#
#   scripts/run-all.sh smoke    로컬 스모크 스택으로 스크립트 동작만 검증 (SF=1)
#   scripts/run-all.sh measure  실 클러스터 측정 (env/.env 호스트를 실 클러스터로 지정)
#
# 자동화하지 않는 것: 확장성(10), 장애 주입(11), 비용 산정.
# 사람의 판단과 개입이 필요하므로 개별 스크립트로 수행한다.
. "$(dirname "$0")/lib/common.sh"

MODE="${1:-smoke}"
banner "PoC 파이프라인 ($MODE)"

"$ROOT/scripts/00-preflight.sh"
require_env

if [[ "$MODE" == "smoke" ]]; then
  "$ROOT/scripts/01-env-up.sh" all
fi

"$ROOT/scripts/03-load-dataset.sh" --normalize --preagg
"$ROOT/scripts/04-verify-dataset.sh" || die "적재 검증 실패. 성능 측정으로 진행하지 않는다 (docs/03 §5)."
"$ROOT/scripts/05-run-functional.sh"

for eng in trino starrocks; do
  for track in A B; do
    "$ROOT/scripts/06-run-p1.sh" "$eng" "$track" warm tpch
    "$ROOT/scripts/07-run-p2.sh" "$eng" "$track"
  done
done

if [[ "$MODE" == "measure" ]]; then
  for eng in trino starrocks; do
    for track in A B; do
      "$ROOT/scripts/06-run-p1.sh" "$eng" "$track" cold tpch
      "$ROOT/scripts/08-run-p3.sh" "$eng" "$track"
      "$ROOT/scripts/09-run-p6.sh" "$eng" "$track"
    done
  done
else
  log "smoke 모드: 콜드 측정 / 동시성 / 자원 효율은 건너뛴다"
fi

"$ROOT/scripts/12-score.sh" --primary-track B

cat <<'NOTE'

  남은 수동 단계:
    scripts/10-scalability.sh   확장성 (배점 10)
    scripts/11-fault-inject.sh  장애 주입 F1~F6 (배점 10)
    results/templates/          운영성·비용·결격 조건 입력 후 12-score.sh 재실행
NOTE
