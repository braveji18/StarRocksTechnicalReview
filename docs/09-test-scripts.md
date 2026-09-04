# 09. 테스트 스크립트 사용 안내

[docs/01](01-evaluation-criteria.md)~[08](08-result-templates.md) 의 절차를 실행하는 스크립트 모음이다.
설계 문서가 "무엇을 왜 측정하는가"라면, 본 문서는 "어떻게 실행하는가"를 다룬다.

## 1. 구성

```
env/          로컬 스모크 스택 (docker compose) 및 두 엔진 설정 파일
sql/          측정에 쓰는 SQL 자산
  ddl/          데이터 생성·적재 템플릿 (${VAR} 치환)
  tpch/         TPC-H 22개 - 두 엔진 공통 문법으로 작성 (§4)
  dashboard/    P2 대시보드 워크로드 8개
  functional/   기능 체크리스트 (블록 문법, §5)
bench/        파이썬 측정 하네스 (두 엔진 공통 실행 경로)
scripts/      실행 스크립트 (번호순)
results/      측정 결과. templates/ 에 수동 입력 양식
```

## 2. 실행 순서

```bash
cp env/.env.example env/.env      # 버전·호스트·SLA 확정 (docs/02 §3)
scripts/00-preflight.sh           # 도구 점검 + .venv 구성 + 통제 체크리스트 출력
scripts/01-env-up.sh all          # (로컬 스모크만) 스택 기동
scripts/03-load-dataset.sh --normalize --preagg
scripts/04-verify-dataset.sh      # 체크섬 불일치 시 여기서 중단된다
scripts/05-run-functional.sh

scripts/06-run-p1.sh starrocks B warm tpch     # P1 단일 쿼리 지연
scripts/07-run-p2.sh starrocks B               # P2 대시보드 (SLA 대조)
scripts/08-run-p3.sh starrocks B               # P3 동시성
scripts/09-run-p6.sh starrocks B               # P6 자원 효율

scripts/10-scalability.sh trino A 3 6 "kubectl scale deploy/trino-worker --replicas=6"
scripts/11-fault-inject.sh starrocks F1 docker # F1~F6 각각 수행

scripts/12-score.sh --primary-track B          # 채점 집계
```

`scripts/run-all.sh smoke` 는 위 흐름을 로컬 축소 환경에서 한 번에 돌려 **스크립트 자체를 검증**한다.
`scripts/run-all.sh measure` 는 실 클러스터용 전체 실행이다.

## 3. 로컬 스모크 스택과 실 클러스터

`env/docker-compose.yml` 은 **스크립트 검증용 축소 환경**이다. 채점용 측정값을 얻는 곳이 아니다.

