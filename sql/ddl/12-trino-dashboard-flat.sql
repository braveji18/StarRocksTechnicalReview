-- ===========================================================================
-- P2 대시보드 워크로드용 비정규화 와이드 테이블 (docs/05 §P2)
--
-- SSB(Star Schema Benchmark) 의 성격 - 플랫 테이블에 대한 필터+집계 - 을
-- TPC-H 데이터에서 파생시켜 재현한다. dsgen/ssb-dbgen 을 별도로 돌리지 않고도
-- 동일 데이터에서 대시보드형 워크로드를 만들 수 있다.
-- SSB 원본을 쓰려면 별도 생성 후 sql/dashboard 쿼리를 교체할 것.
-- ===========================================================================
CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.lineitem_flat
WITH (format = 'PARQUET', partitioning = ARRAY['month(l_shipdate)'])
AS
SELECT
    l.l_orderkey, l.l_linenumber, l.l_quantity, l.l_extendedprice,
    l.l_discount, l.l_tax, l.l_returnflag, l.l_linestatus,
    l.l_shipdate, l.l_shipmode, l.l_shipinstruct,
    o.o_orderdate, o.o_orderpriority, o.o_orderstatus, o.o_totalprice,
    c.c_custkey, c.c_name, c.c_mktsegment, c.c_acctbal,
    cn.n_name AS cust_nation, cr.r_name AS cust_region,
    s.s_suppkey, s.s_name AS supp_name,
    sn.n_name AS supp_nation, sr.r_name AS supp_region,
    p.p_partkey, p.p_brand, p.p_type, p.p_size, p.p_container,
    l.l_extendedprice * (1 - l.l_discount) AS revenue
FROM iceberg.${SCHEMA}.lineitem l
JOIN iceberg.${SCHEMA}.orders   o  ON l.l_orderkey  = o.o_orderkey
JOIN iceberg.${SCHEMA}.customer c  ON o.o_custkey   = c.c_custkey
JOIN iceberg.${SCHEMA}.nation   cn ON c.c_nationkey = cn.n_nationkey
JOIN iceberg.${SCHEMA}.region   cr ON cn.n_regionkey= cr.r_regionkey
JOIN iceberg.${SCHEMA}.supplier s  ON l.l_suppkey   = s.s_suppkey
JOIN iceberg.${SCHEMA}.nation   sn ON s.s_nationkey = sn.n_nationkey
JOIN iceberg.${SCHEMA}.region   sr ON sn.n_regionkey= sr.r_regionkey
JOIN iceberg.${SCHEMA}.part     p  ON l.l_partkey   = p.p_partkey;
