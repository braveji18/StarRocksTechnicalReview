#!/usr/bin/env bash
# 기능 체크리스트 실행 (docs/04)
#   scripts/05-run-functional.sh [--engine both] [--track B] [--filter F-3]
. "$(dirname "$0")/lib/common.sh"
require_env; require_venv
banner "05 기능 체크리스트"
cd "$ROOT"
"$PY" -m bench.run_functional "$@"
cat <<'NOTE'

  MANUAL 항목은 사람이 판정해야 한다.
  results/functional/functional_checklist.csv 의 verdict/score 를 직접 채운 뒤
  scripts/12-score.sh 를 실행할 것. (지원=2 / 부분지원=1 / 미지원=0)
NOTE
