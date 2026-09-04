-- Track B Trino 사전 계산 (StarRocks MV 와 대칭을 맞추기 위한 사전 집계 테이블)
-- StarRocks 의 MV 자동 재작성과 달리 Trino 는 쿼리에서 직접 참조해야 하므로,
-- 그 차이 자체가 F-33(MV 자동 재작성) 판정 근거가 된다.
CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.preagg_daily_revenue
WITH (format = 'PARQUET')
AS
SELECT l_shipdate, l_returnflag, l_linestatus,
       sum(l_extendedprice * (1 - l_discount)) AS revenue,
       sum(l_quantity)                          AS qty,
       count(*)                                 AS line_cnt
FROM iceberg.${SCHEMA}.lineitem
GROUP BY l_shipdate, l_returnflag, l_linestatus;

CREATE TABLE IF NOT EXISTS iceberg.${SCHEMA}.preagg_nation_revenue
WITH (format = 'PARQUET')
AS
SELECT n.n_name, o.o_orderdate,
       sum(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM iceberg.${SCHEMA}.lineitem l
JOIN iceberg.${SCHEMA}.orders   o ON l.l_orderkey  = o.o_orderkey
JOIN iceberg.${SCHEMA}.customer c ON o.o_custkey   = c.c_custkey
JOIN iceberg.${SCHEMA}.nation   n ON c.c_nationkey = n.n_nationkey
GROUP BY n.n_name, o.o_orderdate;
