"""env/.env 기반 설정 로더.

우선순위: 실제 환경변수 > env/.env > 기본값
실 클러스터 측정 시 TRINO_HOST / SR_HOST 만 바꾸면 전체 스크립트가 그대로 동작한다.
"""
from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / "env" / ".env"

_DEFAULTS = {
    "TRINO_HOST": "localhost",
    "TRINO_PORT": "8080",
    "TRINO_USER": "bench",
    "TRINO_CATALOG": "iceberg",
    "TRINO_SCHEMA": "tpch_sf1",
    "SR_HOST": "127.0.0.1",
    "SR_PORT": "9030",
    "SR_USER": "root",
    "SR_PASSWORD": "",
    "SR_HTTP_PORT": "8030",
    "SR_EXTERNAL_CATALOG": "iceberg_cat",
    "SR_NATIVE_DB": "tpch_sf1",
    "LAKE_SCHEMA": "tpch_sf1",
    "SCALE_FACTOR": "1",
    "S3_ENDPOINT": "http://minio:9000",
    "S3_ACCESS_KEY": "minioadmin",
    "S3_SECRET_KEY": "minioadmin",
    "S3_REGION": "us-east-1",
    "S3_BUCKET": "lake",
    "ICEBERG_REST_URI": "http://iceberg-rest:8181",
    "HMS_URI": "thrift://hive-metastore:9083",
    "PROMETHEUS_URL": "http://localhost:9090",
    "P1_REPEAT": "3",
    "P1_TIMEOUT_SEC": "600",
    "P3_USERS": "1,5,10,20,50",
    "P3_DURATION_SEC": "600",
    "P3_WARMUP_SEC": "120",
    "SLA_DASHBOARD_P95_MS": "3000",
    "SLA_TARGET_CONCURRENT_USERS": "50",
    "SR_BUCKETS": "16",
    "SR_REPLICAS": "1",
}


def _load_env_file() -> dict[str, str]:
    values: dict[str, str] = {}
    if not ENV_FILE.exists():
        return values
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        values[key.strip()] = val.strip().strip('"').strip("'")
    return values


_FILE_ENV = _load_env_file()


def get(key: str, default: str | None = None) -> str:
    if key in os.environ:
        return os.environ[key]
    if key in _FILE_ENV:
        return _FILE_ENV[key]
    if default is not None:
        return default
    return _DEFAULTS.get(key, "")


def get_int(key: str, default: int | None = None) -> int:
    raw = get(key, None if default is None else str(default))
    return int(raw) if raw else (default or 0)


def warehouse() -> str:
    return f"s3://{get('S3_BUCKET')}/warehouse"


def substitutions() -> dict[str, str]:
    """sql/ddl 템플릿의 ${...} 치환 테이블."""
    return {
        "SCHEMA": get("LAKE_SCHEMA"),
        "SF": get("SCALE_FACTOR"),
        "WAREHOUSE": warehouse(),
        "SR_CATALOG": get("SR_EXTERNAL_CATALOG"),
        "SR_DB": get("SR_NATIVE_DB"),
        "BUCKETS": get("SR_BUCKETS"),
        "REPLICAS": get("SR_REPLICAS"),
        "ICEBERG_REST_URI": get("ICEBERG_REST_URI"),
        "HMS_URI": get("HMS_URI"),
        "S3_ENDPOINT": get("S3_ENDPOINT"),
        "S3_ACCESS_KEY": get("S3_ACCESS_KEY"),
        "S3_SECRET_KEY": get("S3_SECRET_KEY"),
        "S3_REGION": get("S3_REGION"),
    }


RESULTS_DIR = ROOT / "results"
SQL_DIR = ROOT / "sql"
