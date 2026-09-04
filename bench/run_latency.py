"""P1 단일 쿼리 지연 / P2 대시보드 응답 측정 (docs/05 §P1, §P2).

원칙:
  - 캐시 상태(cold/warm)를 반드시 기록한다. 미기록 측정값은 무효 (docs/05 §2).
  - warm 은 선행 2회 실행 후 N회 측정, 중앙값 채택.
  - 실패 쿼리는 제외하지 않고 타임아웃 값을 대입한 뒤 status 에 표기한다 (docs/01 §3.2).
  - 대표값은 기하평균 (산술평균은 장시간 쿼리에 지배됨).
"""
from __future__ import annotations

import argparse
from pathlib import Path

from . import config, engines, resultio, sqlfile

SUITES = {
    "tpch": ("tpch", config.SQL_DIR / "tpch"),
    "tpcds": ("tpcds", config.SQL_DIR / "tpcds"),
    "dashboard": ("dashboard", config.SQL_DIR / "dashboard"),
}


def measure(eng: engines.Engine, name: str, sql: str, repeat: int,
            warmup: int, timeout: int) -> dict:
    for _ in range(warmup):
        eng.execute(sql, timeout_sec=timeout)

    runs, status, error = [], "OK", ""
    scan_bytes = cpu_ms = peak_mem = None
    for _ in range(repeat):
        res = eng.execute(sql, timeout_sec=timeout)
        if res.ok:
            runs.append(res.elapsed_ms)
            scan_bytes = res.scan_bytes if res.scan_bytes is not None else scan_bytes
            cpu_ms = res.cpu_ms if res.cpu_ms is not None else cpu_ms
            peak_mem = res.peak_mem_bytes if res.peak_mem_bytes is not None else peak_mem
        else:
            # 실패는 타임아웃 값으로 대입한다 (평균에서 제외하지 않는다)
            runs.append(timeout * 1000.0)
            status, error = res.status, res.error[:300]

    return {
        "query": name,
        "runs": runs,
        "median_ms": resultio.median(runs),
        "min_ms": min(runs) if runs else float("nan"),
        "scan_bytes": scan_bytes,
        "cpu_ms": cpu_ms,
        "peak_mem_bytes": peak_mem,
        "status": status,
        "error": error,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="P1/P2 지연 측정")
    ap.add_argument("--engine", choices=["trino", "starrocks"], required=True)
    ap.add_argument("--track", choices=[engines.TRACK_A, engines.TRACK_B],
                    default=engines.TRACK_A)
    ap.add_argument("--suite", choices=list(SUITES), default="tpch")
    ap.add_argument("--cache", choices=["cold", "warm"], default="warm")
    ap.add_argument("--repeat", type=int, default=config.get_int("P1_REPEAT", 3))
    ap.add_argument("--timeout", type=int, default=config.get_int("P1_TIMEOUT_SEC", 600))
    ap.add_argument("--queries", default="", help="쉼표 구분 쿼리명 필터 (예: q01,q06)")
    ap.add_argument("--out", default="", help="출력 CSV 경로 (기본: results/performance/...)")
    args = ap.parse_args()

    bench_name, qdir = SUITES[args.suite]
    if not qdir.exists():
        print(f"쿼리 디렉터리가 없다: {qdir}")
        if args.suite == "tpcds":
            print("TPC-DS 쿼리는 저장소에 포함되지 않는다. "
                  "sql/tpcds/ 에 q01.sql~q99.sql 을 배치한 뒤 재실행할 것 (docs/09 참조).")
        return 1

    queries = sqlfile.load_query_set(qdir)
    if args.queries:
        wanted = {q.strip() for q in args.queries.split(",")}
        queries = [(n, s) for n, s in queries if n in wanted]
    if not queries:
        print("실행할 쿼리가 없다.")
        return 1

    # cold 는 캐시가 이미 비워진 상태를 전제로 하며 반복하지 않는다.
    repeat = 1 if args.cache == "cold" else args.repeat
    warmup = 0 if args.cache == "cold" else 2

    print(f"=== P-latency {args.engine} track={args.track} suite={args.suite} "
          f"cache={args.cache} repeat={repeat} ===")

    rows, medians = [], []
    with engines.make(args.engine, track=args.track) as eng:
        eng.ping()
        applied = eng.apply_cache_policy(cold=(args.cache == "cold"))
        cache_note = ";".join(applied) if applied else "none"
        for name, sql in queries:
            m = measure(eng, name, sql, repeat, warmup, args.timeout)
            r = m["runs"]
            rows.append([
                args.track, args.engine, args.cache, bench_name, name,
                round(r[0], 1) if len(r) > 0 else "",
                round(r[1], 1) if len(r) > 1 else "",
                round(r[2], 1) if len(r) > 2 else "",
                round(m["median_ms"], 1),
                ";".join(f"{v:.1f}" for v in r),
                m["scan_bytes"] if m["scan_bytes"] is not None else "",
                round(m["peak_mem_bytes"] / 1048576, 1) if m["peak_mem_bytes"] else "",
                round(m["cpu_ms"] / 1000, 2) if m["cpu_ms"] else "",
                m["status"], m["error"], cache_note, resultio.now(),
            ])
            medians.append(m["median_ms"])
            flag = "OK " if m["status"] == "OK" else m["status"]
            print(f"  {name:8s} {m['median_ms']:10.1f} ms  [{flag}]")

    out = Path(args.out) if args.out else resultio.results_path(
        "performance", f"p1_latency_{args.suite}.csv")
    out.parent.mkdir(parents=True, exist_ok=True)
    resultio.append_csv(out, [
        "track", "engine", "cache", "benchmark", "query",
        "run1_ms", "run2_ms", "run3_ms", "median_ms", "runs_ms",
        "scan_bytes", "peak_mem_mb", "cpu_sec", "status", "error",
        "cache_policy", "ts"], rows)

    gm = resultio.geomean(medians)
    failed = sum(1 for r in rows if r[13] != "OK")
    summary = [[args.track, args.engine, args.cache, bench_name,
                len(rows), round(gm, 1), round(sum(medians), 1), failed,
                round(resultio.percentile(medians, 0.95), 1), resultio.now()]]
    sp = resultio.results_path("performance", "p1_summary.csv")
    resultio.append_csv(sp, ["track", "engine", "cache", "benchmark",
                             "query_count", "geomean_ms", "total_ms",
                             "failed_queries", "p95_ms", "ts"], summary)

    print(f"\n기하평균 {gm:.1f} ms / 총합 {sum(medians)/1000:.1f} s / 실패 {failed}건")
    print(f"원시: {out}\n요약: {sp}")
    if args.cache == "warm" and args.suite == "dashboard":
        sla = config.get_int("SLA_DASHBOARD_P95_MS", 3000)
        p95 = resultio.percentile(medians, 0.95)
        verdict = "충족" if p95 <= sla else "미충족 (결격 조건 K2 검토 대상)"
        print(f"대시보드 p95 {p95:.0f} ms vs SLA {sla} ms -> {verdict}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
