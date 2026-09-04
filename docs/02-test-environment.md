# 02. 공통 테스트 환경 구성

## 1. 설계 원칙

- **총 자원 동일**: 두 엔진에 할당하는 vCPU · 메모리 · 디스크 · 네트워크 총량을 동일하게 맞춘다.
  역할 구성(코디네이터/워커 vs FE/BE)이 달라도 **합계**가 같아야 한다.
- **동일 데이터 실체**: 동일한 Iceberg 테이블(동일 파일)을 두 엔진이 함께 바라본다.
- **동일 측정 경로**: 클라이언트, 부하 도구, 수집 지표, 수집 주기를 통일한다.
- **변경 1회 1항목**: 튜닝은 한 번에 하나만 바꾸고 그때마다 재측정한다.

## 2. 물리/논리 구성

### 2.1 노드 배치 (기준안)

| 역할 | 대수 | 사양 (기준) |
|---|---:|---|
| 제어 노드 (Trino Coordinator / StarRocks FE) | 3 | 8 vCPU, 32 GB RAM, SSD 200 GB |
| 연산 노드 (Trino Worker / StarRocks BE·CN) | 3 (확장 테스트 시 6) | 16 vCPU, 64 GB RAM, NVMe 1 TB |
| 부하 발생기 | 1 | 8 vCPU, 16 GB RAM (엔진 노드와 분리 필수) |
| 오브젝트 스토리지 (MinIO 또는 S3) | 별도 | 용량은 데이터셋 크기의 3배 |
| Hive Metastore (또는 Iceberg REST Catalog) | 1 | 4 vCPU, 8 GB RAM + RDB |
| 모니터링 (Prometheus + Grafana) | 1 | 4 vCPU, 16 GB RAM |

> 실제 사양은 도입 예정 환경에 맞춰 조정하되, **두 엔진 간에는 반드시 동일**해야 한다.
> 부하 발생기를 엔진 노드에 함께 배치하면 측정값이 오염되므로 금지한다.

### 2.2 네트워크

- 노드 간 10 GbE 이상, 동일 스위치/AZ.
- 오브젝트 스토리지까지의 대역폭과 RTT를 사전 측정하여 기록한다(`iperf3`, `curl -w`).
  레이크 직접 조회 성능은 이 값에 지배되므로 기준선 없이는 해석할 수 없다.

## 3. 버전 및 설정 고정

착수 시점에 아래 표를 채우고 검토 종료까지 변경하지 않는다. 불가피하게 변경하면 **전 항목 재측정**한다.

| 항목 | Trino | StarRocks |
|---|---|---|
| 엔진 버전 | (고정) | (고정) |
| JVM / 런타임 | 배포판이 요구하는 JDK 버전 고정 | FE JVM 힙 고정 |
| 배포 방식 | Helm chart 또는 tarball | Helm/Operator 또는 tarball |
| 배포 모드 | — | shared-nothing 또는 shared-data (§4.3) |
| 파일 포맷 | Parquet + ZSTD | 동일 |
| 카탈로그 | Iceberg (HMS 또는 REST) | External Catalog (Iceberg) + 내부 카탈로그 |

### 3.1 Trino 핵심 설정

`etc/config.properties` (coordinator):

```properties
coordinator=true
node-scheduler.include-coordinator=false
http-server.http.port=8080
discovery.uri=http://trino-coordinator:8080
query.max-memory=<총 워커 메모리의 70%>
query.max-memory-per-node=<워커 힙의 50%>
```

`etc/catalog/iceberg.properties`:

```properties
connector.name=iceberg
iceberg.catalog.type=hive_metastore
hive.metastore.uri=thrift://hms:9083
fs.native-s3.enabled=true
s3.endpoint=http://minio:9000
s3.path-style-access=true
s3.region=us-east-1
```

- 내결함성 실행(fault-tolerant execution)은 **기본 비활성**으로 측정하고, 장애 시나리오 F1에서 활성/비활성을 각각 측정한다.
- `resource-groups.properties`로 동시성 제어 정책을 정의하고, 그 내용을 결과표에 첨부한다.

### 3.2 StarRocks 핵심 설정

- FE: `fe.conf` — 메타 디렉터리, `query_port`(MySQL 프로토콜), FE Follower 3대로 HA 구성.
- BE/CN: `be.conf` — 스토리지 경로, 메모리 한도.
- 외부 카탈로그 등록:

