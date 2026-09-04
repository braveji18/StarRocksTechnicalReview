#!/usr/bin/env bash
# P1 단일 쿼리 지연 (docs/05 §P1)
#   scripts/06-run-p1.sh <engine> <track> <cold|warm> [suite]
#   예: scripts/06-run-p1.sh starrocks B warm tpch
. "$(dirname "$0")/lib/common.sh"
require_env; require_venv

ENGINE="${1:?engine (trino|starrocks)}"
TRACK="${2:-A}"
CACHE="${3:-warm}"
SUITE="${4:-tpch}"

banner "06 P1 지연 측정 - $ENGINE / Track $TRACK / $CACHE / $SUITE"
[[ "$CACHE" == "cold" ]] && cold_prepare "$ENGINE"

cd "$ROOT"
"$PY" -m bench.run_latency --engine "$ENGINE" --track "$TRACK" \
      --cache "$CACHE" --suite "$SUITE"
