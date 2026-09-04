-- 연계성 (docs/04 §6). 대부분 설정 작업을 수반하므로 manual 판정이다.
-- 각 항목은 실제로 연결을 구성한 뒤 아래 확인 쿼리를 실행하여 판정한다.

-- @check F-70 | lake-format | Hive Metastore 연결 | mode=manual
select 1;

-- @check F-71 | lake-format | Iceberg REST Catalog 연결
select count(*) from nation;

-- @check F-72 | lake-format | S3 / MinIO 접근 (path-style, 자격증명)
select count(*) from region;

-- @check F-73 | lake-format | HDFS 연결 (Kerberos 포함) | mode=manual
select 1;

-- @check F-74 | lake-format | Kafka 실시간 적재/조회 | mode=manual
-- StarRocks: Routine Load / Trino: Kafka 커넥터. 가시성 지연을 함께 기록한다.
select 1;

-- @check F-75 | lake-format | JDBC (MySQL / PostgreSQL) 조회 | mode=manual
select 1;

-- @check F-76 | lake-format | Elasticsearch 조회 | mode=manual
select 1;

-- @check F-77 | lake-format | 이기종 조인 (레이크 x RDB) | mode=manual
-- Federation 관점 권고의 핵심 근거다. 지원 범위와 성능을 함께 기록한다.
select 1;
