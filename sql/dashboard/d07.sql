-- 대시보드: 공급자 국가별 반품률 (비율 지표)
select supp_nation,
       sum(case when l_returnflag = 'R' then revenue else 0 end) / sum(revenue) as return_rate,
       sum(revenue) as revenue
from lineitem_flat
where l_shipdate >= date '1995-01-01' and l_shipdate < date '1997-01-01'
group by supp_nation
order by return_rate desc
