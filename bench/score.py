"""채점 집계 (docs/01 평가 기준).

측정 CSV + 수동 입력 CSV 를 읽어 100점 배점표를 기계적으로 산출한다.
수동 입력 양식은 results/templates/ 에 있으며, 채워서 results/ 하위로 복사한다.

  results/functional/functional_checklist.csv   (자동 + MANUAL 항목 보완)
  results/performance/p1_summary.csv            (자동)
  results/performance/p3_summary.csv            (자동)
  results/performance/p6_resource.csv           (자동)
  results/operability/operability_scores.csv    (수동)
  results/operability/fault_injection.csv       (수동)
  results/operability/scalability.csv           (수동)
  results/cost/cost_tco.csv                     (수동)
  results/scoring/knockout.csv                  (수동)
"""
from __future__ import annotations

import argparse
from pathlib import Path

from . import config, resultio

ENGINES = ["trino", "starrocks"]
TIE_BAND = 0.10  # 10% 이내 차이는 동점 처리 (docs/01 §2)

FUNC_WEIGHTS = {
    "sql-standard": 5,
    "join-optimizer": 4,
    "mv": 3,
    "semistructured": 2,
    "lake-format": 4,
    "security": 2,
}

FAULT_POINTS = {
    "무중단+쿼리보존": 1.67,
    "무중단+쿼리실패": 1.0,
    "자동복구+일시중단": 0.5,
    "수동개입필요": 0.0,
    "데이터유실": 0.0,
}

LINEARITY_POINTS = [(0.90, 10), (0.75, 7), (0.60, 4), (0.0, 1)]


def _rel_lower_better(values: dict[str, float], budget: float) -> dict[str, float]:
    """작을수록 좋은 지표. 10% 이내 차이는 동점(양쪽 만점)."""
    usable = {e: v for e, v in values.items() if v and v > 0}
    if not usable:
        return {e: 0.0 for e in ENGINES}
    best = min(usable.values())
    worst = max(usable.values())
    if worst <= best * (1 + TIE_BAND):
        return {e: (budget if e in usable else 0.0) for e in ENGINES}
    return {e: round(budget * (best / usable[e]), 2) if e in usable else 0.0
            for e in ENGINES}


def _rel_higher_better(values: dict[str, float], budget: float) -> dict[str, float]:
    usable = {e: v for e, v in values.items() if v and v > 0}
    if not usable:
        return {e: 0.0 for e in ENGINES}
    best = max(usable.values())
    worst = min(usable.values())
    if best <= worst * (1 + TIE_BAND):
        return {e: (budget if e in usable else 0.0) for e in ENGINES}
    return {e: round(budget * (usable[e] / best), 2) if e in usable else 0.0
            for e in ENGINES}


def score_functional() -> tuple[dict[str, float], list[str]]:
    rows = resultio.read_csv(resultio.results_path("functional", "functional_checklist.csv"))
    notes: list[str] = []
    if not rows:
        return {e: 0.0 for e in ENGINES}, ["기능 체크리스트 결과 없음"]

    manual_open = sum(1 for r in rows if r.get("verdict") == "MANUAL")
    if manual_open:
        notes.append(f"MANUAL 미판정 {manual_open}건 - 0점 처리됨. 채워 넣고 재집계할 것")

    out: dict[str, float] = {}
    for eng in ENGINES:
        total = 0.0
        for cat, weight in FUNC_WEIGHTS.items():
            cat_rows = [r for r in rows if r.get("engine") == eng and r.get("category") == cat]
            if not cat_rows:
                continue
            got = sum(float(r["score"]) for r in cat_rows if r.get("score", "").strip())
            full = 2 * len(cat_rows)
            total += weight * (got / full) if full else 0
        out[eng] = round(total, 2)
    return out, notes


def score_p1(track: str) -> tuple[dict[str, float], list[str]]:
    rows = resultio.read_csv(resultio.results_path("performance", "p1_summary.csv"))
    # P1 은 분석 쿼리 스위트만 대상이다 (docs/01 §3.2). 대시보드(P2)는 제외한다.
    sel = [r for r in rows
           if r.get("track") == track and r.get("cache") == "warm"
           and r.get("benchmark") in ("tpch", "tpcds")]
    if not sel:
        return {e: 0.0 for e in ENGINES}, [f"P1 warm 요약 없음 (track {track})"]
    vals: dict[str, float] = {}
    for eng in ENGINES:
        gms = [float(r["geomean_ms"]) for r in sel
               if r.get("engine") == eng and r.get("geomean_ms")]
        if gms:
            vals[eng] = resultio.geomean(gms)  # 여러 벤치마크 스위트의 기하평균
    notes = [] if len(vals) == 2 else ["P1 측정이 한쪽 엔진에만 존재"]
    return _rel_lower_better(vals, 10), notes


