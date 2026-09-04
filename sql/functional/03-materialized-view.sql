-- @check F-30 | mv | Materialized View 생성 | engine=starrocks
create materialized view if not exists mv_fn_test
distributed by hash (l_returnflag) buckets 2
refresh async
as select l_returnflag, sum(l_quantity) q from lineitem group by l_returnflag;

-- @check F-30 | mv | Materialized View 생성 | engine=trino
-- Iceberg 커넥터의 MV 지원 여부를 확인한다. 미지원이면 오류가 발생해야 한다.
create materialized view if not exists mv_fn_test as
select l_returnflag, sum(l_quantity) q from lineitem group by l_returnflag;

-- @check F-31 | mv | 다중 테이블(조인) MV | engine=starrocks
create materialized view if not exists mv_fn_join
distributed by hash (n_name) buckets 2
refresh async
as select n.n_name, sum(l.l_extendedprice) rev
   from lineitem l join orders o on l.l_orderkey = o.o_orderkey
   join customer c on o.o_custkey = c.c_custkey
   join nation n on c.c_nationkey = n.n_nationkey
   group by n.n_name;

-- @check F-31 | mv | 다중 테이블(조인) MV | engine=trino
create materialized view if not exists mv_fn_join as
select n.n_name, sum(l.l_extendedprice) rev
from lineitem l join orders o on l.l_orderkey = o.o_orderkey
join customer c on o.o_custkey = c.c_custkey
join nation n on c.c_nationkey = n.n_nationkey
group by n.n_name;

-- @check F-32 | mv | 자동/증분 갱신 | mode=manual
-- 원본 테이블에 데이터를 추가한 뒤 MV 가 자동 갱신되는지, 전체 재계산인지 부분 갱신인지 확인한다.
select 1;

-- @check F-33 | mv | 원본 쿼리 자동 재작성 (MV 미참조 쿼리 가속) | mode=manual
-- 아래 쿼리의 실행계획에 MV 가 등장하는지 EXPLAIN 으로 확인한다.
-- 실시간 BI 관점 권고의 결정적 항목이다 (docs/04 §4).
explain select l_returnflag, sum(l_quantity) from lineitem group by l_returnflag;

-- @check F-34 | mv | 파티션 단위 부분 갱신 | mode=manual
select 1;

-- @check F-35 | mv | 갱신 중 조회 일관성 | mode=manual
select 1;
