# StarRocks vs Trino 기술 검토 절차서

## 1. 목적

본 절차서는 StarRocks와 Trino를 **기능 · 성능 · 운영성 · 확장성 · 안정성 · 비용** 측면에서
동일한 조건으로 비교 검토하고, 최종 도입 대상을 선정하기 위한 기준과 수행 절차를 정의한다.

본 문서의 원칙은 다음 세 가지다.

1. **동일 조건(Fair Comparison)** — 동일 하드웨어 총량, 동일 데이터, 동일 쿼리, 동일 측정 도구.
2. **재현성(Reproducibility)** — 모든 설정 파일 · 스크립트 · 원시 측정값을 본 저장소에 커밋한다.
3. **의사결정 지향(Decision-Oriented)** — 모든 측정은 [평가 기준](docs/01-evaluation-criteria.md)의
   배점 항목 중 하나에 반드시 매핑된다. 매핑되지 않는 측정은 수행하지 않는다.

## 2. 검토 대상

| 구분 | 대상 | 저장소 | 버전 고정 |
|---|---|---|---|
| Federation 쿼리 엔진 | Trino | https://github.com/trinodb/trino.git | 검토 착수일 기준 최신 안정 버전으로 고정 |
| 실시간 OLAP DB | StarRocks | https://github.com/StarRocks/starrocks.git | 검토 착수일 기준 최신 안정 버전으로 고정 |

