#!/usr/bin/env bash
# 규모별 프로파일을 env/.env 에 병합한다 (docs/10).
#
#   scripts/13-apply-profile.sh <smoke|small|medium|large> [--show]
#
# 프로파일이 가진 키만 덮어쓴다. 접속 정보(호스트/포트/자격증명)는 건드리지 않는다.
# 엔진 쪽 메모리·CPU 는 여기서 바꾸지 않는다 — docs/10 §4 참조.
. "$(dirname "$0")/lib/common.sh"

PROFILE="${1:?프로파일 이름 (smoke|small|medium|large)}"
SRC="$ENV_DIR/profiles/${PROFILE}.env"
[[ -f "$SRC" ]] || die "프로파일이 없다: $SRC"

banner "13 프로파일 적용: $PROFILE"

if [[ "${2:-}" == "--show" ]]; then
  grep -vE '^\s*(#|$)' "$SRC"
  exit 0
fi

[[ -f "$ENV_FILE" ]] || cp "$ENV_DIR/.env.example" "$ENV_FILE"
BACKUP="$ENV_FILE.bak.$(date +%Y%m%d-%H%M%S)"
cp "$ENV_FILE" "$BACKUP"

python3 - "$ENV_FILE" "$SRC" <<'PY'
import re, sys
env_path, src_path = sys.argv[1], sys.argv[2]

def parse(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip()
    return out

new = parse(src_path)
lines = open(env_path, encoding="utf-8").read().splitlines()
seen, out = set(), []
for line in lines:
    m = re.match(r"^([A-Z_][A-Z0-9_]*)=", line.strip())
    if m and m.group(1) in new:
        key = m.group(1)
        seen.add(key)
        out.append(f"{key}={new[key]}")
    else:
        out.append(line)
missing = [k for k in new if k not in seen]
if missing:
    out.append("")
    out.append(f"# --- 프로파일에서 추가된 값 ---")
    out += [f"{k}={new[k]}" for k in missing]
open(env_path, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"  적용 {len(seen)}건, 추가 {len(missing)}건")
PY

log "백업: $BACKUP"
require_env
cat <<NOTE

  적용된 규모 설정:
    SCALE_FACTOR      = ${SCALE_FACTOR}   (TPCH_SCHEMA=${TPCH_SCHEMA:-sf${SCALE_FACTOR}})
    PARTITION_GRAIN   = ${PARTITION_GRAIN}
    SR_BUCKETS_FACT   = ${SR_BUCKETS_FACT}   SR_BUCKETS_DIM = ${SR_BUCKETS_DIM}
    SR_REPLICAS       = ${SR_REPLICAS}
    P3_USERS          = ${P3_USERS}
    SLA p95           = ${SLA_DASHBOARD_P95_MS} ms

  엔진 쪽 메모리·CPU 는 이 스크립트가 바꾸지 않는다.
  docs/10-scaling-guide.md §4 의 표대로 배포 도구에서 직접 설정한 뒤,
  §5 의 대칭성 검증을 통과해야 측정에 들어갈 수 있다.
NOTE
