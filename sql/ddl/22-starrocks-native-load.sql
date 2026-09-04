-- Track B 적재: 외부 카탈로그(=Track A 와 동일 데이터)에서 네이티브 테이블로 복사
INSERT INTO ${SR_DB}.region   SELECT * FROM ${SR_CATALOG}.${SCHEMA}.region;
INSERT INTO ${SR_DB}.nation   SELECT * FROM ${SR_CATALOG}.${SCHEMA}.nation;
INSERT INTO ${SR_DB}.supplier SELECT * FROM ${SR_CATALOG}.${SCHEMA}.supplier;
INSERT INTO ${SR_DB}.part     SELECT * FROM ${SR_CATALOG}.${SCHEMA}.part;
INSERT INTO ${SR_DB}.partsupp SELECT * FROM ${SR_CATALOG}.${SCHEMA}.partsupp;
INSERT INTO ${SR_DB}.customer SELECT * FROM ${SR_CATALOG}.${SCHEMA}.customer;
INSERT INTO ${SR_DB}.orders   SELECT * FROM ${SR_CATALOG}.${SCHEMA}.orders;
INSERT INTO ${SR_DB}.lineitem SELECT * FROM ${SR_CATALOG}.${SCHEMA}.lineitem;
