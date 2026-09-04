-- @check F-01 | sql-standard | CTE (WITH) 다중 참조
with a as (select l_orderkey, sum(l_quantity) q from lineitem group by l_orderkey),
     b as (select avg(q) aq from a)
select count(*) from a, b where a.q > b.aq;

-- @check F-02 | sql-standard | 재귀 CTE (WITH RECURSIVE)
with recursive t(n) as (select 1 union all select n + 1 from t where n < 10)
select sum(n) from t;

-- @check F-03 | sql-standard | Window 순위 함수
select l_orderkey, row_number() over (partition by l_orderkey order by l_quantity desc) rn,
       rank() over (partition by l_orderkey order by l_quantity desc) rk,
       dense_rank() over (partition by l_orderkey order by l_quantity desc) dr
from lineitem limit 100;

-- @check F-04 | sql-standard | Window 프레임 지정 (ROWS / RANGE)
select l_orderkey,
       sum(l_quantity) over (partition by l_orderkey order by l_linenumber
                             rows between 2 preceding and current row) s
from lineitem limit 100;

-- @check F-05 | sql-standard | Window 이동 함수 (LAG/LEAD/FIRST_VALUE)
select l_orderkey,
       lag(l_quantity)  over (partition by l_orderkey order by l_linenumber) lg,
       lead(l_quantity) over (partition by l_orderkey order by l_linenumber) ld,
       first_value(l_quantity) over (partition by l_orderkey order by l_linenumber) fv
from lineitem limit 100;

-- @check F-06 | sql-standard | 분위수 집계
select approx_percentile(cast(l_quantity as double), 0.95) from lineitem;
-- @fallback engine=starrocks
select percentile_approx(cast(l_quantity as double), 0.95) from lineitem;

-- @check F-07 | sql-standard | GROUPING SETS / ROLLUP / CUBE
select l_returnflag, l_linestatus, sum(l_quantity)
from lineitem
group by grouping sets ((l_returnflag, l_linestatus), (l_returnflag), ());

-- @check F-08 | sql-standard | 근사 distinct 집계
select approx_distinct(l_orderkey) from lineitem;
-- @fallback engine=starrocks
select approx_count_distinct(l_orderkey) from lineitem;

-- @check F-09 | sql-standard | 집합 연산 (UNION / INTERSECT / EXCEPT)
select l_orderkey from lineitem where l_orderkey < 100
intersect
select o_orderkey from orders where o_orderkey < 100;

-- @check F-10 | sql-standard | 정규식 및 문자열 함수
select count(*) from customer
where regexp_like(c_phone, '^[0-9]{2}-') and length(concat(c_name, '-x')) > 5;
-- @fallback engine=starrocks
select count(*) from customer
where regexp(c_phone, '^[0-9]{2}-') and length(concat(c_name, '-x')) > 5;

-- @check F-11 | sql-standard | 날짜/시간 함수 및 타임존
select date_trunc('month', l_shipdate) m, count(*)
from lineitem group by date_trunc('month', l_shipdate) limit 10;

-- @check F-12 | sql-standard | 사용자 정의 함수(UDF) 등록 및 호출 | mode=manual
-- 엔진별 UDF 등록 절차를 수행한 뒤 판정한다. 등록 난이도와 제약을 함께 기록할 것.
select 1;
