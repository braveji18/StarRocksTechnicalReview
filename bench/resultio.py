"""결과 파일 입출력 (docs/08 §1 - 원시 데이터는 CSV 로만 관리)."""
from __future__ import annotations

import csv
import datetime as _dt
from pathlib import Path
from typing import Any, Iterable, Sequence

from . import config


def results_path(*parts: str) -> Path:
    p = config.RESULTS_DIR.joinpath(*parts)
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def write_csv(path: Path, header: Sequence[str], rows: Iterable[Sequence[Any]]) -> Path:
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(header)
        w.writerows(rows)
    return path


def append_csv(path: Path, header: Sequence[str], rows: Iterable[Sequence[Any]]) -> Path:
    exists = path.exists()
    with path.open("a", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        if not exists:
            w.writerow(header)
        w.writerows(rows)
    return path


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def now() -> str:
    return _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def run_stamp() -> str:
    return _dt.datetime.now().strftime("%Y%m%d-%H%M%S")


def percentile(values: list[float], q: float) -> float:
    """선형 보간 백분위수 (numpy 의존 없이)."""
    if not values:
        return float("nan")
    s = sorted(values)
    if len(s) == 1:
        return s[0]
    pos = (len(s) - 1) * q
    lo, hi = int(pos), min(int(pos) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (pos - lo)


def geomean(values: list[float]) -> float:
    """기하평균 (docs/05 §P1 - 산술평균은 장시간 쿼리에 지배되므로 쓰지 않는다)."""
    import math

    vals = [v for v in values if v > 0]
    if not vals:
        return float("nan")
    return math.exp(sum(math.log(v) for v in vals) / len(vals))


def median(values: list[float]) -> float:
    if not values:
        return float("nan")
    s = sorted(values)
    n = len(s)
    mid = n // 2
    return s[mid] if n % 2 else (s[mid - 1] + s[mid]) / 2
