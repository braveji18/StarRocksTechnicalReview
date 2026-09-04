-- @check F-80 | dml | INSERT | engine=starrocks
insert into region select * from region limit 0;

-- @check F-80 | dml | INSERT | engine=trino
insert into fn_write_test select * from nation limit 0;

-- @check F-81 | dml | UPDATE / DELETE | engine=trino
delete from fn_write_test where n_nationkey < 0;

-- @check F-81 | dml | UPDATE / DELETE | engine=starrocks | mode=manual
-- 네이티브 PRIMARY KEY 테이블에서 UPDATE/DELETE 를 수행하여 판정한다.
select 1;

-- @check F-82 | dml | MERGE (UPSERT) | mode=manual
select 1;

-- @check F-83 | dml | 기본키 기반 실시간 upsert | mode=manual
-- StarRocks PRIMARY KEY 테이블 / Trino Iceberg MERGE 로 각각 확인한다.
select 1;

-- @check F-84 | dml | 트랜잭션 원자성 (부분 실패 롤백) | mode=manual
select 1;

-- @check F-85 | dml | 동시 쓰기 충돌 처리 | mode=manual
select 1;
