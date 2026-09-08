-- ===========================================================================
-- Track B: StarRocks 네이티브 테이블 (docs/03 §3)
-- 정렬키/분산키/버킷 수는 StarRocks 권장 튜닝을 적용한다.
-- 적용한 튜닝 내역은 반드시 결과표에 기록한다 (비대칭 튜닝 명시 원칙).
-- 치환 변수: ${SR_DB} ${BUCKETS_FACT} ${BUCKETS_DIM} ${REPLICAS} ${SR_PARTITION_*}
-- ===========================================================================
CREATE DATABASE IF NOT EXISTS ${SR_DB};

CREATE TABLE IF NOT EXISTS ${SR_DB}.lineitem (
    l_orderkey      BIGINT        NOT NULL,
    l_partkey       INT           NOT NULL,
    l_suppkey       INT           NOT NULL,
    l_linenumber    INT           NOT NULL,
    l_quantity      DECIMAL(15,2) NOT NULL,
    l_extendedprice DECIMAL(15,2) NOT NULL,
    l_discount      DECIMAL(15,2) NOT NULL,
    l_tax           DECIMAL(15,2) NOT NULL,
    l_returnflag    VARCHAR(1)    NOT NULL,
    l_linestatus    VARCHAR(1)    NOT NULL,
    l_shipdate      DATE          NOT NULL,
    l_commitdate    DATE          NOT NULL,
    l_receiptdate   DATE          NOT NULL,
    l_shipinstruct  VARCHAR(25)   NOT NULL,
    l_shipmode      VARCHAR(10)   NOT NULL,
    l_comment       VARCHAR(44)   NOT NULL
)
DUPLICATE KEY (l_orderkey, l_partkey, l_suppkey, l_linenumber)${SR_PARTITION_LINEITEM}
DISTRIBUTED BY HASH (l_orderkey) BUCKETS ${BUCKETS_FACT}
PROPERTIES ("replication_num" = "${REPLICAS}");

CREATE TABLE IF NOT EXISTS ${SR_DB}.orders (
    o_orderkey      BIGINT        NOT NULL,
    o_custkey       INT           NOT NULL,
    o_orderstatus   VARCHAR(1)    NOT NULL,
    o_totalprice    DECIMAL(15,2) NOT NULL,
    o_orderdate     DATE          NOT NULL,
    o_orderpriority VARCHAR(15)   NOT NULL,
    o_clerk         VARCHAR(15)   NOT NULL,
    o_shippriority  INT           NOT NULL,
    o_comment       VARCHAR(79)   NOT NULL
)
DUPLICATE KEY (o_orderkey)${SR_PARTITION_ORDERS}
DISTRIBUTED BY HASH (o_orderkey) BUCKETS ${BUCKETS_FACT}
PROPERTIES ("replication_num" = "${REPLICAS}");

CREATE TABLE IF NOT EXISTS ${SR_DB}.customer (
    c_custkey    INT           NOT NULL,
    c_name       VARCHAR(25)   NOT NULL,
    c_address    VARCHAR(40)   NOT NULL,
    c_nationkey  INT           NOT NULL,
    c_phone      VARCHAR(15)   NOT NULL,
    c_acctbal    DECIMAL(15,2) NOT NULL,
    c_mktsegment VARCHAR(10)   NOT NULL,
    c_comment    VARCHAR(117)  NOT NULL
)
DUPLICATE KEY (c_custkey)
DISTRIBUTED BY HASH (c_custkey) BUCKETS ${BUCKETS_DIM}
PROPERTIES ("replication_num" = "${REPLICAS}");

CREATE TABLE IF NOT EXISTS ${SR_DB}.part (
    p_partkey     INT           NOT NULL,
    p_name        VARCHAR(55)   NOT NULL,
    p_mfgr        VARCHAR(25)   NOT NULL,
    p_brand       VARCHAR(10)   NOT NULL,
    p_type        VARCHAR(25)   NOT NULL,
    p_size        INT           NOT NULL,
    p_container   VARCHAR(10)   NOT NULL,
    p_retailprice DECIMAL(15,2) NOT NULL,
    p_comment     VARCHAR(23)   NOT NULL
)
DUPLICATE KEY (p_partkey)
DISTRIBUTED BY HASH (p_partkey) BUCKETS ${BUCKETS_DIM}
PROPERTIES ("replication_num" = "${REPLICAS}");