def score_p3(track: str) -> tuple[dict[str, float], list[str]]:
    rows = resultio.read_csv(resultio.results_path("performance", "p3_summary.csv"))
    sel = [r for r in rows if r.get("track") == track]
    if not sel:
        return {e: 0.0 for e in ENGINES}, [f"P3 요약 없음 (track {track})"]
    vals = {}
    for eng in ENGINES:
        qps = [float(r["peak_qps"]) for r in sel if r.get("engine") == eng and r.get("peak_qps")]
        if qps:
            vals[eng] = max(qps)
    return _rel_higher_better(vals, 10), []


def score_p6(track: str) -> tuple[dict[str, float], list[str]]:
    rows = resultio.read_csv(resultio.results_path("performance", "p6_resource.csv"))
    sel = [r for r in rows if r.get("track") == track and r.get("cpu_seconds")]
    if not sel:
        return {e: 0.0 for e in ENGINES}, ["P6 자원 측정 없음 (Prometheus 미구성 가능)"]
    vals = {}
    for eng in ENGINES:
        cpu = [float(r["cpu_seconds"]) for r in sel if r.get("engine") == eng]
        if cpu:
            vals[eng] = sum(cpu) / len(cpu)
    return _rel_lower_better(vals, 5), []


def score_bulk() -> tuple[dict[str, float], list[str]]:
    """P4 대용량 처리 5점 - 수동 입력."""
    rows = resultio.read_csv(resultio.results_path("performance", "p4_bulk.csv"))
    if not rows:
        return {e: 0.0 for e in ENGINES}, ["P4 대용량 처리 결과 없음 (수동 입력 필요)"]
    vals = {r["engine"]: float(r["elapsed_sec"]) for r in rows
            if r.get("completed", "").lower() in ("y", "yes", "true", "1")
            and r.get("elapsed_sec")}
    return _rel_lower_better(vals, 5), []


def score_operability() -> tuple[dict[str, float], list[str]]:
    rows = resultio.read_csv(resultio.results_path("operability", "operability_scores.csv"))
    if not rows:
        return {e: 0.0 for e in ENGINES}, ["운영성 점수 미입력 (results/templates 참조)"]
    out = {}
    for eng in ENGINES:
        out[eng] = round(sum(float(r["score"]) for r in rows
                             if r.get("engine") == eng and r.get("score")), 2)
    return out, []


def score_stability() -> tuple[dict[str, float], list[str]]:
    rows = resultio.read_csv(resultio.results_path("operability", "fault_injection.csv"))
    if not rows:
        return {e: 0.0 for e in ENGINES}, ["장애 주입 결과 미입력"]
    notes, out = [], {}
    for eng in ENGINES:
        total = 0.0
        for r in rows:
            if r.get("engine") != eng:
                continue
            verdict = (r.get("verdict") or "").strip()
            if verdict not in FAULT_POINTS:
                notes.append(f"알 수 없는 장애 판정값: {verdict} ({r.get('code')}/{eng})")
                continue
            total += FAULT_POINTS[verdict]
        out[eng] = round(min(total, 10.0), 2)
    return out, notes


def score_scalability() -> tuple[dict[str, float], list[str]]:
    rows = resultio.read_csv(resultio.results_path("operability", "scalability.csv"))
    if not rows:
        return {e: 0.0 for e in ENGINES}, ["확장성 결과 미입력"]
    out, notes = {}, []
    for r in rows:
        eng = r.get("engine")
        if eng not in ENGINES:
            continue
        try:
            before, after = float(r["qps_before"]), float(r["qps_after"])
            n_before, n_after = float(r["nodes_before"]), float(r["nodes_after"])
        except (KeyError, ValueError):
            notes.append(f"확장성 입력값 오류: {r}")
            continue
        ratio = (n_after / n_before) if n_before else 2.0
        linearity = (after / before) / ratio if before else 0.0
        pts = next(p for th, p in LINEARITY_POINTS if linearity >= th)
        if (r.get("nondisruptive") or "").lower() not in ("y", "yes", "true", "1"):
            pts -= 3
            notes.append(f"{eng}: 무중단 확장 불가 -3점")
        out[eng] = round(max(pts, 0), 2)
        notes.append(f"{eng}: 선형성 계수 {linearity:.2f}")
    for e in ENGINES:
        out.setdefault(e, 0.0)
    return out, notes


