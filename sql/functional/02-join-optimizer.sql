-- @check F-20 | join-optimizer | INNER / LEFT / RIGHT / FULL OUTER JOIN
select count(*) from (
  select c.c_custkey from customer c full outer join orders o on c.c_custkey = o.o_custkey
) t;

-- @check F-21 | join-optimizer | SEMI / ANTI JOIN (EXISTS / NOT EXISTS)
select count(*) from customer c
where exists (select 1 from orders where o_custkey = c.c_custkey)
  and not exists (select 1 from orders where o_custkey = c.c_custkey and o_orderstatus = 'X');

-- @check F-22 | join-optimizer | CROSS JOIN / UNNEST 배열 전개
select count(*) from (select 1) t, unnest(array[1, 2, 3]) as u(x);
-- @fallback engine=starrocks
select count(*) from (select 1 as c) t, unnest([1, 2, 3]) as u;

-- @check F-23 | join-optimizer | 상관 스칼라 서브쿼리
select count(*) from orders o
where o.o_totalprice > (select avg(l_extendedprice) from lineitem where l_orderkey = o.o_orderkey);

-- @check F-24 | join-optimizer | 다중 조인 재정렬 (EXPLAIN 확인)
explain select count(*)
from lineitem l, orders o, customer c, nation n, region r
where l.l_orderkey = o.o_orderkey and o.o_custkey = c.c_custkey
  and c.c_nationkey = n.n_nationkey and n.n_regionkey = r.r_regionkey
  and r.r_name = 'ASIA';

-- @check F-25 | join-optimizer | 조인 전략 자동 선택 (Broadcast vs Shuffle) | mode=manual
-- 위 F-24 의 EXPLAIN 출력에서 조인 분배 방식을 확인하여 판정한다.
select 1;

-- @check F-26 | join-optimizer | 런타임 필터 적용 | mode=manual
-- 실행 프로파일(Trino EXPLAIN ANALYZE / StarRocks Query Profile)에서 확인한다.
select 1;

-- @check F-27 | join-optimizer | 파티션 프루닝 (스캔 바이트 감소)
select count(*) from lineitem
where l_shipdate >= date '1995-01-01' and l_shipdate < date '1995-02-01';

-- @check F-28 | join-optimizer | 통계 기반 CBO 동작 | mode=manual
-- ANALYZE 전/후 EXPLAIN 계획 차이를 비교하여 판정한다.
select 1;
