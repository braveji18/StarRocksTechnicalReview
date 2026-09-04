-- 대시보드: 상위 고객 20 (랭킹 위젯 - 고선택도 필터)
select c_custkey, c_name, cust_nation, sum(revenue) as revenue
from lineitem_flat
where cust_region = 'ASIA'
  and l_shipdate >= date '1997-01-01' and l_shipdate < date '1998-01-01'
group by c_custkey, c_name, cust_nation
order by revenue desc
limit 20
