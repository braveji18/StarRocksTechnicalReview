# 03. 데이터셋 생성 · 적재 · 검증 절차

## 1. 데이터셋 구성

| 데이터셋 | 규모 | 용도 |
|---|---|---|
| TPC-H | SF100 (필요 시 SF1000) | 표준 분석 쿼리 22종, 조인·집계 성능 |
| TPC-DS | SF100 | 복잡 쿼리 99종, 옵티마이저 성숙도 |
| SSB (Star Schema Benchmark) | SF100 | 대시보드형 단순 집계, 고동시성 |
| 사내 대표 데이터 | 실데이터 또는 마스킹본 | 실제 스키마·분포에서의 검증 (선택, 권장) |

> 공개 벤치마크만으로 결론 내지 않는다. 사내 대표 테이블 1~2개를 반드시 포함하면
> 데이터 분포 편향(카디널리티, 스큐, 널 비율)에 따른 차이를 잡아낼 수 있다.

## 2. 생성 방법 — Trino 내장 커넥터로 Iceberg에 기록

두 엔진이 **완전히 동일한 파일**을 읽게 하려면, 데이터 생성 주체를 하나로 고정해야 한다.
Trino의 `tpch` / `tpcds` 커넥터로 생성하여 Iceberg 테이블에 CTAS 한다.

```sql
-- 1) 스키마 생성
CREATE SCHEMA iceberg.tpch_sf100
WITH (location = 's3://lake/tpch_sf100');

-- 2) 대형 팩트 테이블은 파티셔닝 적용
CREATE TABLE iceberg.tpch_sf100.lineitem
WITH (
  format = 'PARQUET',
  format_version = 2,
  partitioning = ARRAY['month(l_shipdate)']
) AS SELECT * FROM tpch.sf100.lineitem;

CREATE TABLE iceberg.tpch_sf100.orders
WITH (format = 'PARQUET', partitioning = ARRAY['month(o_orderdate)'])
AS SELECT * FROM tpch.sf100.orders;

-- 3) 소형 차원 테이블은 파티셔닝 없이
CREATE TABLE iceberg.tpch_sf100.customer WITH (format='PARQUET') AS SELECT * FROM tpch.sf100.customer;
CREATE TABLE iceberg.tpch_sf100.part     WITH (format='PARQUET') AS SELECT * FROM tpch.sf100.part;
CREATE TABLE iceberg.tpch_sf100.partsupp WITH (format='PARQUET') AS SELECT * FROM tpch.sf100.partsupp;
CREATE TABLE iceberg.tpch_sf100.supplier WITH (format='PARQUET') AS SELECT * FROM tpch.sf100.supplier;
CREATE TABLE iceberg.tpch_sf100.nation   WITH (format='PARQUET') AS SELECT * FROM tpch.sf100.nation;
CREATE TABLE iceberg.tpch_sf100.region   WITH (format='PARQUET') AS SELECT * FROM tpch.sf100.region;
```

TPC-DS도 동일하게 `tpcds.sf100` 소스로 생성한다.

> 대안: `dbgen`/`dsdgen`으로 CSV를 생성한 뒤 Spark로 Iceberg에 적재해도 된다.
> 어느 방식이든 **생성 주체는 하나**여야 하며, 선택한 방식을 결과표에 기록한다.

### 2.1 파일 레이아웃 정규화

측정 전 파일 크기 분포를 정규화한다. 작은 파일이 많으면 두 엔진 모두 왜곡된다.

```sql
-- 목표 파일 크기로 재작성
ALTER TABLE iceberg.tpch_sf100.lineitem EXECUTE optimize(file_size_threshold => '256MB');
```

정규화 후 파일 수 · 평균 파일 크기를 기록한다.

## 3. Track B용 네이티브 적재 (StarRocks)

Track B에서는 동일 데이터를 StarRocks 네이티브 테이블로 적재한다.

