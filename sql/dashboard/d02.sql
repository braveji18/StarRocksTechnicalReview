-- 대시보드: 지역별 매출 Top (바 차트)
select cust_region, sum(revenue) as revenue
from lineitem_flat
where l_shipdate >= date '1996-01-01' and l_shipdate < date '1997-01-01'
group by cust_region
order by revenue desc
