"""P6 자원 효율 측정 (docs/05 §P6).

워크로드를 실행하는 동안의 Prometheus 지표를 구간 적분하여 기록한다.

사용:
  python -m bench.run_resource --engine trino --label "p1-warm" -- \
      python -m bench.run_latency --engine trino --suite tpch --cache warm

'--' 뒤의 명령을 실행하고, 그 시작/종료 시각으로 Prometheus 를 질의한다.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time

from . import config, resultio

# 기본 PromQL. 실 클러스터에서는 --selector 로 엔진별 라벨을 좁혀 사용한다.
QUERIES = {
    "cpu_seconds": 'sum(increase(node_cpu_seconds_total{{mode!="idle"{sel}}}[{window}s]))',
    "peak_mem_bytes": 'max_over_time((node_memory_MemTotal_bytes{{{sel_bare}}} '
                      '- node_memory_MemAvailable_bytes{{{sel_bare}}})[{window}s:15s])',
    "net_rx_bytes": 'sum(increase(node_network_receive_bytes_total{{device!="lo"{sel}}}[{window}s]))',
    "net_tx_bytes": 'sum(increase(node_network_transmit_bytes_total{{device!="lo"{sel}}}[{window}s]))',
    "disk_read_bytes": 'sum(increase(node_disk_read_bytes_total{{{sel_bare}}}[{window}s]))',
}


def query_prometheus(url: str, promql: str, at: float) -> float | None:
    import requests

    try:
        resp = requests.get(f"{url.rstrip('/')}/api/v1/query",
                            params={"query": promql, "time": at}, timeout=30)
        data = resp.json()
        if data.get("status") != "success":
            return None
        result = data["data"]["result"]
        if not result:
            return None
        return float(result[0]["value"][1])
    except Exception:
        return None


def main() -> int:
    ap = argparse.ArgumentParser(description="P6 자원 효율 측정 (워크로드 래퍼)")
    ap.add_argument("--engine", required=True)
    ap.add_argument("--track", default="A")
    ap.add_argument("--label", default="workload", help="측정 구간 이름")
    ap.add_argument("--selector", default="",
                    help='추가 라벨 셀렉터 (예: instance=~"sr-be.*")')
    ap.add_argument("--prometheus", default=config.get("PROMETHEUS_URL"))
    ap.add_argument("cmd", nargs=argparse.REMAINDER,
                    help="'--' 뒤에 실행할 워크로드 명령")
    args = ap.parse_args()

    cmd = [c for c in args.cmd if c != "--"]
    if not cmd:
        print("실행할 워크로드 명령이 없다. '--' 뒤에 명령을 지정할 것.")
        return 2

    sel = f",{args.selector}" if args.selector else ""
    sel_bare = args.selector or ""

    start = time.time()
    print(f"[P6] 워크로드 시작: {' '.join(cmd)}")
    proc = subprocess.run(cmd)
    end = time.time()
    window = max(int(end - start) + 15, 30)
    print(f"[P6] 워크로드 종료 (소요 {end - start:.1f}s, 종료코드 {proc.returncode})")
    print("[P6] Prometheus 지표 수집 대기 (15s)")
    time.sleep(15)

    metrics = {}
    for name, tmpl in QUERIES.items():
        promql = tmpl.format(window=window, sel=sel, sel_bare=sel_bare)
        metrics[name] = query_prometheus(args.prometheus, promql, end + 10)

    missing = [k for k, v in metrics.items() if v is None]
    if missing:
        print(f"[P6] 수집 실패 지표: {', '.join(missing)} "
              f"(Prometheus 미기동이거나 라벨 불일치. --selector 확인)")

    rows = [[args.track, args.engine, args.label,
             round(end - start, 1),
             round(metrics["cpu_seconds"], 1) if metrics["cpu_seconds"] else "",
             round(metrics["peak_mem_bytes"] / 1048576, 1) if metrics["peak_mem_bytes"] else "",
             int(metrics["net_rx_bytes"]) if metrics["net_rx_bytes"] else "",
             int(metrics["net_tx_bytes"]) if metrics["net_tx_bytes"] else "",
             int(metrics["disk_read_bytes"]) if metrics["disk_read_bytes"] else "",
             proc.returncode, resultio.now()]]
    out = resultio.results_path("performance", "p6_resource.csv")
    resultio.append_csv(out, ["track", "engine", "label", "wall_sec", "cpu_seconds",
                              "peak_mem_mb", "net_rx_bytes", "net_tx_bytes",
                              "disk_read_bytes", "exit_code", "ts"], rows)
    print(f"[P6] 기록: {out}")
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