```sql
-- 외부 카탈로그에서 내부 테이블로 적재
CREATE DATABASE IF NOT EXISTS tpch_sf100;

CREATE TABLE tpch_sf100.lineitem (
  l_orderkey      BIGINT,
  l_partkey       INT,
  l_suppkey       INT,
  l_linenumber    INT,
  l_quantity      DECIMAL(15,2),
  l_extendedprice DECIMAL(15,2),
  l_discount      DECIMAL(15,2),
  l_tax           DECIMAL(15,2),
  l_returnflag    VARCHAR(1),
  l_linestatus    VARCHAR(1),
  l_shipdate      DATE,
  l_commitdate    DATE,
  l_receiptdate   DATE,
  l_shipinstruct  VARCHAR(25),
  l_shipmode      VARCHAR(10),
  l_comment       VARCHAR(44)
)
DUPLICATE KEY (l_orderkey, l_partkey, l_suppkey, l_linenumber)
PARTITION BY RANGE (l_shipdate) ( ... )
DISTRIBUTED BY HASH (l_orderkey) BUCKETS 48;

INSERT INTO tpch_sf100.lineitem
SELECT * FROM iceberg_cat.tpch_sf100.lineitem;
```

- 정렬키/분산키/버킷 수는 **StarRocks 권장 튜닝을 적용**한다(Track B의 취지가 최적 구성 비교이므로).
- 적용한 튜닝 내역(파티션 전략, 버킷 수, 인덱스, MV 정의)을 전부 결과표에 기록한다.
- Trino 측에도 대칭으로 허용된 튜닝(정렬 CTAS, 사전 집계 테이블)을 적용하고 동일하게 기록한다.

## 4. 통계 정보 수집

옵티마이저 비교의 전제 조건이다. 누락하면 성능 측정이 무의미해진다.

```sql
-- Trino
ANALYZE iceberg.tpch_sf100.lineitem;

-- StarRocks
ANALYZE TABLE tpch_sf100.lineitem;
ANALYZE TABLE iceberg_cat.tpch_sf100.lineitem;   -- 외부 테이블 통계
```

## 5. 적재 검증

동일 데이터임을 **수치로 증명**한 뒤에만 성능 측정에 들어간다.

### 5.1 행 수 대조

```sql
SELECT 'lineitem' AS t, count(*) FROM <catalog>.tpch_sf100.lineitem
UNION ALL SELECT 'orders', count(*) FROM <catalog>.tpch_sf100.orders;
```

### 5.2 값 체크섬 대조

```sql
SELECT
  count(*)                       AS row_cnt,
  sum(l_quantity)                AS sum_qty,
  sum(l_extendedprice)           AS sum_price,
  min(l_shipdate)                AS min_dt,
  max(l_shipdate)                AS max_dt
FROM <catalog>.tpch_sf100.lineitem;
```

두 엔진의 결과가 **완전히 일치**해야 한다. DECIMAL 합계가 불일치하면 타입 매핑 차이를 먼저 조사한다.

### 5.3 Iceberg 스냅샷 고정

Track A 측정 중 데이터가 변경되지 않도록 스냅샷 ID를 기록하고, 필요 시 스냅샷을 고정 조회한다.

```sql
-- Trino: 스냅샷 확인
SELECT snapshot_id, committed_at FROM iceberg.tpch_sf100."lineitem$snapshots" ORDER BY committed_at DESC;
```

## 6. 적재 성능 측정 (성능 항목에 반영)

| 항목 | 측정 방법 | 기록 |
|---|---|---|
| 배치 적재 처리량 | Iceberg → 네이티브 INSERT SELECT 소요 시간 | MB/s, 행/s |
| 스트리밍 적재 | Kafka → StarRocks Routine Load / Trino는 Kafka 커넥터 조회 | 지연(가시성까지 초), 처리 건/s |
| 적재 중 조회 영향 | 적재와 동시에 대시보드 쿼리 실행 | p95 지연 변화율 |

> Trino는 저장소를 갖지 않으므로 "적재"의 의미가 다르다. Trino는 **레이크에 기록하는 INSERT 성능**과
> **Kafka 커넥터를 통한 실시간 조회 지연**으로 대응 측정하고, 항목 비대칭성을 결과표에 명시한다.

## 7. 완료 조건

- [ ] TPC-H / TPC-DS / SSB 전 테이블 적재 완료
- [ ] 두 엔진 간 행 수 · 체크섬 100% 일치
- [ ] 파일 크기 정규화 및 파일 수 기록 완료
- [ ] 양측 통계 정보 수집 완료
- [ ] Iceberg 스냅샷 ID 기록 완료
- [ ] 적재 스크립트 및 DDL 전부 저장소 `sql/` 하위에 커밋
