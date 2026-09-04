-- 대시보드: 브랜드 x 사이즈 드릴다운 (다중 필터 적용)
select p_brand, p_size, sum(revenue) as revenue, count(distinct c_custkey) as customers
from lineitem_flat
where p_container in ('SM BOX', 'MED BOX', 'LG BOX')
  and l_shipdate >= date '1996-01-01' and l_shipdate < date '1996-07-01'
group by p_brand, p_size
order by revenue desc
limit 50
