-- @check F-50 | lake-format | Iceberg 테이블 읽기
select count(*) from lineitem;

-- @check F-51 | lake-format | Iceberg v2 delete 파일 반영 | mode=manual
-- 한쪽 엔진에서 DELETE 를 수행한 뒤 다른 엔진에서 행 수가 일치하는지 교차 확인한다.
select count(*) from lineitem;

-- @check F-52 | lake-format | Iceberg 쓰기 (INSERT) | engine=trino
create table if not exists fn_write_test as select * from nation;
insert into fn_write_test select * from nation;

-- @check F-52 | lake-format | Iceberg 쓰기 (INSERT) | engine=starrocks
-- 외부 카탈로그에 대한 쓰기 지원 여부를 확인한다.
insert into region select * from region limit 0;

-- @check F-53 | lake-format | 스키마 진화 (컬럼 추가) | engine=trino
alter table fn_write_test add column extra_col varchar;

-- @check F-53 | lake-format | 스키마 진화 (컬럼 추가) | engine=starrocks | mode=manual
-- 외부 카탈로그 테이블의 스키마 변경 지원 여부를 확인한다.
select 1;

-- @check F-54 | lake-format | 파티션 진화 | mode=manual
select 1;

-- @check F-55 | lake-format | Time travel / 스냅샷 조회 | engine=trino
select count(*) from "lineitem$snapshots";

-- @check F-55 | lake-format | Time travel / 스냅샷 조회 | engine=starrocks
select count(*) from lineitem for version as of 1;

-- @check F-56 | lake-format | Hudi CoW 읽기 | mode=manual
select 1;

-- @check F-57 | lake-format | Hudi MoR 읽기 | mode=manual
select 1;

-- @check F-58 | lake-format | Delta Lake 읽기 | mode=manual
select 1;

-- @check F-59 | lake-format | Hive 테이블(ORC/Parquet) 읽기 | mode=manual
select 1;

-- @check F-60 | lake-format | 테이블 유지보수 (compaction / 스냅샷 만료) | engine=trino
alter table fn_write_test execute optimize;

-- @check F-60 | lake-format | 테이블 유지보수 (compaction / 스냅샷 만료) | mode=manual | engine=starrocks
select 1;
