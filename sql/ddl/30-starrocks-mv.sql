-- ===========================================================================
-- Track B StarRocks 사전 계산: 비동기 MV (docs/02 §4)
--
-- 주의 - 대칭성 원칙:
--   Track B 에서 StarRocks 에 MV 를 허용했다면 Trino 에도 동등한 사전 집계
--   테이블(sql/ddl/31-trino-preagg.sql)을 반드시 함께 생성해야 한다.
--   한쪽만 사전 계산을 허용한 측정값은 채점에 사용할 수 없다.
-- ===========================================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS ${SR_DB}.mv_daily_revenue
DISTRIBUTED BY HASH (l_shipdate) BUCKETS ${BUCKETS}
REFRESH ASYNC
PROPERTIES ("replication_num" = "${REPLICAS}")
AS
SELECT l_shipdate,
       l_returnflag,
       l_linestatus,
       sum(l_extendedprice * (1 - l_discount)) AS revenue,
       sum(l_quantity)                          AS qty,
       count(*)                                 AS line_cnt
FROM ${SR_DB}.lineitem
GROUP BY l_shipdate, l_returnflag, l_linestatus;

CREATE MATERIALIZED VIEW IF NOT EXISTS ${SR_DB}.mv_nation_revenue
DISTRIBUTED BY HASH (n_name) BUCKETS ${BUCKETS}
REFRESH ASYNC
PROPERTIES ("replication_num" = "${REPLICAS}")
AS
SELECT n.n_name,
       o.o_orderdate,
       sum(l.l_extendedprice * (1 - l.l_discount)) AS revenue
FROM ${SR_DB}.lineitem l
JOIN ${SR_DB}.orders   o ON l.l_orderkey  = o.o_orderkey
JOIN ${SR_DB}.customer c ON o.o_custkey   = c.c_custkey
JOIN ${SR_DB}.nation   n ON c.c_nationkey = n.n_nationkey
GROUP BY n.n_name, o.o_orderdate;
