#!/usr/bin/env bash
# 데이터셋 생성/적재 (docs/03)
#   scripts/03-load-dataset.sh [--normalize] [--preagg] [--engine trino|starrocks|both]
. "$(dirname "$0")/lib/common.sh"
require_env; require_venv
banner "03 데이터셋 적재 (SF=${SCALE_FACTOR}, schema=${LAKE_SCHEMA})"
cd "$ROOT"
"$PY" -m bench.load_dataset "$@"
log "다음 단계: scripts/04-verify-dataset.sh"