| | 로컬 스모크 | 실 측정 |
|---|---|---|
| 목적 | 스크립트·SQL·집계가 동작하는지 확인 | 채점용 수치 확보 |
| 규모 | SF=1 | SF=100 이상 |
| 노드 | 컨테이너 (동일 호스트) | [docs/02 §2.1](02-test-environment.md#21-노드-배치-기준안) 사양 |
| 부하 발생기 | 같은 장비 (오염됨) | 분리된 별도 노드 |

실 클러스터로 전환할 때 바꾸는 것은 `env/.env` 의 `TRINO_HOST` / `SR_HOST` / `SCALE_FACTOR` 뿐이다.
스크립트는 그대로 동작한다. `scripts/08-run-p3.sh` 는 부하 발생기가 엔진과 같은 장비일 때 경고한다.

메모리가 부족하면 `scripts/01-env-up.sh trino` 와 `... starrocks` 로 번갈아 기동한다.
**번갈아 기동한 경우 그 사실을 결과표에 기록해야 한다** — 동시 기동과 조건이 다르다.

## 3.1 이미 구축된 클러스터에 붙이기

`scripts/01-env-up.sh` 를 쓰지 않고 기존 Trino / StarRocks 에 바로 붙일 수 있다.
`env/.env` 의 접속 값과 스키마 이름만 맞추면 된다.

```bash
TRINO_HOST=localhost
TRINO_PORT=18080            # 기존 코디네이터 포트
LAKE_SCHEMA=bench           # 두 엔진이 함께 보는 Iceberg 스키마
SR_EXTERNAL_CATALOG=iceberg # StarRocks 에 이미 등록된 외부 카탈로그 이름
```

카탈로그가 Iceberg REST 가 아니라 **Hive Metastore** 인 경우:

- Trino: `env/trino/etc/catalog/iceberg.properties` 의 주석 처리된 HMS 블록으로 교체
- StarRocks: `sql/ddl/20-starrocks-external-catalog.sql` 대신
  `sql/ddl/20b-starrocks-external-catalog-hms.sql` 사용 (`HMS_URI` 설정 필요)

이 방식은 **Track A 측정에 바로 쓸 수 있다.** 두 엔진이 이미 같은 테이블을 보고 있기 때문이다.
Track B 는 StarRocks 네이티브 적재가 필요하므로 `scripts/03-load-dataset.sh --engine starrocks` 를 수행한다.

## 4. TPC-H 쿼리의 이식성 처리

`sql/tpch/` 의 22개 쿼리는 **두 엔진이 그대로 실행할 수 있는 하나의 집합**이다.
엔진별 쿼리 파일을 따로 두면 "쿼리가 달라서 성능이 다른" 오염이 생기므로 그렇게 하지 않았다.

이를 위해 아래를 적용했다.

| 원본 TPC-H 문법 | 적용 방식 | 이유 |
|---|---|---|
| `date '1998-12-01' - interval '90' day` | 계산된 리터럴 `date '1998-09-02'` 로 고정 | 인터벌 산술 문법이 엔진마다 다름 |
| `extract(year from x)` | `year(x)` | 양쪽 공통 |
| `substring(x from 1 for 2)` | `substr(x, 1, 2)` | 양쪽 공통 |
| Q15 의 `CREATE VIEW revenue0` | `WITH` CTE | 뷰 생성 권한/정리 부담 제거 |
| 테이블 수식자 (`catalog.schema.`) | **미사용 (unqualified)** | 세션 컨텍스트로 트랙을 전환 |

마지막 항목이 트랙 전환의 핵심이다. 동일 SQL이 세션 컨텍스트에 따라 다른 데이터를 향한다.

| 트랙 | Trino | StarRocks |
|---|---|---|
| A (공통 레이크) | `iceberg.<schema>` | `SET CATALOG iceberg_cat; USE <schema>` |
| B (각자 최적) | `iceberg.<schema>` + 사전집계 테이블 | `default_catalog` 네이티브 DB + MV |

TPC-DS 99개 쿼리는 저장소에 포함하지 않았다. `sql/tpcds/` 에 `q01.sql`~`q99.sql` 을 배치하면
`--suite tpcds` 로 동일하게 실행된다. 테이블은 `tpcds` 커넥터로 같은 방식으로 생성한다.

## 5. 기능 체크리스트 블록 문법

```
-- @check F-06 | sql-standard | 분위수 집계
select approx_percentile(cast(l_quantity as double), 0.95) from lineitem;
-- @fallback engine=starrocks
select percentile_approx(cast(l_quantity as double), 0.95) from lineitem;
```

- 표준 SQL 성공 → **지원(2)**
- 표준 실패 + 우회 SQL 성공 → **부분지원(1)** (우회가 필요했다는 사실이 곧 판정 근거)
- 둘 다 실패 → **미지원(0)**, 에러 메시지를 결과에 기록
- `mode=manual` → 판정란을 비운 채 행만 생성. 검토자가 직접 채운다 (현재 33건)

`engine=` 한정 블록을 쓸 때는 **반대편 엔진에도 대응 블록을 둔다.** 한쪽에만 존재하는 항목은
그 엔진의 분모만 키워 불리하게 작용한다. 현재 두 엔진의 평가 항목 집합은 63개로 동일하다.

## 6. 측정 지표의 비대칭성

주 지표는 **클라이언트 wall-clock** 이다. 두 엔진에 동일한 파이썬 하네스를 쓰므로
클라이언트 오버헤드 차이가 결과를 오염시키지 않는다.

엔진이 보고하는 보조 지표는 수집 경로가 다르다. 이 비대칭을 결과표에 명시해야 한다.

| 지표 | Trino | StarRocks |
|---|---|---|
| 스캔 바이트 / CPU / 피크 메모리 | `cursor.stats` 에서 항상 수집 | **AuditLoader 플러그인 설치 시에만** 수집 |
| 미수집 시 | — | 빈 값으로 기록 (0 으로 채우지 않는다) |

노드 단위 자원(P6)은 Prometheus 에서 양쪽 동일하게 수집하므로, 자원 효율 채점은 P6 값을 쓴다.

## 7. 캐시 통제

`scripts/06-run-p1.sh <engine> <track> cold` 는 측정 전에 엔진을 재시작하고,
`ALLOW_DROP_CACHES=1` 이면 OS 페이지 캐시 드롭까지 시도한다.

```bash
ALLOW_DROP_CACHES=1 scripts/06-run-p1.sh starrocks B cold tpch
```

sudo 가 불가하면 경고를 남기고 진행한다. **이 경우 콜드 조건이 불완전하므로 결과표에 기록한다.**
StarRocks 는 쿼리 캐시/데이터 캐시 세션 변수를 끄며, 실제 적용된 변수 목록이 결과 CSV 의
`cache_policy` 열에 남는다 — 버전에 따라 변수명이 달라 적용 여부가 달라질 수 있기 때문이다.

## 8. 자동화하지 않은 것과 그 이유

| 항목 | 이유 |
|---|---|
| 장애 판정(verdict) | 다운타임은 자동 측정하나, "쿼리가 보존됐는가/데이터가 유실됐는가"는 판단이 필요 |
| 재분배 완료 판정 | 완료 기준이 환경마다 달라 사전 정의가 필요 |
| 운영성 점수 | 설치 난이도·오류 진단성 등은 경험적 판단 |
| 비용 산정 | 단가와 필요 노드 수가 조직 상황에 종속 |
| 결격 조건 판정 | 임계값이 착수 시 합의 사항 |

이들은 `results/templates/` 의 양식을 채우면 `scripts/12-score.sh` 가 채점에 반영한다.
빈 값은 0점으로 처리되며 집계 시 경고로 표시된다.

## 9. 결과 재현성

`scripts/12-score.sh` 는 `results/` 의 CSV 만 읽어 점수를 산출한다.
같은 CSV로는 항상 같은 점수가 나오며, 별도 보정이나 수기 조정 경로는 없다.
점수에 이견이 있으면 CSV 를 확인하고, CSV 가 맞다면 [docs/01](01-evaluation-criteria.md) 의
환산식을 논의 대상으로 삼는다.
