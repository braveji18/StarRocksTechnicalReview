-- @check F-40 | semistructured | JSON 파싱 및 경로 추출
select json_extract_scalar('{"a":{"b":42}}', '$.a.b');
-- @fallback engine=starrocks
select get_json_string('{"a":{"b":42}}', '$.a.b');

-- @check F-41 | semistructured | JSON 타입 및 연산
select cast(json_parse('{"k":1}') as json) is not null;
-- @fallback engine=starrocks
select parse_json('{"k":1}') is not null;

-- @check F-42 | semistructured | ARRAY / MAP 연산
select cardinality(array[1,2,3]), element_at(map(array['a'], array[1]), 'a');
-- @fallback engine=starrocks
select array_length([1,2,3]), map_keys(map{'a':1})[1];

-- @check F-43 | semistructured | 중첩 구조 전개 (UNNEST)
select x from unnest(array[1,2,3]) as t(x);
-- @fallback engine=starrocks
select t.x from table(unnest([1,2,3])) as t(x);

-- @check F-44 | semistructured | 스키마리스 컬럼 조회 성능 | mode=manual
-- 사내 반정형 데이터로 조회 성능을 측정하여 판정한다.
select 1;
