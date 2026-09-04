"""P3 동시성 측정 (docs/05 §P3).

- 동시 사용자 수를 단계적으로 올리며 각 단계에서 지속 부하를 인가한다.
- 쿼리 혼합: 대시보드 70% / 분석 25% / 대용량 5%.
- 종료 조건: 에러율 5% 초과 또는 p95 가 SLA 의 3배 초과 시 해당 단계에서 중단.
- 포화점(QPS 가 더 이상 증가하지 않는 지점)을 산출한다.

부하 발생기는 엔진 노드와 분리된 장비에서 실행할 것 (docs/02 §2.1).
"""
from __future__ import annotations

import argparse
import random
import threading
import time
from dataclasses import dataclass

from . import config, engines, resultio, sqlfile

HEAVY_QUERIES = {"q09", "q21", "q18"}


@dataclass
class Sample:
    query: str
    elapsed_ms: float
    ok: bool


def build_mix() -> list[tuple[str, str, float]]:
    """(가중치 그룹, 쿼리명, SQL) 목록과 그룹별 선택 확률을 구성."""
    dashboard = sqlfile.load_query_set(config.SQL_DIR / "dashboard")
    tpch = sqlfile.load_query_set(config.SQL_DIR / "tpch")
    analytic = [(n, s) for n, s in tpch if n not in HEAVY_QUERIES]
    heavy = [(n, s) for n, s in tpch if n in HEAVY_QUERIES]

    pools = []
    if dashboard:
        pools.append((0.70, dashboard))
    if analytic:
        pools.append((0.25, analytic))
    if heavy:
        pools.append((0.05, heavy))
    if not pools:
        raise SystemExit("쿼리 풀이 비어 있다. sql/dashboard, sql/tpch 를 확인할 것.")
    total = sum(w for w, _ in pools)
    return [(w / total, pool) for w, pool in pools]


def pick(mix, rng: random.Random) -> tuple[str, str]:
    r = rng.random()
    acc = 0.0
    for weight, pool in mix:
        acc += weight
        if r <= acc:
            return rng.choice(pool)
    return rng.choice(mix[-1][1])


def worker(engine_name: str, track: str, mix, stop_at: float,
           measure_from: float, samples: list[Sample], lock: threading.Lock,
           timeout: int, seed: int) -> None:
    rng = random.Random(seed)
    local: list[Sample] = []
    try:
        with engines.make(engine_name, track=track) as eng:
            while time.time() < stop_at:
                name, sql = pick(mix, rng)
                res = eng.execute(sql, timeout_sec=timeout)
                if time.time() >= measure_from:
                    local.append(Sample(name, res.elapsed_ms, res.ok))
    except Exception as exc:  # 접속 자체가 실패한 경우도 기록되어야 한다
        local.append(Sample("connect", 0.0, False))
        print(f"  워커 오류: {exc}")
    with lock:
        samples.extend(local)


def run_level(engine_name: str, track: str, users: int, duration: int,
              warmup: int, timeout: int) -> dict:
    # 스레드 기동 전에 접속 가능 여부를 확인한다 (실패 시 즉시 중단)
    with engines.make(engine_name, track=track) as probe:
        probe.ping()
    mix = build_mix()
    samples: list[Sample] = []
    lock = threading.Lock()
    started = time.time()
    measure_from = started + warmup
    stop_at = measure_from + duration

    threads = [threading.Thread(
        target=worker,
        args=(engine_name, track, mix, stop_at, measure_from, samples, lock,
              timeout, 1000 + i),
        daemon=True) for i in range(users)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=duration + warmup + timeout + 60)

    ok = [s.elapsed_ms for s in samples if s.ok]
    total = len(samples)
    errors = total - len(ok)
    elapsed = max(time.time() - measure_from, 1e-9)
    return {
        "users": users,
        "total": total,
        "errors": errors,
        "error_rate": (errors / total) if total else 1.0,
        "qps": len(ok) / elapsed,
        "p50": resultio.percentile(ok, 0.50),
        "p95": resultio.percentile(ok, 0.95),
        "p99": resultio.percentile(ok, 0.99),
        "duration_sec": elapsed,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="P3 동시성 측정")
    ap.add_argument("--engine", choices=["trino", "starrocks"], required=True)
    ap.add_argument("--track", choices=[engines.TRACK_A, engines.TRACK_B],
                    default=engines.TRACK_A)
    ap.add_argument("--users", default=config.get("P3_USERS"),
                    help="쉼표 구분 동시 사용자 단계 (기본 1,5,10,20,50)")
    ap.add_argument("--duration", type=int, default=config.get_int("P3_DURATION_SEC", 600))
    ap.add_argument("--warmup", type=int, default=config.get_int("P3_WARMUP_SEC", 120))
    ap.add_argument("--timeout", type=int, default=300)
    args = ap.parse_args()

    sla = config.get_int("SLA_DASHBOARD_P95_MS", 3000)
    levels = [int(u) for u in args.users.split(",") if u.strip()]
    rows, results = [], []

    print(f"=== P3 동시성 {args.engine} track={args.track} "
          f"단계={levels} 측정 {args.duration}s (워밍업 {args.warmup}s) ===")
    for users in levels:
        print(f"\n[동시 {users} 사용자] 진행 중...")
        r = run_level(args.engine, args.track, users, args.duration,
                      args.warmup, args.timeout)
        results.append(r)
        rows.append([args.track, args.engine, users, round(r["duration_sec"] / 60, 2),
                     round(r["qps"], 3), round(r["p50"], 1), round(r["p95"], 1),
                     round(r["p99"], 1), round(r["error_rate"], 4),
                     r["total"], r["errors"], resultio.now()])
        print(f"  QPS {r['qps']:.2f}  p50 {r['p50']:.0f}ms  p95 {r['p95']:.0f}ms  "
              f"p99 {r['p99']:.0f}ms  에러율 {r['error_rate']*100:.2f}%")

        if r["error_rate"] > 0.05:
            print("  종료 조건: 에러율 5% 초과 - 이후 단계 중단")
            break
        if r["p95"] > sla * 3:
            print(f"  종료 조건: p95 가 SLA({sla}ms)의 3배 초과 - 이후 단계 중단")
            break

    out = resultio.results_path("performance", "p3_concurrency.csv")
    resultio.append_csv(out, ["track", "engine", "concurrent_users", "duration_min",
                              "qps", "p50_ms", "p95_ms", "p99_ms", "error_rate",
                              "total_queries", "errors", "ts"], rows)

    # 포화점: QPS 가 직전 단계 대비 5% 미만으로 증가하기 시작하는 지점
    saturation, best_qps = None, 0.0
    for r in results:
        if r["qps"] < best_qps * 1.05 and saturation is None and best_qps > 0:
            saturation = r["users"]
        best_qps = max(best_qps, r["qps"])
    sla_max = max((r["users"] for r in results if r["p95"] <= sla), default=0)

    summary = [[args.track, args.engine, saturation or "미도달",
                round(best_qps, 3), sla_max, sla, resultio.now()]]
    sp = resultio.results_path("performance", "p3_summary.csv")
    resultio.append_csv(sp, ["track", "engine", "saturation_users", "peak_qps",
                             "sla_max_users", "sla_p95_ms", "ts"], summary)

    print(f"\n포화점: {saturation or '미도달'} 사용자 / 최대 QPS {best_qps:.2f} / "
          f"SLA 유지 최대 동시 사용자 {sla_max}")
    print(f"원시: {out}\n요약: {sp}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