> 두 엔진은 **성격이 다르다.** Trino는 저장소를 갖지 않는 연합(federation) 쿼리 엔진이고,
> StarRocks는 자체 저장 포맷을 가진 MPP OLAP DB이면서 외부 카탈로그로 레이크도 조회한다.
> 따라서 [2-트랙 비교 설계](docs/02-test-environment.md#4-2-트랙-비교-설계)를 반드시 적용한다.
> 단일 트랙 비교는 어느 한쪽에 유리하게 왜곡되므로 채택하지 않는다.

## 3. 검토 범위

| 영역 | 세부 항목 | 상세 절차 |
|---|---|---|
| 기능 | SQL 표준, Join, Window Function, Materialized View, JSON/반정형, Iceberg/Hudi/Delta, DML/스키마 진화, 보안 | [04-기능 테스트](docs/04-functional-test.md) |
| 아키텍처 | Storage, Compute, Metadata, HA, Scale-out | [02-테스트 환경](docs/02-test-environment.md) |
| 성능 | TPC-H / TPC-DS / SSB, 응답시간, 동시성, CPU · Memory 효율 | [05-성능 테스트](docs/05-performance-test.md) |
| 운영성 | 설치, 확장, 업그레이드, 백업, 복구, 모니터링, 멀티테넌시 | [06-운영성 테스트](docs/06-operability-test.md) |
| 연계성 | Hive, Iceberg, Hudi, Delta, Kafka, S3, HDFS, MinIO, JDBC | [04-기능 테스트](docs/04-functional-test.md#6-레이크-포맷-호환성-가중치-4) |
| 비용 | 인프라, 스토리지, 라이선스/지원, 운영 인건비 3년 TCO | [07-비용 모델](docs/07-cost-model.md) |

## 4. 평가 항목 및 배점

| 항목 | 배점 | 산출 근거 |
|---|---:|---|
| 기능 | 20 | 기능 체크리스트 지원도 가중 합산 |
| 성능 | 30 | 단일 쿼리 지연 10 / 동시성 10 / 대용량 처리 5 / 자원 효율 5 |
| 운영성 | 20 | 설치·확장 8 / 백업·복구 6 / 모니터링·멀티테넌시 6 |
| 확장성 | 10 | Scale-out 선형성 및 무중단성 |
| 안정성 | 10 | 장애 주입 시나리오 통과율 및 복구 시간 |
| 비용 | 10 | 동일 SLA 달성 기준 3년 TCO 역수 환산 |
| **합계** | **100** | |

채점 규칙(척도 정의, 동점 처리, 결격 조건)은 [01-평가 기준](docs/01-evaluation-criteria.md)에 정의한다.

## 5. PoC 수행 절차

```
[0] 준비        →  [1] 환경 구성   →  [2] 데이터 적재  →  [3] 기능 검증
                                                              ↓
[7] 최종 권고   ←  [6] 채점·집계   ←  [5] 장애·운영    ←  [4] 성능 측정
```

| 단계 | 내용 | 산출물 | 문서 |
|---|---|---|---|
| 0 | 범위·배점 합의, 버전 고정, R&R 확정 | 착수 확인서 | 본 문서 §7 |
| 1 | 동일 환경 구성 (인프라, 두 엔진, 모니터링) | 설정 파일 일체 | [02](docs/02-test-environment.md) |
| 2 | 동일 데이터셋 적재 (TPC-H / TPC-DS / SSB, Iceberg+Parquet) | 적재 검증 리포트 | [03](docs/03-dataset.md) |
| 3 | 표준 기능 검증 | 기능 체크리스트 | [04](docs/04-functional-test.md) |
| 4 | 표준 쿼리 수행 및 부하 테스트 | 원시 측정값 CSV | [05](docs/05-performance-test.md) |
| 5 | 운영 시나리오 및 장애 복구 테스트 | 장애 시나리오 결과표 | [06](docs/06-operability-test.md) |
| 6 | 비용 산정 및 채점 집계 | 점수표 | [07](docs/07-cost-model.md), [08](docs/08-result-templates.md) |
| 7 | 최종 권고 및 리스크 정리 | 권고안 | [08](docs/08-result-templates.md#8-최종-권고서-양식) |

각 단계는 **완료 조건(Exit Criteria)** 을 충족해야 다음 단계로 진행한다. 완료 조건은 각 문서에 명시한다.

## 6. 결과 평가

측정 결과는 [08-결과 기록 양식](docs/08-result-templates.md)의 표준 표에만 기록한다.
자유 서술 보고서는 원시 데이터를 대체하지 않는다.

- SQL 기능 지원도
- Join 성능 (대용량 셔플 포함)
- Aggregation 성능
- Dashboard 응답 시간 (p50 / p95 / p99)
- Concurrent Query (동시 사용자별 QPS · 지연 · 에러율)
- 운영성 (설치 · 확장 · 백업 · 복구 · 모니터링)
- 비용 (3년 TCO)

## 7. 최종 권고

단일 총점만으로 결론짓지 않고, 아래 **3개 관점별 권고**를 함께 제시한다.
총점 1위 엔진과 관점별 권고가 어긋날 경우, 그 사유를 명시한다.

| 관점 | 핵심 평가 축 |
|---|---|
| 실시간 BI / OLAP 분석 | 대시보드 p95 응답, 고동시성 QPS, MV 가속 |
| 데이터 Federation | 커넥터 폭, 이기종 조인, 원본 침해 없는 조회 |
| Lakehouse + 고성능 분석 | Iceberg/Hudi/Delta 호환성, 레이크 직접 조회 성능, 캐시 전략 |

병행 도입(예: Trino = Federation · ETL 계층, StarRocks = 서빙 계층) 안도 비교 대상에 포함한다.

## 8. 실행

절차서의 각 단계는 실행 스크립트로 구현되어 있다. 상세는 [docs/09](docs/09-test-scripts.md).

```bash
cp env/.env.example env/.env      # 버전·호스트·SLA 확정 후
scripts/00-preflight.sh           # 도구 점검 + 측정 하네스 구성
scripts/run-all.sh smoke          # 로컬 축소 환경에서 스크립트 검증

scripts/13-apply-profile.sh medium  # 규모 선택 (smoke|small|medium|large)
scripts/run-all.sh measure          # 실 클러스터 측정
```

채점 가능한 규모(SF100 이상)로 올릴 때는 [docs/10](docs/10-scaling-guide.md) 을 따른다.
노드 사양·메모리 대칭·단계별 절차가 거기에 있다.

| 디렉터리 | 내용 |
|---|---|
| `env/` | 로컬 스모크 스택(docker compose), 두 엔진 설정, 규모별 프로파일 |
| `sql/` | TPC-H 22개 · 대시보드 8개 · 기능 체크리스트 · 적재 DDL |
| `bench/` | 두 엔진을 동일 경로로 구동하는 파이썬 측정 하네스 |
| `scripts/` | 번호순 실행 스크립트 (00 사전점검 ~ 12 채점) |
| `results/` | 측정 결과 CSV. `templates/` 에 수동 입력 양식 |

## 9. 역할 및 일정

| 주차 | 활동 | 담당 |
|---|---|---|
| W1 | 착수, 버전 고정, 인프라 준비, 두 엔진 설치 | 인프라 |
| W2 | 데이터 생성·적재, 적재 검증, 기능 체크리스트 | 데이터 엔지니어 |
| W3 | 성능 측정 (단일 쿼리 · 대시보드 · 동시성) | 성능 담당 |
| W4 | 부하 · 장애 주입 · 운영 시나리오 | 운영 담당 |
| W5 | 비용 산정, 채점 집계, 교차 검증 | 검토 리드 |
| W6 | 최종 권고서 작성 및 보고 | 검토 리드 |

## 10. 문서 구성

| 문서 | 내용 |
|---|---|
| [docs/01-evaluation-criteria.md](docs/01-evaluation-criteria.md) | 평가 기준, 배점 상세, 채점 척도, 결격 조건 |
| [docs/02-test-environment.md](docs/02-test-environment.md) | 공통 인프라, 두 엔진 배포, 동일 조건 통제 항목, 2-트랙 설계 |
| [docs/03-dataset.md](docs/03-dataset.md) | 데이터셋 생성·적재·검증 절차 |
| [docs/04-functional-test.md](docs/04-functional-test.md) | 기능·연계성 체크리스트 및 판정 기준 |
| [docs/05-performance-test.md](docs/05-performance-test.md) | 성능 시나리오, 측정 방법, 캐시 통제 |
| [docs/06-operability-test.md](docs/06-operability-test.md) | 설치·확장·백업·복구·장애 주입 시나리오 |
| [docs/07-cost-model.md](docs/07-cost-model.md) | 3년 TCO 산정 모델 |
| [docs/08-result-templates.md](docs/08-result-templates.md) | 결과 기록 양식 및 최종 권고서 양식 |
| [docs/09-test-scripts.md](docs/09-test-scripts.md) | 테스트 스크립트 사용 안내 (실행 방법) |
| [docs/10-scaling-guide.md](docs/10-scaling-guide.md) | 규모별 환경 구성 및 SF100+ 측정 가이드 |