```sql
CREATE EXTERNAL CATALOG iceberg_cat PROPERTIES (
  "type" = "iceberg",
  "iceberg.catalog.type" = "hive",
  "hive.metastore.uris" = "thrift://hms:9083",
  "aws.s3.endpoint" = "http://minio:9000",
  "aws.s3.enable_path_style_access" = "true",
  "aws.s3.access_key" = "***",
  "aws.s3.secret_key" = "***"
);
```

- 레이크 데이터 로컬 캐시(data cache)는 **트랙별로 명시적으로 on/off** 하고 그 상태를 결과표에 기록한다.
  캐시 상태를 기록하지 않은 측정값은 무효로 처리한다.

## 4. 2-트랙 비교 설계

두 엔진의 성격 차이 때문에 **단일 구성 비교는 반드시 왜곡된다.** 아래 두 트랙을 모두 측정한다.

| 트랙 | Trino | StarRocks | 답하는 질문 |
|---|---|---|---|
| **Track A — 공통 레이크** | Iceberg 테이블 직접 조회 | External Catalog로 **동일 Iceberg 테이블** 조회 | "같은 레이크 데이터를 누가 더 빨리 읽는가" |
| **Track B — 각자 최적** | Iceberg + 통계/튜닝 + 캐시 | 네이티브 테이블 적재 + 정렬키/버킷 + MV | "실제 운영 구성에서 누가 더 나은가" |

- Track A는 **Federation / Lakehouse 관점** 권고의 근거가 된다.
- Track B는 **실시간 BI/OLAP 관점** 권고의 근거가 된다.
- Track B에서 StarRocks에만 MV를 적용했다면, Trino 측에도 동등한 사전 집계 테이블(CTAS)을 허용하여
  "사전 계산 허용" 조건을 대칭으로 맞춘다. 비대칭 튜닝은 결과표에 반드시 명시한다.

### 4.3 StarRocks 배포 모드 선택

| 모드 | 특징 | 선택 기준 |
|---|---|---|
| shared-nothing (BE 로컬 스토리지, 다중 복제) | 최고 성능, 스토리지 비용 증가, 스케일 시 tablet 재분배 발생 | 온프레미스, 최저 지연이 목표 |
| shared-data (CN + 오브젝트 스토리지) | 스토리지-컴퓨트 분리, 탄력적 확장, 캐시 미스 시 지연 | 클라우드, 탄력적 확장이 목표 |

도입 예정 환경과 같은 모드를 **주 트랙**으로 삼고, 여력이 되면 다른 모드를 보조 측정한다.
두 모드를 섞어서 하나의 점수로 합산하지 않는다.

## 5. 동일 조건 통제 체크리스트

측정 착수 전 아래를 모두 확인하고 서명한다.

- [ ] 두 엔진의 총 vCPU / 총 메모리가 동일하다
- [ ] 동일한 Iceberg 테이블(동일 스냅샷 ID)을 조회한다
- [ ] 파일 포맷 · 압축 · 파티셔닝 · 파일 크기 분포가 동일하다
- [ ] 통계 정보(ANALYZE)를 양쪽 모두 최신화했다
- [ ] 캐시 상태(콜드/웜)가 정의되어 있고 트랙별로 기록된다
- [ ] 부하 발생기가 엔진 노드와 물리적으로 분리되어 있다
- [ ] Prometheus 수집 주기가 동일하다 (권장 5초)
- [ ] 동시 실행 중인 타 워크로드가 없다
- [ ] 모든 설정 파일이 본 저장소 `config/` 하위에 커밋되었다

## 6. 모니터링 구성

| 대상 | 수집 방법 | 핵심 지표 |
|---|---|---|
| Trino | JMX exporter / `/v1/jmx` | 쿼리 수, 큐 대기, 워커 CPU, 스캔 바이트, GC |
| StarRocks | FE/BE `/metrics` 엔드포인트 | QPS, 쿼리 지연, tablet 상태, compaction, 캐시 적중률 |
| 노드 | node_exporter | CPU, 메모리, 디스크 IOPS, 네트워크 |
| 스토리지 | MinIO/S3 지표 | 요청 수, 대역폭, 4xx/5xx |

Grafana 대시보드 JSON도 저장소에 커밋한다.

## 7. 완료 조건

- 두 엔진 모두 헬스체크 통과 및 샘플 쿼리 정상 수행.
- §5 통제 체크리스트 전 항목 충족.
- 모니터링 대시보드에서 두 엔진 지표가 동시에 조회된다.
