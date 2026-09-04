-- 통계 수집 (docs/03 §4). 누락 시 옵티마이저 비교가 무의미해진다.
ANALYZE iceberg.${SCHEMA}.lineitem;
ANALYZE iceberg.${SCHEMA}.orders;
ANALYZE iceberg.${SCHEMA}.customer;
ANALYZE iceberg.${SCHEMA}.part;
ANALYZE iceberg.${SCHEMA}.partsupp;
ANALYZE iceberg.${SCHEMA}.supplier;
ANALYZE iceberg.${SCHEMA}.nation;
ANALYZE iceberg.${SCHEMA}.region;
ANALYZE iceberg.${SCHEMA}.lineitem_flat;