CREATE TABLE IF NOT EXISTS ${SR_DB}.partsupp (
    ps_partkey    INT           NOT NULL,
    ps_suppkey    INT           NOT NULL,
    ps_availqty   INT           NOT NULL,
    ps_supplycost DECIMAL(15,2) NOT NULL,
    ps_comment    VARCHAR(199)  NOT NULL
)
DUPLICATE KEY (ps_partkey, ps_suppkey)
DISTRIBUTED BY HASH (ps_partkey) BUCKETS ${BUCKETS_DIM}
PROPERTIES ("replication_num" = "${REPLICAS}");

CREATE TABLE IF NOT EXISTS ${SR_DB}.supplier (
    s_suppkey   INT           NOT NULL,
    s_name      VARCHAR(25)   NOT NULL,
    s_address   VARCHAR(40)   NOT NULL,
    s_nationkey INT           NOT NULL,
    s_phone     VARCHAR(15)   NOT NULL,
    s_acctbal   DECIMAL(15,2) NOT NULL,
    s_comment   VARCHAR(101)  NOT NULL
)
DUPLICATE KEY (s_suppkey)
DISTRIBUTED BY HASH (s_suppkey) BUCKETS ${BUCKETS_DIM}
PROPERTIES ("replication_num" = "${REPLICAS}");

CREATE TABLE IF NOT EXISTS ${SR_DB}.nation (
    n_nationkey INT          NOT NULL,
    n_name      VARCHAR(25)  NOT NULL,
    n_regionkey INT          NOT NULL,
    n_comment   VARCHAR(152) NULL
)
DUPLICATE KEY (n_nationkey)
DISTRIBUTED BY HASH (n_nationkey) BUCKETS 1
PROPERTIES ("replication_num" = "${REPLICAS}");

CREATE TABLE IF NOT EXISTS ${SR_DB}.region (
    r_regionkey INT          NOT NULL,
    r_name      VARCHAR(25)  NOT NULL,
    r_comment   VARCHAR(152) NULL
)
DUPLICATE KEY (r_regionkey)
DISTRIBUTED BY HASH (r_regionkey) BUCKETS 1
PROPERTIES ("replication_num" = "${REPLICAS}");

-- ---------------------------------------------------------------------------
-- P2 대시보드 워크로드용 비정규화 테이블 (Track B)
-- 레이크 쪽 iceberg.${SCHEMA}.lineitem_flat 과 같은 역할을 한다.
-- 이 테이블이 없으면 Track B 에서 P2 를 아예 측정할 수 없다.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ${SR_DB}.lineitem_flat (
    l_orderkey      BIGINT        NOT NULL,
    l_linenumber    INT           NOT NULL,
    l_shipdate      DATE          NOT NULL,
    l_quantity      DECIMAL(15,2) NOT NULL,
    l_extendedprice DECIMAL(15,2) NOT NULL,
    l_discount      DECIMAL(15,2) NOT NULL,
    l_tax           DECIMAL(15,2) NOT NULL,
    l_returnflag    VARCHAR(1)    NOT NULL,
    l_linestatus    VARCHAR(1)    NOT NULL,
    l_shipmode      VARCHAR(10)   NOT NULL,
    l_shipinstruct  VARCHAR(25)   NOT NULL,
    o_orderdate     DATE          NOT NULL,
    o_orderpriority VARCHAR(15)   NOT NULL,
    o_orderstatus   VARCHAR(1)    NOT NULL,
    o_totalprice    DECIMAL(15,2) NOT NULL,
    c_custkey       INT           NOT NULL,
    c_name          VARCHAR(25)   NOT NULL,
    c_mktsegment    VARCHAR(10)   NOT NULL,
    c_acctbal       DECIMAL(15,2) NOT NULL,
    cust_nation     VARCHAR(25)   NOT NULL,
    cust_region     VARCHAR(25)   NOT NULL,
    s_suppkey       INT           NOT NULL,
    supp_name       VARCHAR(25)   NOT NULL,
    supp_nation     VARCHAR(25)   NOT NULL,
    supp_region     VARCHAR(25)   NOT NULL,
    p_partkey       INT           NOT NULL,
    p_brand         VARCHAR(10)   NOT NULL,
    p_type          VARCHAR(25)   NOT NULL,
    p_size          INT           NOT NULL,
    p_container     VARCHAR(10)   NOT NULL,
    revenue         DECIMAL(38,4) NOT NULL
)
DUPLICATE KEY (l_orderkey, l_linenumber, l_shipdate)${SR_PARTITION_LINEITEM}
DISTRIBUTED BY HASH (l_orderkey) BUCKETS ${BUCKETS_FACT}
PROPERTIES ("replication_num" = "${REPLICAS}");
