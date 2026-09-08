-- Track B 적재: 외부 카탈로그(=Track A 와 동일 데이터)에서 네이티브 테이블로 복사
INSERT INTO ${SR_DB}.region   SELECT * FROM ${SR_CATALOG}.${SCHEMA}.region;
INSERT INTO ${SR_DB}.nation   SELECT * FROM ${SR_CATALOG}.${SCHEMA}.nation;
INSERT INTO ${SR_DB}.supplier SELECT * FROM ${SR_CATALOG}.${SCHEMA}.supplier;
INSERT INTO ${SR_DB}.part     SELECT * FROM ${SR_CATALOG}.${SCHEMA}.part;
INSERT INTO ${SR_DB}.partsupp SELECT * FROM ${SR_CATALOG}.${SCHEMA}.partsupp;
INSERT INTO ${SR_DB}.customer SELECT * FROM ${SR_CATALOG}.${SCHEMA}.customer;
INSERT INTO ${SR_DB}.orders   SELECT * FROM ${SR_CATALOG}.${SCHEMA}.orders;
INSERT INTO ${SR_DB}.lineitem SELECT * FROM ${SR_CATALOG}.${SCHEMA}.lineitem;

-- 대시보드 비정규화 테이블. 레이크에서 그대로 복사하여 두 트랙의 내용이 동일하게 유지된다.
INSERT INTO ${SR_DB}.lineitem_flat (
    l_orderkey, l_linenumber, l_shipdate, l_quantity, l_extendedprice, l_discount, l_tax,
    l_returnflag, l_linestatus, l_shipmode, l_shipinstruct,
    o_orderdate, o_orderpriority, o_orderstatus, o_totalprice,
    c_custkey, c_name, c_mktsegment, c_acctbal, cust_nation, cust_region,
    s_suppkey, supp_name, supp_nation, supp_region,
    p_partkey, p_brand, p_type, p_size, p_container, revenue)
SELECT
    l_orderkey, l_linenumber, l_shipdate, l_quantity, l_extendedprice, l_discount, l_tax,
    l_returnflag, l_linestatus, l_shipmode, l_shipinstruct,
    o_orderdate, o_orderpriority, o_orderstatus, o_totalprice,
    c_custkey, c_name, c_mktsegment, c_acctbal, cust_nation, cust_region,
    s_suppkey, supp_name, supp_nation, supp_region,
    p_partkey, p_brand, p_type, p_size, p_container, revenue
FROM ${SR_CATALOG}.${SCHEMA}.lineitem_flat;
