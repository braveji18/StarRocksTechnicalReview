"""F6 폭주 쿼리 주입 (docs/06 §5).

의도적으로 메모리를 고갈시키는 쿼리를 실행한다.
관찰 포인트는 "이 쿼리가 실패하는가"가 아니라
"이 쿼리 때문에 다른 쿼리/클러스터가 영향을 받는가"이다.
"""
from __future__ import annotations

import os

from . import engines

RUNAWAY_SQL = (
    "select count(*) from lineitem a, lineitem b "
    "where a.l_orderkey % 97 = b.l_orderkey % 97"
)


def main() -> int:
    engine_name = os.environ.get("FAULT_ENGINE", "trino")
    track = os.environ.get("FAULT_TRACK", engines.TRACK_B)
    print(f"  [F6] 폭주 쿼리 주입: {engine_name} (track={track})")
    with engines.make(engine_name, track=track) as eng:
        res = eng.execute(RUNAWAY_SQL, timeout_sec=300)
        print(f"  [F6] 결과: {res.status} {res.error[:300]}")
        print("  [F6] 판정 기준 - 이 쿼리만 실패했는가, 아니면 다른 쿼리도 영향을 받았는가")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