def score_cost() -> tuple[dict[str, float], list[str]]:
    rows = resultio.read_csv(resultio.results_path("cost", "cost_tco.csv"))
    if not rows:
        return {e: 0.0 for e in ENGINES}, ["TCO 미입력"]
    vals = {r["engine"]: float(r["total_3y"]) for r in rows
            if r.get("engine") in ENGINES and r.get("total_3y")}
    return _rel_lower_better(vals, 10), []


def knockouts() -> dict[str, list[str]]:
    rows = resultio.read_csv(resultio.results_path("scoring", "knockout.csv"))
    out: dict[str, list[str]] = {e: [] for e in ENGINES}
    for r in rows:
        if (r.get("applies") or "").lower() in ("y", "yes", "true", "1"):
            out.setdefault(r.get("engine", ""), []).append(
                f"{r.get('code')}: {r.get('reason', '')}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="채점 집계")
    ap.add_argument("--primary-track", default="B", choices=["A", "B"],
                    help="총점 산출에 사용할 트랙 (기본 B: 각자 최적 구성)")
    args = ap.parse_args()

    all_notes: list[str] = []
    sections: list[tuple[str, float, dict[str, float]]] = []

    func, n = score_functional(); all_notes += n
    sections.append(("기능", 20, func))

    p1, n = score_p1(args.primary_track); all_notes += n
    p3, n2 = score_p3(args.primary_track); all_notes += n2
    p4, n3 = score_bulk(); all_notes += n3
    p6, n4 = score_p6(args.primary_track); all_notes += n4
    perf = {e: round(p1[e] + p3[e] + p4[e] + p6[e], 2) for e in ENGINES}
    sections.append(("성능", 30, perf))

    ops, n = score_operability(); all_notes += n
    sections.append(("운영성", 20, ops))

    scal, n = score_scalability(); all_notes += n
    sections.append(("확장성", 10, scal))

    stab, n = score_stability(); all_notes += n
    sections.append(("안정성", 10, stab))

    cost, n = score_cost(); all_notes += n
    sections.append(("비용", 10, cost))

    totals = {e: round(sum(s[2].get(e, 0.0) for s in sections), 2) for e in ENGINES}
    ko = knockouts()

    rows = [[name, budget, vals.get("trino", 0.0), vals.get("starrocks", 0.0)]
            for name, budget, vals in sections]
    rows.append(["총점", 100, totals["trino"], totals["starrocks"]])
    out = resultio.results_path("scoring", "final_score.csv")
    resultio.write_csv(out, ["item", "budget", "trino", "starrocks"], rows)

    detail = resultio.results_path("scoring", "performance_breakdown.csv")
    resultio.write_csv(detail, ["sub_item", "budget", "trino", "starrocks"], [
        ["P1 단일쿼리", 10, p1["trino"], p1["starrocks"]],
        ["P3 동시성", 10, p3["trino"], p3["starrocks"]],
        ["P4 대용량", 5, p4["trino"], p4["starrocks"]],
        ["P6 자원효율", 5, p6["trino"], p6["starrocks"]],
    ])

    md = ["# 최종 점수 집계", "",
          f"- 집계 시각: {resultio.now()}",
          f"- 총점 산출 트랙: **Track {args.primary_track}**", "",
          "| 평가 항목 | 배점 | Trino | StarRocks |", "|---|---:|---:|---:|"]
    for name, budget, vals in sections:
        md.append(f"| {name} | {budget} | {vals.get('trino', 0.0)} | {vals.get('starrocks', 0.0)} |")
    md.append(f"| **총점** | **100** | **{totals['trino']}** | **{totals['starrocks']}** |")
    md += ["", "## 성능 세부", "",
           "| 세부 | 배점 | Trino | StarRocks |", "|---|---:|---:|---:|",
           f"| P1 단일쿼리 | 10 | {p1['trino']} | {p1['starrocks']} |",
           f"| P3 동시성 | 10 | {p3['trino']} | {p3['starrocks']} |",
           f"| P4 대용량 | 5 | {p4['trino']} | {p4['starrocks']} |",
           f"| P6 자원효율 | 5 | {p6['trino']} | {p6['starrocks']} |", ""]

    md += ["## 결격 조건", ""]
    for eng in ENGINES:
        if ko.get(eng):
            md.append(f"- **{eng}: 도입 부적합** - " + "; ".join(ko[eng]))
        else:
            md.append(f"- {eng}: 해당 없음")
    md += ["", "## 집계 경고", ""]
    md += [f"- {x}" for x in all_notes] or ["- 없음"]
    md += ["", "> 총점만으로 결론짓지 않는다. docs/08 §7 관점별 권고를 함께 작성할 것."]

    md_path = resultio.results_path("scoring", "final_score.md")
    md_path.write_text("\n".join(md), encoding="utf-8")

    print("\n".join(md))
    print(f"\n기록: {out}\n      {detail}\n      {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
