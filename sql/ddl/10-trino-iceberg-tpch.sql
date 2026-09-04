-- ===========================================================================
-- Track A 공통 레이크 데이터 생성 (docs/03 §2)
-- 데이터 생성 주체를 Trino 하나로 고정하여 두 엔진이 동일 파일을 읽게 한다.
-- 치환 변수: ${SCHEMA} ${SF} ${WAREHOUSE}
-- ===========================================================================

CREATE SCHEMA IF NOT EXISTS iceberg.${SCHEMA} WITH (location = '${WAREHOUSE}/${SCHEMA}');

-- 대형 팩트 테이블: 파티셔닝 적용
CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.lineitem
WITH (format = 'PARQUET', partitioning = ARRAY['month(l_shipdate)'])
AS SELECT * FROM tpch.sf${SF}.lineitem;

CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.orders
WITH (format = 'PARQUET', partitioning = ARRAY['month(o_orderdate)'])
AS SELECT * FROM tpch.sf${SF}.orders;

-- 차원 테이블: 파티셔닝 없음
CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.customer WITH (format='PARQUET') AS SELECT * FROM tpch.sf${SF}.customer;
CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.part     WITH (format='PARQUET') AS SELECT * FROM tpch.sf${SF}.part;
CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.partsupp WITH (format='PARQUET') AS SELECT * FROM tpch.sf${SF}.partsupp;
CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.supplier WITH (format='PARQUET') AS SELECT * FROM tpch.sf${SF}.supplier;
CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.nation   WITH (format='PARQUET') AS SELECT * FROM tpch.sf${SF}.nation;
CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.region   WITH (format='PARQUET') AS SELECT * FROM tpch.sf${SF}.region;
