-- 대시보드: 최근 1년 월별 매출 추이 (시계열 라인 차트)
select date_trunc('month', l_shipdate) as mon,
       sum(revenue) as revenue,
       count(*)     as orders
from lineitem_flat
where l_shipdate >= date '1997-01-01' and l_shipdate < date '1998-01-01'
group by date_trunc('month', l_shipdate)
order by mon
