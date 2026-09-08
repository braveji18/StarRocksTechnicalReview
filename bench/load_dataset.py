"""데이터셋 생성/적재 (docs/03).

단계별 소요 시간을 results/dataset/load_timing.csv 에 기록한다.
이 값이 P5 적재 성능 측정의 입력이 된다.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

from . import config, engines, resultio, sqlfile


# 리다이렉트 시에도 진행 상황이 바로 보이도록 (장시간 적재/측정 대비)
sys.stdout.reconfigure(line_buffering=True)

DDL = config.SQL_DIR / "ddl"

TRINO_STEPS = [
    ("iceberg-tpch", "10-trino-iceberg-tpch.sql"),
    ("dashboard-flat", "12-trino-dashboard-flat.sql"),
    ("analyze", "13-trino-analyze.sql"),
]
TRINO_OPTIONAL = {
    "normalize": "11-trino-normalize-files.sql",
    "preagg": "31-trino-preagg.sql",
}
SR_STEPS = [
    ("external-catalog", "20-starrocks-external-catalog.sql"),
    ("native-ddl", "21-starrocks-native-tpch.sql"),
    ("native-load", "22-starrocks-native-load.sql"),
    ("analyze", "23-starrocks-analyze.sql"),
]
SR_OPTIONAL = {"mv": "30-starrocks-mv.sql"}


def _run_file(engine: engines.Engine, step: str, filename: str,
              rows: list, timeout: int) -> bool:
    path = DDL / filename
    statements = sqlfile.load_template(path)
    ok_all = True
    for idx, stmt in enumerate(statements, 1):
        started = time.perf_counter()
        res = engine.execute(stmt, timeout_sec=timeout, fetch=False)
        elapsed = (time.perf_counter() - started) * 1000
        head = " ".join(stmt.split())[:80]
        rows.append([resultio.now(), engine.name, step, filename, idx, head,
                     round(elapsed, 1), res.status, res.error[:300]])
        marker = "OK " if res.ok else "FAIL"
        print(f"  [{marker}] {step}/{idx:02d} {elapsed/1000:7.1f}s  {head}")
        if not res.ok:
            ok_all = False
            print(f"         -> {res.error[:300]}")
    return ok_all


def main() -> int:
    ap = argparse.ArgumentParser(description="데이터셋 생성 및 적재")
    ap.add_argument("--engine", choices=["trino", "starrocks", "both"], default="both")
    ap.add_argument("--normalize", action="store_true",
                    help="파일 크기 정규화 실행 (docs/03 §2.1)")
    ap.add_argument("--preagg", action="store_true",
                    help="Track B 사전 계산 생성 (StarRocks MV + Trino 사전집계 테이블). "
                         "두 엔진에 반드시 함께 적용해야 대칭성이 유지된다.")
    ap.add_argument("--skip-external-catalog", action="store_true",
                    help="StarRocks 외부 카탈로그 생성을 건너뛴다. 이미 등록된 카탈로그를 "
                         "재사용할 때 사용 (DDL 이 DROP CATALOG 를 포함하므로 기존 랩에서는 필수)")
    ap.add_argument("--timeout", type=int, default=7200)
    args = ap.parse_args()

    rows: list[list] = []
    failed = False

    if args.engine in ("trino", "both"):
        print(f"[Trino] 데이터 생성 (SF={config.get('SCALE_FACTOR')}, "
              f"schema={config.get('LAKE_SCHEMA')})")
        with engines.TrinoEngine(track=engines.TRACK_A) as eng:
            eng.ping()
            steps = list(TRINO_STEPS)
            if args.normalize:
                steps.insert(1, ("normalize", TRINO_OPTIONAL["normalize"]))
            if args.preagg:
                steps.append(("preagg", TRINO_OPTIONAL["preagg"]))
            for step, fname in steps:
                if not _run_file(eng, step, fname, rows, args.timeout):
                    failed = True

    if args.engine in ("starrocks", "both"):
        print(f"[StarRocks] 외부 카탈로그 등록 및 네이티브 적재 "
              f"(db={config.get('SR_NATIVE_DB')})")
        with engines.StarRocksEngine(track=engines.TRACK_RAW) as eng:
            eng.ping()
            steps = list(SR_STEPS)
            if args.skip_external_catalog:
                steps = [s for s in steps if s[0] != "external-catalog"]
                print("  외부 카탈로그 생성 건너뜀 "
                      f"(기존 {config.get('SR_EXTERNAL_CATALOG')} 재사용)")
            if args.preagg:
                steps.append(("mv", SR_OPTIONAL["mv"]))
            for step, fname in steps:
                if not _run_file(eng, step, fname, rows, args.timeout):
                    failed = True

    out = resultio.results_path("dataset", "load_timing.csv")
    resultio.append_csv(out, ["ts", "engine", "step", "file", "stmt_no",
                              "statement", "elapsed_ms", "status", "error"], rows)
    print(f"\n적재 타이밍 기록: {out}")
    if failed:
        print("일부 단계가 실패했다. 위 FAIL 항목을 해결한 뒤 재실행할 것.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
