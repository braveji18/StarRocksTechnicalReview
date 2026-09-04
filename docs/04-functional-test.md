# 04. 기능 · 연계성 테스트 절차

## 1. 수행 방법

- 각 항목을 **실제 SQL을 실행하여** 판정한다. 문서만 보고 판정하지 않는다.
- 판정: **지원(2) / 부분 지원(1) / 미지원(0)**. 부분 지원은 제약 내용을 반드시 서술한다.
- 실행한 쿼리와 결과(또는 에러 메시지)를 `results/functional/` 하위에 저장한다.
- 배점 환산은 [01-평가 기준 §3.1](01-evaluation-criteria.md#31-기능-20점)을 따른다.

## 2. SQL 표준 · Window · 집계 (가중치 5)

| # | 항목 | 검증 쿼리 요지 | Trino | StarRocks |
|---|---|---|---|---|
| F-01 | CTE (WITH) | 다중 CTE 참조 | | |
| F-02 | 재귀 CTE | `WITH RECURSIVE` 계층 전개 | | |
| F-03 | Window — 순위 | `ROW_NUMBER/RANK/DENSE_RANK OVER` | | |
| F-04 | Window — 프레임 | `ROWS/RANGE BETWEEN ... PRECEDING` | | |
| F-05 | Window — 이동 | `LAG/LEAD/FIRST_VALUE/NTH_VALUE` | | |
| F-06 | 분위수 | `PERCENTILE_CONT / APPROX_PERCENTILE` | | |
| F-07 | GROUPING SETS / ROLLUP / CUBE | 다차원 집계 | | |
| F-08 | 근사 집계 | `APPROX_DISTINCT` / HLL / bitmap | | |
| F-09 | 집합 연산 | `UNION/INTERSECT/EXCEPT [ALL]` | | |
| F-10 | 문자열·정규식 | `REGEXP_*`, `SPLIT`, 유니코드 | | |
| F-11 | 날짜/시간 | 타임존 변환, `DATE_TRUNC`, 인터벌 연산 | | |
| F-12 | UDF | 사용자 정의 함수 등록 및 호출 | | |

## 3. Join · 서브쿼리 · 옵티마이저 (가중치 4)

| # | 항목 | 검증 방법 | Trino | StarRocks |
|---|---|---|---|---|
| F-20 | INNER / LEFT / RIGHT / FULL OUTER | 결과 정확성 | | |
| F-21 | SEMI / ANTI JOIN | `IN` / `EXISTS` / `NOT EXISTS` | | |
| F-22 | CROSS JOIN / LATERAL / UNNEST | 배열 전개 조인 | | |
| F-23 | 상관 서브쿼리 | 스칼라/다중행 상관 서브쿼리 | | |
| F-24 | 조인 순서 재정렬 | TPC-DS q64 등 다중 조인 `EXPLAIN` 확인 | | |
| F-25 | 조인 전략 선택 | Broadcast vs Shuffle 자동 선택 여부 | | |
| F-26 | 런타임 필터 | 실행 계획/프로파일에서 필터 푸시다운 확인 | | |
| F-27 | 파티션 프루닝 | 파티션 컬럼 조건 시 스캔 바이트 감소 확인 | | |
| F-28 | 통계 기반 CBO | ANALYZE 전/후 계획 변화 | | |

> `EXPLAIN` / `EXPLAIN ANALYZE`(Trino), Query Profile(StarRocks) 출력을 캡처하여 근거로 첨부한다.

## 4. Materialized View · 쿼리 재작성 (가중치 3)

| # | 항목 | Trino | StarRocks |
|---|---|---|---|
| F-30 | MV 생성 지원 여부 | | |
| F-31 | 다중 테이블(조인) MV | | |
| F-32 | 자동/증분 갱신 | | |
| F-33 | 원본 쿼리 자동 재작성(rewrite) — MV를 직접 참조하지 않아도 가속되는가 | | |
| F-34 | 파티션 단위 부분 갱신 | | |
| F-35 | 갱신 중 조회 일관성 | | |

> F-33은 실시간 BI 관점 권고에 결정적인 항목이다. `EXPLAIN`에서 MV가 실제로 선택되는지 확인한다.

## 5. 반정형 데이터 (가중치 2)

| # | 항목 | Trino | StarRocks |
|---|---|---|---|
| F-40 | JSON 파싱 / 경로 추출 | | |
| F-41 | JSON 컬럼 타입 및 인덱싱 | | |
| F-42 | ARRAY / MAP / STRUCT(ROW) 연산 | | |
| F-43 | 중첩 구조 전개 (`UNNEST` / `flatten`) | | |
| F-44 | 스키마리스 컬럼 조회 성능 | | |

## 6. 레이크 포맷 호환성 (가중치 4)

| # | 항목 | Trino | StarRocks |
|---|---|---|---|
| F-50 | Iceberg v1 읽기 | | |
| F-51 | Iceberg v2 (position / equality delete) 읽기 | | |
| F-52 | Iceberg 쓰기 (INSERT / UPDATE / DELETE / MERGE) | | |
| F-53 | Iceberg 스키마 진화 (컬럼 추가·삭제·타입 변경) | | |
| F-54 | Iceberg 파티션 진화 | | |
| F-55 | Time travel / 스냅샷 롤백 | | |
| F-56 | Hudi CoW 읽기 | | |
| F-57 | Hudi MoR 읽기 | | |
| F-58 | Delta Lake 읽기 (deletion vector 포함) | | |
| F-59 | Hive 테이블(ORC/Parquet/Text) 읽기 | | |
| F-60 | 테이블 유지보수 (compaction, 스냅샷 만료, 고아 파일 정리) | | |

> **연계성 테스트**: 아래는 배점상 위 카테고리에 포함되나, 사내 요건과 직결되므로 별도로 결과를 관리한다.

| # | 연계 대상 | 검증 내용 | Trino | StarRocks |
|---|---|---|---|---|
| F-70 | Hive Metastore | 카탈로그 연결, 스키마 인식 | | |
| F-71 | Iceberg REST Catalog | 연결 및 인증 | | |
| F-72 | S3 / MinIO | path-style, 자격증명, SSE | | |
| F-73 | HDFS | Kerberos 포함 연결 | | |
| F-74 | Kafka | 실시간 적재(Routine Load) 또는 커넥터 조회 | | |
| F-75 | JDBC (MySQL / PostgreSQL) | 외부 RDB 조회 및 조인 | | |
| F-76 | Elasticsearch | 조회 지원 여부 | | |
| F-77 | 이기종 조인 | 레이크 테이블 × RDB 테이블 조인 | | |

> F-77은 Federation 관점 권고의 핵심 근거다. 두 엔진 모두에서 동일 쿼리를 실행하여 지원 범위와 성능을 함께 기록한다.

## 7. DML · 동시성 시맨틱

| # | 항목 | Trino | StarRocks |
|---|---|---|---|
| F-80 | INSERT / INSERT OVERWRITE | | |
| F-81 | UPDATE / DELETE | | |
| F-82 | MERGE (UPSERT) | | |
| F-83 | 기본키 기반 실시간 upsert | | |
| F-84 | 트랜잭션 원자성 (부분 실패 시 롤백) | | |
| F-85 | 동시 쓰기 충돌 처리 | | |

## 8. 보안 (가중치 2)

| # | 항목 | Trino | StarRocks |
|---|---|---|---|
| F-90 | 인증 (LDAP / OAuth2 / Kerberos / mTLS) | | |
| F-91 | 전송 구간 암호화 (TLS) | | |
| F-92 | RBAC (역할, GRANT/REVOKE) | | |
| F-93 | 컬럼 마스킹 / 행 수준 필터 | | |
| F-94 | 감사 로그 (쿼리 이력, 접근 기록) | | |
| F-95 | 외부 권한 시스템 연동 (Ranger 등) | | |

> F-90, F-92는 [결격 조건 K4](01-evaluation-criteria.md#4-결격-조건-knock-out)와 직결된다. 미충족 시 즉시 보고한다.

## 9. 완료 조건

- [ ] 전 항목 판정 완료 (미판정 항목 0건)
- [ ] 부분 지원 항목의 제약 사항이 모두 서술됨
- [ ] 실행 쿼리 및 결과/에러 로그가 `results/functional/`에 저장됨
- [ ] 결격 조건 해당 여부 확인 완료
