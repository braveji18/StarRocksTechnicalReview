-- 대시보드: 배송 모드별 지표 카드 (소량 결과, 저지연 요구)
select l_shipmode,
       count(*)        as line_cnt,
       sum(revenue)    as revenue,
       avg(l_discount) as avg_discount
from lineitem_flat
where l_shipdate >= date '1997-06-01' and l_shipdate < date '1997-07-01'
group by l_shipmode
order by revenue desc
