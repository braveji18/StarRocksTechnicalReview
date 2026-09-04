#!/usr/bin/env bash
# 적재 검증 (docs/03 §5). 불일치 시 종료코드 1 - 성능 측정으로 진행 금지.
. "$(dirname "$0")/lib/common.sh"
require_env; require_venv
banner "04 적재 검증 (행 수 / 체크섬 대조)"
cd "$ROOT"
"$PY" -m bench.verify_dataset "$@"
