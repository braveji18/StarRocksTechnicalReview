-- 대시보드: 일자별 이동 집계 (윈도우 함수 - 대시보드에서 흔한 패턴)
select mon, revenue,
       sum(revenue) over (order by mon rows between 2 preceding and current row) as revenue_3m_ma
from (
  select date_trunc('month', l_shipdate) as mon, sum(revenue) as revenue
  from lineitem_flat
  where l_shipdate >= date '1995-01-01' and l_shipdate < date '1998-01-01'
  group by date_trunc('month', l_shipdate)
) t
order by mon
