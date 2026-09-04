"""Trino / StarRocks 공통 엔진 추상화.

측정 원칙 (docs/05 §1):
  - 주 지표는 **클라이언트 wall-clock** 이다. 두 엔진에 동일한 파이썬 하네스를
    사용하여 클라이언트 오버헤드 차이가 결과를 오염시키지 않게 한다.
  - 엔진이 보고하는 스캔 바이트/CPU/메모리는 **보조 지표**이며, 수집 가능 여부가
    엔진마다 다르다. 수집되지 않으면 None 으로 남기고 그 사실을 결과에 남긴다.
    (Trino: cursor.stats, StarRocks: AuditLoader 플러그인 설치 시에만 수집)
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any

from . import config

TRACK_A = "A"      # 공통 레이크 (두 엔진이 동일한 Iceberg 테이블 조회)
TRACK_B = "B"      # 각자 최적 구성
TRACK_RAW = "raw"  # 세션 컨텍스트 설정 없음 (DDL/카탈로그 생성 등 준비 작업용)


@dataclass
class QueryResult:
    ok: bool
    elapsed_ms: float
    row_count: int = 0
    status: str = "OK"          # OK | ERROR | TIMEOUT
    error: str = ""
    query_id: str | None = None
    scan_bytes: int | None = None
    cpu_ms: int | None = None
    peak_mem_bytes: int | None = None
    rows: list[Any] = field(default_factory=list)


class Engine:
    """엔진 공통 인터페이스."""

    name: str = "base"

    def __init__(self, track: str = TRACK_A) -> None:
        self.track = track
        self._conn = None
        self.cache_policy_applied: list[str] = []

    # --- 생명주기 -----------------------------------------------------------
    def connect(self) -> "Engine":
        raise NotImplementedError

    def close(self) -> None:
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
            self._conn = None

    def __enter__(self) -> "Engine":
        return self.connect()

    def __exit__(self, *exc: Any) -> None:
        self.close()

    # --- 실행 ---------------------------------------------------------------
    def execute(self, sql: str, timeout_sec: int | None = None,
                fetch: bool = True) -> QueryResult:
        raise NotImplementedError

    def execute_script(self, statements: list[str],
                       timeout_sec: int | None = None) -> list[QueryResult]:
        return [self.execute(s, timeout_sec=timeout_sec) for s in statements]

    # --- 캐시 통제 (docs/05 §2) --------------------------------------------
    def apply_cache_policy(self, cold: bool) -> list[str]:
        """콜드/웜 정책에 해당하는 세션 변수를 적용하고 적용된 항목을 반환.

        엔진/버전에 따라 존재하지 않는 변수가 있으므로 개별 try 로 처리하고,
        실제로 적용된 목록만 돌려준다. 이 목록은 결과 CSV 에 기록된다.
        """
        return []

    # --- 메타 ---------------------------------------------------------------
    def qualified(self, table: str) -> str:
        return table

    def describe(self) -> dict[str, str]:
        return {"engine": self.name, "track": self.track}

    def ping(self) -> "Engine":
        """접속 및 세션 컨텍스트 확인.

        엔진이 죽어 있는 상태로 측정을 시작하면 전 쿼리가 ERROR 로 기록되어
        결과 파일이 통째로 오염된다. 측정 진입 전에 여기서 중단시킨다.
        """
        res = self.execute("select 1", timeout_sec=30)
        if not res.ok:
            raise SystemExit(
                f"[{self.name}] 접속/세션 확인 실패 (track={self.track}): "
                f"{res.error[:300]}\n"
                f"엔진 기동 상태와 env/.env 의 호스트 설정을 확인할 것.")
        return self


class TrinoEngine(Engine):
    name = "trino"

    def connect(self) -> "TrinoEngine":
        import trino  # 지연 임포트: 해당 엔진을 쓸 때만 의존성 필요

        # trino 클라이언트는 지연 접속이므로 여기서는 실패하지 않는다.
        # 실제 도달 가능 여부는 ping() 에서 확인한다.
        self._conn = trino.dbapi.connect(
            host=config.get("TRINO_HOST"),
            port=config.get_int("TRINO_PORT"),
            user=config.get("TRINO_USER"),
            catalog=config.get("TRINO_CATALOG"),
            schema=config.get("LAKE_SCHEMA"),
            http_scheme="http",
            source="srtr-bench",
        )
        return self

    def execute(self, sql: str, timeout_sec: int | None = None,
                fetch: bool = True) -> QueryResult:
        cur = self._conn.cursor()
        started = time.perf_counter()
        try:
            if timeout_sec:
                # 세션 단위 실행 시간 상한. 별도 커서로 적용한다.
                try:
                    tcur = self._conn.cursor()
                    tcur.execute(
                        f"SET SESSION query_max_execution_time = '{timeout_sec}s'")
                    tcur.fetchall()
                except Exception:
                    pass
            cur.execute(sql)
            rows = cur.fetchall() if fetch else []
            elapsed = (time.perf_counter() - started) * 1000
            stats = getattr(cur, "stats", None) or {}
            return QueryResult(
                ok=True,
                elapsed_ms=elapsed,
                row_count=len(rows),
                query_id=stats.get("queryId"),
                scan_bytes=stats.get("processedBytes"),
                cpu_ms=stats.get("cpuTimeMillis"),
                peak_mem_bytes=stats.get("peakMemoryBytes"),
                rows=rows,
            )
        except Exception as exc:  # noqa: BLE001 - 측정 하네스는 모든 실패를 기록한다
            elapsed = (time.perf_counter() - started) * 1000
            msg = str(exc)
            status = "TIMEOUT" if "exceeded" in msg.lower() and "time" in msg.lower() else "ERROR"
            return QueryResult(ok=False, elapsed_ms=elapsed, status=status, error=msg)

    def apply_cache_policy(self, cold: bool) -> list[str]:
        # Trino 는 쿼리 결과 캐시가 기본적으로 없다. 콜드 조건은 OS 페이지 캐시
        # 드롭과 엔진 재시작(scripts/07-run-p1.sh --cold)으로 만든다.
        self.cache_policy_applied = []
        return []

    def qualified(self, table: str) -> str:
        return f"{config.get('TRINO_CATALOG')}.{config.get('LAKE_SCHEMA')}.{table}"


class StarRocksEngine(Engine):
    name = "starrocks"

    def connect(self) -> "StarRocksEngine":
        import pymysql

        host, port = config.get("SR_HOST"), config.get_int("SR_PORT")
        try:
            self._conn = pymysql.connect(
                host=host, port=port,
                user=config.get("SR_USER"),
                password=config.get("SR_PASSWORD"),
                autocommit=True,
                charset="utf8mb4",
                connect_timeout=30,
            )
        except Exception as exc:  # noqa: BLE001
            raise SystemExit(
                f"[starrocks] FE 접속 실패 ({host}:{port}): {exc}\n"
                f"엔진 기동 상태와 env/.env 의 SR_HOST/SR_PORT 를 확인할 것.") from None
        try:
            self._use_track_context()
        except Exception as exc:  # noqa: BLE001
            ctx = (f"카탈로그 {config.get('SR_EXTERNAL_CATALOG')} / DB {config.get('LAKE_SCHEMA')}"
                   if self.track == TRACK_A else f"DB {config.get('SR_NATIVE_DB')}")
            self.close()
            raise SystemExit(
                f"[starrocks] 세션 컨텍스트 설정 실패 (track={self.track}, {ctx}): {exc}\n"
                f"적재가 끝나지 않았거나 카탈로그/DB 이름이 다르다. "
                f"scripts/03-load-dataset.sh 를 먼저 수행할 것.") from None
        return self

    def _use_track_context(self) -> None:
        """Track A = 외부 카탈로그(공통 Iceberg), Track B = 네이티브 DB."""
        if self.track == TRACK_RAW:
            return
        cur = self._conn.cursor()
        if self.track == TRACK_A:
            cur.execute(f"SET CATALOG {config.get('SR_EXTERNAL_CATALOG')}")
            cur.execute(f"USE {config.get('LAKE_SCHEMA')}")
        else:
            cur.execute("SET CATALOG default_catalog")
            cur.execute(f"USE {config.get('SR_NATIVE_DB')}")
        cur.close()

    def execute(self, sql: str, timeout_sec: int | None = None,
                fetch: bool = True) -> QueryResult:
        if timeout_sec:
            try:
                c = self._conn.cursor()
                c.execute(f"SET query_timeout = {int(timeout_sec)}")
                c.close()
            except Exception:
                pass
        cur = self._conn.cursor()
        started = time.perf_counter()
        try:
            cur.execute(sql)
            rows = cur.fetchall() if fetch and cur.description else []
            elapsed = (time.perf_counter() - started) * 1000
            res = QueryResult(ok=True, elapsed_ms=elapsed,
                              row_count=len(rows), rows=list(rows))
            self._attach_audit_stats(res)
            return res
        except Exception as exc:  # noqa: BLE001
            elapsed = (time.perf_counter() - started) * 1000
            msg = str(exc)
            status = "TIMEOUT" if "timeout" in msg.lower() else "ERROR"
            return QueryResult(ok=False, elapsed_ms=elapsed, status=status, error=msg)
        finally:
            cur.close()

    def _attach_audit_stats(self, res: QueryResult) -> None:
        """AuditLoader 플러그인이 설치된 경우에만 보조 지표를 채운다.

        미설치 환경에서는 조용히 건너뛴다 (엔진 간 수집 비대칭은 결과표에 명시).
        """
        try:
            cur = self._conn.cursor()
            cur.execute(
                "SELECT scanBytes, cpuCostNs, memCostBytes "
                "FROM starrocks_audit_db__.starrocks_audit_tbl__ "
                "ORDER BY `timestamp` DESC LIMIT 1")
            row = cur.fetchone()
            cur.close()
            if row:
                res.scan_bytes = int(row[0]) if row[0] is not None else None
                res.cpu_ms = int(row[1]) // 1_000_000 if row[1] is not None else None
                res.peak_mem_bytes = int(row[2]) if row[2] is not None else None
        except Exception:
            pass

    def apply_cache_policy(self, cold: bool) -> list[str]:
        """콜드 측정 시 쿼리 캐시/데이터 캐시를 끈다.

        변수명이 버전마다 다르므로 후보를 순회하며 적용 가능한 것만 적용하고,
        실제 적용 목록을 반환하여 결과 CSV 에 남긴다.
        """
        target = "false" if cold else "true"
        candidates = [
            f"SET enable_query_cache = {target}",
            f"SET enable_scan_datacache = {target}",
            f"SET enable_populate_datacache = {target}",
        ]
        applied: list[str] = []
        for stmt in candidates:
            try:
                cur = self._conn.cursor()
                cur.execute(stmt)
                cur.close()
                applied.append(stmt)
            except Exception:
                continue
        self.cache_policy_applied = applied
        return applied

    def qualified(self, table: str) -> str:
        if self.track == TRACK_A:
            return f"{config.get('SR_EXTERNAL_CATALOG')}.{config.get('LAKE_SCHEMA')}.{table}"
        return f"{config.get('SR_NATIVE_DB')}.{table}"


ENGINES = {"trino": TrinoEngine, "starrocks": StarRocksEngine}


def make(engine_name: str, track: str = TRACK_A) -> Engine:
    if engine_name not in ENGINES:
        raise SystemExit(f"알 수 없는 엔진: {engine_name} (가능: {', '.join(ENGINES)})")
    return ENGINES[engine_name](track=track)
