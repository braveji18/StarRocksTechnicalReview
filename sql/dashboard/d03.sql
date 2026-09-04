-- 대시보드: 세그먼트 x 주문 우선순위 교차 집계 (피벗 테이블)
select c_mktsegment, o_orderpriority,
       sum(revenue) as revenue,
       avg(l_quantity) as avg_qty
from lineitem_flat
where l_shipdate >= date '1995-01-01' and l_shipdate < date '1996-01-01'
group by c_mktsegment, o_orderpriority
order by c_mktsegment, o_orderpriority
