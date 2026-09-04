"""적재 검증 (docs/03 §5).

두 엔진 x 두 트랙에서 행 수와 값 체크섬을 대조한다.
불일치가 하나라도 있으면 종료코드 1 - 성능 측정으로 진행해서는 안 된다.
"""
from __future__ import annotations

import argparse
from decimal import Decimal

from . import engines, resultio

TABLES = ["lineitem", "orders", "customer", "part",
          "partsupp", "supplier", "nation", "region"]

CHECKSUM_SQL = {
    "lineitem": """select count(*), sum(l_quantity), sum(l_extendedprice),
                          min(l_shipdate), max(l_shipdate) from lineitem""",
    "orders": """select count(*), sum(o_totalprice), sum(o_custkey),
                        min(o_orderdate), max(o_orderdate) from orders""",
    "customer": "select count(*), sum(c_acctbal), sum(c_nationkey), min(c_name), max(c_name) from customer",
    "part": "select count(*), sum(p_retailprice), sum(p_size), min(p_brand), max(p_brand) from part",
    "partsupp": "select count(*), sum(ps_supplycost), sum(ps_availqty), min(ps_partkey), max(ps_partkey) from partsupp",
    "supplier": "select count(*), sum(s_acctbal), sum(s_nationkey), min(s_name), max(s_name) from supplier",
    "nation": "select count(*), sum(n_nationkey), sum(n_regionkey), min(n_name), max(n_name) from nation",
    "region": "select count(*), sum(r_regionkey), 0, min(r_name), max(r_name) from region",
}


def _normalize(value):
    """엔진 간 타입 표현 차이(Decimal/float/date)를 비교 가능한 형태로 정규화."""
    if value is None:
        return None
    if isinstance(value, (Decimal, float, int)):
        return f"{Decimal(str(value)):.2f}"
    return str(value)


def collect(engine_name: str, track: str) -> dict[str, tuple]:
    out: dict[str, tuple] = {}
    with engines.make(engine_name, track=track) as eng:
        eng.ping()
        for table in TABLES:
            res = eng.execute(CHECKSUM_SQL[table], timeout_sec=1800)
            if not res.ok or not res.rows:
                out[table] = ("ERROR", res.error[:200], "", "", "")
            else:
                out[table] = tuple(_normalize(v) for v in res.rows[0])
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="적재 검증 (행 수 / 체크섬 대조)")
    ap.add_argument("--tracks", default="A,B",
                    help="검증할 트랙 (기본 A,B). Track B 는 StarRocks 네이티브 적재 이후 유효")
    args = ap.parse_args()

    rows, mismatches = [], 0
    for track in [t.strip() for t in args.tracks.split(",") if t.strip()]:
        print(f"\n=== Track {track} 검증 ===")
        trino = collect("trino", engines.TRACK_A)  # Trino 는 트랙과 무관하게 동일 레이크
        sr = collect("starrocks", track)
        for table in TABLES:
            t, s = trino[table], sr[table]
            match = t == s
            if not match:
                mismatches += 1
            rows.append([track, table,
                         t[0], s[0], t[1], s[1], t[2], s[2], t[3], s[3], t[4], s[4],
                         "MATCH" if match else "MISMATCH"])
            flag = "OK " if match else "!! "
            print(f"  [{flag}] {table:10s} trino={t}  starrocks={s}")

    out = resultio.results_path("functional", "dataset_verification.csv")
    resultio.write_csv(out, [
        "track", "table",
        "trino_cnt", "sr_cnt", "trino_sum1", "sr_sum1", "trino_sum2", "sr_sum2",
        "trino_min", "sr_min", "trino_max", "sr_max", "verdict"], rows)
    print(f"\n검증 결과: {out}")

    if mismatches:
        print(f"\n불일치 {mismatches}건. 두 엔진이 동일 데이터를 보고 있지 않다.")
        print("DECIMAL 합계 불일치는 타입 매핑 차이를 먼저 조사할 것 (docs/03 §5.2).")
        print("성능 측정으로 진행하지 말 것.")
        return 1
    print("\n전 테이블 일치. 성능 측정으로 진행 가능.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
