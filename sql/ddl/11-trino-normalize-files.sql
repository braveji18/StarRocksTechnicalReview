-- 파일 크기 정규화 (docs/03 §2.1). 작은 파일 과다는 두 엔진 모두를 왜곡시킨다.
ALTER TABLE iceberg.${SCHEMA}.lineitem EXECUTE optimize;
ALTER TABLE iceberg.${SCHEMA}.orders   EXECUTE optimize;
ALTER TABLE iceberg.${SCHEMA}.customer EXECUTE optimize;
ALTER TABLE iceberg.${SCHEMA}.part     EXECUTE optimize;
ALTER TABLE iceberg.${SCHEMA}.partsupp EXECUTE optimize;
ALTER TABLE iceberg.${SCHEMA}.supplier EXECUTE optimize;
