-- TPC-H Q15 Top Supplier (원본의 뷰를 CTE 로 대체하여 두 엔진 공통 실행)
with revenue0 as (
  select l_suppkey as supplier_no,
         sum(l_extendedprice * (1 - l_discount)) as total_revenue
  from lineitem
  where l_shipdate >= date '1996-01-01'
    and l_shipdate <  date '1996-04-01'
  group by l_suppkey
)
select s_suppkey, s_name, s_address, s_phone, total_revenue
from supplier, revenue0
where s_suppkey = supplier_no
  and total_revenue = (select max(total_revenue) from revenue0)
order by s_suppkey
