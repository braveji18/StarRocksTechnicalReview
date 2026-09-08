-- ===========================================================================
-- Track A 공통 레이크 데이터 생성 (docs/03 §2)
-- 데이터 생성 주체를 Trino 하나로 고정하여 두 엔진이 동일 파일을 읽게 한다.
-- 치환 변수: ${SCHEMA} ${TPCH_SCHEMA} ${WAREHOUSE} ${LINEITEM_PART} ${ORDERS_PART}
--
-- 주의: Trino 의 tpch 커넥터는 컬럼명에 접두사를 붙이지 않는다 (custkey, shipdate ...).
--       TPC-H 표준 쿼리는 접두사 형태(c_custkey, l_shipdate)를 쓰므로
--       여기서 명시적으로 별칭을 부여한다. SELECT * 를 쓰면 안 된다.
-- ===========================================================================

CREATE SCHEMA IF NOT EXISTS iceberg.${SCHEMA} WITH (location = '${WAREHOUSE}/${SCHEMA}');

-- 대형 팩트 테이블: 파티셔닝 적용
CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.lineitem
WITH (format = 'PARQUET'${LINEITEM_PART})
AS SELECT
    orderkey      AS l_orderkey,
    partkey       AS l_partkey,
    suppkey       AS l_suppkey,
    linenumber    AS l_linenumber,
    quantity      AS l_quantity,
    extendedprice AS l_extendedprice,
    discount      AS l_discount,
    tax           AS l_tax,
    returnflag    AS l_returnflag,
    linestatus    AS l_linestatus,
    shipdate      AS l_shipdate,
    commitdate    AS l_commitdate,
    receiptdate   AS l_receiptdate,
    shipinstruct  AS l_shipinstruct,
    shipmode      AS l_shipmode,
    comment       AS l_comment
FROM tpch.${TPCH_SCHEMA}.lineitem;

CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.orders
WITH (format = 'PARQUET'${ORDERS_PART})
AS SELECT
    orderkey      AS o_orderkey,
    custkey       AS o_custkey,
    orderstatus   AS o_orderstatus,
    totalprice    AS o_totalprice,
    orderdate     AS o_orderdate,
    orderpriority AS o_orderpriority,
    clerk         AS o_clerk,
    shippriority  AS o_shippriority,
    comment       AS o_comment
FROM tpch.${TPCH_SCHEMA}.orders;

-- 차원 테이블: 파티셔닝 없음
CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.customer
WITH (format = 'PARQUET')
AS SELECT
    custkey    AS c_custkey,
    name       AS c_name,
    address    AS c_address,
    nationkey  AS c_nationkey,
    phone      AS c_phone,
    acctbal    AS c_acctbal,
    mktsegment AS c_mktsegment,
    comment    AS c_comment
FROM tpch.${TPCH_SCHEMA}.customer;

CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.part
WITH (format = 'PARQUET')
AS SELECT
    partkey     AS p_partkey,
    name        AS p_name,
    mfgr        AS p_mfgr,
    brand       AS p_brand,
    "type"      AS p_type,
    "size"      AS p_size,
    container   AS p_container,
    retailprice AS p_retailprice,
    comment     AS p_comment
FROM tpch.${TPCH_SCHEMA}.part;

CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.partsupp
WITH (format = 'PARQUET')
AS SELECT
    partkey    AS ps_partkey,
    suppkey    AS ps_suppkey,
    availqty   AS ps_availqty,
    supplycost AS ps_supplycost,
    comment    AS ps_comment
FROM tpch.${TPCH_SCHEMA}.partsupp;

CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.supplier
WITH (format = 'PARQUET')
AS SELECT
    suppkey   AS s_suppkey,
    name      AS s_name,
    address   AS s_address,
    nationkey AS s_nationkey,
    phone     AS s_phone,
    acctbal   AS s_acctbal,
    comment   AS s_comment
FROM tpch.${TPCH_SCHEMA}.supplier;

CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.nation
WITH (format = 'PARQUET')
AS SELECT
    nationkey AS n_nationkey,
    name      AS n_name,
    regionkey AS n_regionkey,
    comment   AS n_comment
FROM tpch.${TPCH_SCHEMA}.nation;

CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.region
WITH (format = 'PARQUET')
AS SELECT
    regionkey AS r_regionkey,
    name      AS r_name,
    comment   AS r_comment
FROM tpch.${TPCH_SCHEMA}.region;
