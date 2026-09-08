"""기능 체크리스트 실행 (docs/04).

판정: 표준 SQL 성공 -> 지원(2) / 우회 SQL 성공 -> 부분지원(1) / 모두 실패 -> 미지원(0)
mode=manual 항목은 판정란을 비운 채 행만 생성한다. 검토자가 직접 채운다.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import config, engines, resultio, sqlfile


# 리다이렉트 시에도 진행 상황이 바로 보이도록 (장시간 적재/측정 대비)
sys.stdout.reconfigure(line_buffering=True)

CHECK_DIR = config.SQL_DIR / "functional"


def run_one(eng: engines.Engine, check: sqlfile.Check, timeout: int) -> tuple[str, int, str]:
    if check.manual:
        return ("MANUAL", -1, "검토자 직접 판정 필요")

    statements = sqlfile.split_statements(check.sql)
    last_err = ""
    for stmt in statements:
        res = eng.execute(stmt, timeout_sec=timeout)
        if not res.ok:
            last_err = res.error
            break
    else:
        return ("지원", 2, "")

    fb = check.fallback_for(eng.name)
    if fb:
        for stmt in sqlfile.split_statements(fb):
            res = eng.execute(stmt, timeout_sec=timeout)
            if not res.ok:
                return ("미지원", 0, f"표준: {last_err[:200]} / 우회: {res.error[:200]}")
        return ("부분지원", 1, f"표준 문법 실패, 엔진 고유 문법으로 동작. 표준 오류: {last_err[:200]}")

    return ("미지원", 0, last_err[:400])


def main() -> int:
    ap = argparse.ArgumentParser(description="기능 체크리스트 실행")
    ap.add_argument("--engine", choices=["trino", "starrocks", "both"], default="both")
    ap.add_argument("--track", default=engines.TRACK_B,
                    help="기능 검증 기본 트랙. StarRocks 는 네이티브(B)에서 전 기능을 노출한다")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--filter", default="",
                    help="체크 ID 부분 일치 필터. 쉼표로 여러 개 (예: F-0,F-1)")
    args = ap.parse_args()

    checks = sqlfile.load_all_checks(CHECK_DIR)
    if args.filter:
        pats = [p.strip() for p in args.filter.split(",") if p.strip()]
        checks = [c for c in checks if any(p in c.check_id for p in pats)]
    if not checks:
        print("실행할 체크가 없다.")
        return 1

    targets = ["trino", "starrocks"] if args.engine == "both" else [args.engine]
    rows = []
    for name in targets:
        print(f"\n=== {name} 기능 체크 (track={args.track}) ===")
        with engines.make(name, track=args.track) as eng:
            eng.ping()
            for check in checks:
                if check.engine and check.engine != name:
                    continue
                verdict, score, note = run_one(eng, check, args.timeout)
                rows.append([check.check_id, check.category, check.description,
                             name, args.track,
                             verdict, "" if score < 0 else score,
                             note.replace("\n", " ")[:400], check.source])
                print(f"  {check.check_id:6s} {verdict:6s} {check.description}")

    out = resultio.results_path("functional", "functional_checklist.csv")
    resultio.write_csv(out, ["check_id", "category", "description", "engine",
                             "track", "verdict", "score", "note", "source"], rows)

    manual = sum(1 for r in rows if r[5] == "MANUAL")
    print(f"\n결과: {out}")
    print(f"총 {len(rows)}행 (자동 판정 {len(rows) - manual}, 수동 판정 필요 {manual})")
    if manual:
        print("MANUAL 항목의 verdict/score 를 직접 채운 뒤 채점 스크립트를 실행할 것.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
