# 10. 규모별 환경 구성 및 SF100+ 측정 가이드

[docs/09](09-test-scripts.md) 가 "스크립트를 어떻게 돌리는가"라면, 본 문서는
**"채점 가능한 규모에서 어떻게 돌리는가"**를 다룬다.

전제: 소규모 랩(SF0.01)에서 파이프라인이 동작함은 확인되었다
([results/measurement-conditions.md](../results/measurement-conditions.md) §5).
남은 것은 규모와 자원 대칭성이다.

## 1. 규모 등급

| 등급 | SF | lineitem 행수 | 목적 | 채점 |
|---|---:|---:|---|---|
| `smoke` | 0.01 | 6만 | 스크립트 검증 | **불가** |
| `small` | 100 | 6억 | 기능 + 기본 성능 | 최소 요건 충족 |
| `medium` | 300 | 18억 | 동시성·확장성 포함 | **표준 권장** |
| `large` | 1000 | 60억 | 대용량 조인·스필·고동시성 | 상위 검증 |

[docs/01 §4](01-evaluation-criteria.md#4-결격-조건-knock-out) 의 결격 조건 K2(SLA 달성)를
판정하려면 최소 `small` 이 필요하다. 확장성 배점(10점)과 P3 포화점까지 채우려면 `medium` 이상이어야 한다.

## 2. 노드 사양

**두 엔진에 동일한 노드 수·vCPU·RAM·디스크를 준다.** 이것이 지켜지지 않으면
그 뒤의 모든 수치는 엔진이 아니라 설정을 측정한 값이 된다.

| | small (SF100) | medium (SF300) | large (SF1000) |
|---|---|---|---|
| 제어 노드 (Coordinator / FE) | 3 x 8 vCPU / 32 GB | 3 x 8 vCPU / 32 GB | 3 x 16 vCPU / 64 GB |
| 연산 노드 (Worker / BE) | **3** x 16 vCPU / **64 GB** | **5** x 32 vCPU / **128 GB** | **8** x 32 vCPU / **256 GB** |
| 연산 노드 로컬 디스크 | NVMe 1 TB | NVMe 2 TB | NVMe 4 TB |
| 부하 발생기 | 1 x 8 vCPU / 16 GB (**반드시 분리**) | 1 x 16 vCPU / 32 GB | 2 x 16 vCPU / 32 GB |
| 오브젝트 스토리지 | 500 GB | 1.5 TB | 5 TB |
| 네트워크 | 10 GbE 이상, 동일 AZ | 동일 | 25 GbE 권장 |

연산 노드를 **홀수/짝수로 나눠 배치하지 않는다.** 두 엔진이 같은 노드 수를 써야 한다.
같은 물리 노드에 두 엔진을 동시에 올리면 서로 간섭하므로, 한 번에 한 엔진만 기동하거나
노드를 분리한다. 번갈아 기동했다면 그 사실을 결과표에 기록한다.

## 3. 스토리지 소요량

TPC-H 원본 텍스트는 대략 `SF x 1 GB`, Parquet+ZSTD 는 그 30% 안팎이다. 아래는 그 기준의 **추정치**이며,
실제 적재 후 반드시 실측하여 이 표를 갱신한다.

| 항목 | small | medium | large |
|---|---:|---:|---:|
| Iceberg 기본 8테이블 | ~30 GB | ~90 GB | ~300 GB |
| `lineitem_flat` (P2용 비정규화) | ~50 GB | ~150 GB | ~500 GB |
| Trino 사전집계 (Track B) | ~2 GB | ~6 GB | ~20 GB |
| **레이크 소계** | **~82 GB** | **~246 GB** | **~820 GB** |
| StarRocks 네이티브 x 복제 3 (Track B) | ~240 GB | ~720 GB | ~2.4 TB |
| **오브젝트 스토리지 총계** | **~330 GB** | **~1 TB** | **~3.3 TB** |
| 노드당 로컬 (데이터 캐시 + 스필) | 500 GB | 1 TB | 2 TB |

> `lineitem_flat` 이 기본 테이블보다 크다. 6억 행에 차원 컬럼 15개를 붙인 와이드 테이블이기 때문이다.
> 용량이 빠듯하면 이것부터 걸린다. P2 대시보드 측정을 포기하지 않는 한 줄일 수 없다.

> StarRocks 네이티브는 `replication_num=3` 기준이다. 복제본을 1로 낮추면 스토리지는 1/3 이 되지만
> [docs/06 §5](06-operability-test.md#5-장애-주입-시나리오-안정성-10점) 의 장애 시나리오 결과가 달라진다.
> 안정성 배점을 측정할 계획이면 3을 유지하고, 그 스토리지 비용을
> [docs/07 §3](07-cost-model.md#3-스토리지-비용-비대칭-처리) 의 비용 산정에 그대로 반영한다.

## 4. 엔진 메모리 설정 — 대칭이 핵심

### 4.1 Trino 메모리 산출 공식

기존 랩에서 확립된 공식을 그대로 쓴다 (`trino-k8s/docs/03-02-node-tuning-plan.md`).

```
Xmx                 = 0.8 x 컨테이너/노드 메모리
heap-headroom       = 0.3 x Xmx        (기본값)
query.max-memory-per-node = Xmx - headroom - 2 GiB(안전분)
query.max-memory    = query.max-memory-per-node x 워커 수
```

| | small | medium | large |
|---|---|---|---|
| 워커 노드 메모리 | 64 GB | 128 GB | 256 GB |
| `jvm.maxHeapSize` | 48G | 96G | 192G |
| `query.max-memory-per-node` | **32GB** | **65GB** | **132GB** |
| `query.max-memory` | 96GB | 325GB | 1056GB |
| `memory.heap-headroom-per-node` | 기본(0.3) | 기본 | 기본 |

산출 예 (small): `0.8x64=51.2 -> 48G` / `0.3x48=14.4` / `48-14.4-2=31.6 -> 32GB`.

### 4.2 StarRocks 메모리 — Trino 와 같은 값으로 맞춘다

StarRocks 는 BE 가 C++ 이라 JVM 헤드룸이 없다. 그래서 컨테이너 메모리를 같게 주면
**쿼리가 실제로 쓸 수 있는 메모리는 StarRocks 쪽이 훨씬 커진다.** 이번 예비 측정에서
Trino 600MB 대 StarRocks 1800M(3배) 가 된 원인이 정확히 이것이다.

노드당 쿼리 메모리를 Trino 와 같은 값으로 명시적으로 묶는다.

| | small | medium | large |
|---|---|---|---|
| BE 노드 메모리 | 64 GB | 128 GB | 256 GB |
| `mem_limit` (be.conf) | 48G | 96G | 192G |
| **`query_mem_limit` (세션/리소스그룹)** | **32GB** | **65GB** | **132GB** |
| FE `-Xmx` | 16G | 24G | 32G |

`query_mem_limit` 은 **BE 노드 1대당, 쿼리 1건당** 상한이므로 Trino 의
`query.max-memory-per-node` 와 같은 의미다. 값을 바이트로 준다.

```sql
-- 전역 기본값으로 고정 (측정 세션마다 재설정하지 않도록)
SET GLOBAL query_mem_limit = 34359738368;   -- 32 GiB, small 기준
```

리소스 그룹을 쓴다면 그룹의 `mem_limit` 으로도 걸 수 있으나, 그룹은 비율(%) 기반이라
정확히 맞추기 어렵다. 대칭성 검증(§5)이 통과하는 쪽을 택한다.

### 4.3 CPU

vCPU 수만 같게 주고 엔진 내부 병렬도는 **양쪽 다 자동값**으로 둔다.
한쪽만 손대면 그 자체가 비대칭이 된다.

| | Trino | StarRocks |
|---|---|---|
| 병렬도 | `task.concurrency` 미지정(=vCPU) | `pipeline_dop=0` (자동) |
| 확인 | `SELECT * FROM system.runtime.nodes` | `SHOW BACKENDS` 의 `CpuCores` |

컨테이너에 CPU 제한을 건다면 **양쪽 같은 값**으로 걸고, 안 건다면 양쪽 다 걸지 않는다.

### 4.4 디스크 스필 — 대용량(P4) 측정의 전제

스필이 꺼져 있으면 메모리를 넘는 쿼리는 무조건 실패한다. 그러면 P4 대용량 처리 배점(5점)이
"완주 실패"로만 나와 비교가 되지 않는다. **양쪽 다 켠다.**

```properties
# Trino (config.properties)
spill-enabled=true
spiller-spill-path=/data/trino/spill        # 로컬 NVMe. 네트워크 스토리지 금지
spiller-max-used-space-threshold=0.8
```

```sql
-- StarRocks
SET GLOBAL enable_spill = true;
SET GLOBAL spill_mode = 'auto';
```

StarRocks BE 의 스필 경로는 `be.conf` 의 `storage_root_path` 를 따른다. 로컬 NVMe 여야 한다.

## 5. 대칭성 검증 — 측정 진입 전 필수

설정만 맞췄다고 끝이 아니다. **실제로 같은 메모리를 쓰는지 확인한다.**

```sql
-- 두 엔진에서 같은 쿼리를 돌리고 peak memory 를 비교한다 (TPC-H Q21 권장)
-- Trino
SELECT query_id, peak_user_memory_bytes/1024/1024/1024 AS peak_gb, state
FROM system.runtime.queries ORDER BY created DESC LIMIT 1;

-- StarRocks (AuditLoader 설치 시)
SELECT queryId, memCostBytes/1024/1024/1024 AS peak_gb, state
FROM starrocks_audit_db__.starrocks_audit_tbl__ ORDER BY `timestamp` DESC LIMIT 1;
```

판정 기준:

| 항목 | 통과 조건 |
|---|---|
| 노드당 쿼리 메모리 상한 | 두 엔진의 설정값이 **동일** |
| 연산 노드 수 / vCPU / RAM | 동일 |
| 실제 peak memory | 같은 쿼리에서 **2배 이내** |
| 스필 활성 여부 | 양쪽 다 활성 |
| CPU 제한 | 양쪽 다 있거나 양쪽 다 없음 |

이 표를 채워 [results/measurement-conditions.md](../results/measurement-conditions.md) 에 남긴다.
하나라도 어긋나면 측정에 들어가지 않는다.

## 6. 단계별 진행 절차

```
[0] 사양 확정      →  [1] 환경 구성  →  [2] 소규모 리허설(SF1)
                                              ↓
[6] 채점          ←  [5] 측정      ←  [4] 검증  ←  [3] 본 적재(SF100+)
```

### 단계 0 — 사양 확정 (0.5일)

- §1 등급 선택, §2 노드 사양 확보, §3 스토리지 확보 확인
- [docs/01 §4](01-evaluation-criteria.md#4-결격-조건-knock-out) 결격 조건 임계값 확정
  (특히 K2 의 대시보드 p95 SLA 와 목표 동시 사용자 수)
- 엔진 버전 고정 → `env/.env` 의 `TRINO_VERSION` / `STARROCKS_VERSION`

**완료 조건**: 사양·임계값이 서명으로 확정되었다. 이후 변경하지 않는다.

### 단계 1 — 환경 구성 (1~2일)

1. 두 엔진 배포. §4 의 메모리·CPU·스필 설정 적용
2. 공통 카탈로그(HMS 또는 Iceberg REST) 1개를 **두 엔진이 함께** 바라보게 구성
3. Prometheus + node_exporter 구성 — 없으면 P6 자원 효율(5점)을 채울 수 없다
4. 부하 발생기 노드에 하네스 설치

```bash
git clone <this-repo> && cd StarRocksTechnicalReview
cp env/.env.example env/.env
# TRINO_HOST / SR_HOST / S3_* / HMS_URI 를 실 클러스터로 지정
scripts/00-preflight.sh
```

**완료 조건**: `scripts/00-preflight.sh` 통과 + §5 대칭성 검증표 작성 완료.

### 단계 2 — 소규모 리허설 (0.5일, 생략 금지)

**SF100 을 바로 적재하지 않는다.** 먼저 SF1 로 전 경로를 완주시킨다.
이번 예비 측정에서 적재 DDL 버그 2건과 하네스 결함 2건이 여기서 드러났다.
SF100 에서 같은 문제를 만나면 수 시간을 버린다.

```bash
scripts/13-apply-profile.sh smoke
sed -i 's/^SCALE_FACTOR=.*/SCALE_FACTOR=1/; s/^TPCH_SCHEMA=.*/TPCH_SCHEMA=sf1/' env/.env
scripts/03-load-dataset.sh --normalize --preagg
scripts/04-verify-dataset.sh          # 여기서 막히면 SF100 도 막힌다
scripts/05-run-functional.sh
scripts/06-run-p1.sh starrocks A warm tpch
```

**완료 조건**: 적재 검증 통과 + P1 22개 실패 0건 + 기능 체크리스트 자동 판정 완료.

### 단계 3 — 본 적재 (SF100 반나절 / SF1000 1~2일)

```bash
scripts/13-apply-profile.sh small       # 또는 medium / large
scripts/03-load-dataset.sh --normalize --preagg
```

적재 중 확인할 것:

| 증상 | 원인 | 조치 |
|---|---|---|
| 워커 exit 137 | 파티션 라이터 버퍼 초과 | `PARTITION_GRAIN` 을 한 단계 낮춘다 (month→year) |
| 적재가 극단적으로 느림 | tpch 커넥터 CTAS 한계 | `large` 는 dbgen + Spark 적재를 검토 |
| 오브젝트 스토리지 용량 부족 | §3 추정 초과 | `lineitem_flat` 부터 확인 |

적재 후 실측을 기록한다.

```sql
-- Iceberg 테이블 실제 크기와 파일 수
SELECT COUNT(*) AS files, SUM(file_size_in_bytes)/1024/1024/1024 AS gb
FROM iceberg.<schema>."lineitem$files";

-- StarRocks 태블릿 크기 분포 (100MB~1GB 권장)
SHOW TABLET FROM <db>.lineitem;
```

태블릿이 100 MB 미만이거나 1 GB 초과면 `SR_BUCKETS_FACT` 를 조정하고 재적재한다.

**완료 조건**: 8개 테이블 + `lineitem_flat` + 사전계산 전부 적재. 실측 용량 기록.

### 단계 4 — 검증 (1시간, 하드 게이트)

```bash
scripts/04-verify-dataset.sh --tracks A,B
```

두 엔진의 행수·체크섬이 **완전히 일치**해야 한다. 불일치 시 종료코드 1 로 막힌다.
DECIMAL 합계가 어긋나면 타입 매핑 차이를 먼저 조사한다
([docs/03 §5.2](03-dataset.md#52-값-체크섬-대조)).

또한 양쪽 통계를 최신화한다 — 누락하면 옵티마이저 비교가 무의미해진다.

**완료 조건**: 검증 통과 + 양쪽 ANALYZE 완료 + Iceberg 스냅샷 ID 기록.

### 단계 5 — 측정 (SF100 2~3일 / SF1000 1주)

순서를 지킨다. 콜드는 캐시를 비운 직후여야 하므로 가장 먼저 한다.

```bash
# 5-1 콜드 (엔진 재시작 + 페이지 캐시 드롭)
for e in trino starrocks; do for t in A B; do
  ALLOW_DROP_CACHES=1 scripts/06-run-p1.sh $e $t cold tpch
done; done

# 5-2 웜 P1 / P2
for e in trino starrocks; do for t in A B; do
  scripts/06-run-p1.sh $e $t warm tpch
  scripts/07-run-p2.sh $e $t
done; done

# 5-3 동시성 (부하 발생기 노드에서 실행)
for e in trino starrocks; do for t in A B; do
  scripts/08-run-p3.sh $e $t
done; done

# 5-4 자원 효율
for e in trino starrocks; do for t in A B; do
  scripts/09-run-p6.sh $e $t
done; done

# 5-5 확장성 (연산 노드 N -> 2N)
scripts/10-scalability.sh trino     A 3 6 "kubectl scale deploy/trino-worker --replicas=6"
scripts/10-scalability.sh starrocks B 3 6 "kubectl scale sts/starrocks-be --replicas=6"

# 5-6 장애 주입 (F1~F6, 부하 인가 상태)
for f in F1 F2 F3 F4 F5 F6; do
  scripts/11-fault-inject.sh trino     $f k8s
  scripts/11-fault-inject.sh starrocks $f k8s
done
```

측정 중 한쪽 엔진만 튜닝하지 않는다. 조정했다면 반대편에도 대칭으로 적용하고
결과표에 기록한다 ([docs/05 §5](05-performance-test.md#5-성능-이상-시-조사-절차)).

**완료 조건**: P1~P6 전 시나리오가 Track A·B 모두에서 완료. 실패 쿼리 목록 정리.

### 단계 6 — 채점 (1일)

```bash
cp results/templates/*.csv results/…      # 운영성·비용·장애·결격 조건 입력
scripts/12-score.sh --primary-track B
```

집계 경고가 하나도 없어야 채점이 완결된 것이다. 경고가 남아 있으면 그 항목은 0점 처리된 상태다.

**완료 조건**: [docs/08 §9](08-result-templates.md#9-완료-조건) 체크리스트 충족.

## 7. 규모별 예상 소요 시간

| 단계 | small | medium | large |
|---|---|---|---|
| 0 사양 확정 | 0.5일 | 0.5일 | 1일 |
| 1 환경 구성 | 1일 | 2일 | 3일 |
| 2 리허설 | 0.5일 | 0.5일 | 0.5일 |
| 3 적재 | 0.5일 | 1일 | 2일 |
| 4 검증 | 1시간 | 2시간 | 4시간 |
| 5 측정 | 2일 | 3일 | 5일 |
| 6 채점 | 1일 | 1일 | 1일 |
| **합계** | **약 1주** | **약 1.5주** | **약 2.5주** |

[README §9](../README.md#9-역할-및-일정) 의 6주 일정은 `medium` 기준에 검토·보고 여유를 더한 값이다.

## 8. 어디를 바꾸는가 — 배포 형태별

| 대상 | 이 저장소 | 기존 랩 (`dataops-insight`) | Kubernetes |
|---|---|---|---|
| 하네스 규모 설정 | `scripts/13-apply-profile.sh <등급>` | 동일 | 동일 |
| Trino 힙 | `env/trino/etc/jvm.config` | `profiles/*.env` 의 `TRINO_WORKER_MEM` (힙=80%) | Helm `values.yaml` 의 `jvm.maxHeapSize` |
| Trino 쿼리 메모리 | `env/trino/{coordinator,worker}/config.properties` | `profiles/*.env` 의 `TRINO_QUERY_MAX_MEMORY*` | Helm `additionalConfigProperties` |
| StarRocks BE 메모리 | `env/docker-compose.yml` 의 `SR_BE_MEM_LIMIT` | `profiles/*.env` 의 `SR_BE_MEM_LIMIT` | Operator CR 의 `be.limits` + `be.conf` |
| StarRocks 쿼리 메모리 | `SET GLOBAL query_mem_limit` | 동일 | 동일 |
| 노드 수 | `env/docker-compose.yml` 서비스 추가 | compose 서비스 추가 | `kubectl scale` |

기존 랩의 `.env` 는 `bin/up.sh` 가 생성하므로 **직접 수정하지 않는다.**
`profiles/functional.env` / `profiles/perf.env` 를 고치고 `bin/up.sh <프로파일>` 로 재기동한다.
다만 두 프로파일 모두 Trino 와 StarRocks 의 쿼리 메모리가 3배 비대칭이므로,
채점 측정에 쓰려면 §4.2 대로 맞춘 프로파일을 새로 만들어야 한다.

## 9. 완료 조건

- [ ] 규모 등급을 선택하고 그에 맞는 노드 사양을 확보했다
- [ ] §4 의 메모리·CPU·스필 설정을 두 엔진에 대칭으로 적용했다
- [ ] §5 대칭성 검증표를 채우고 전 항목 통과했다
- [ ] 단계 2 리허설을 SF1 에서 완주했다
- [ ] 단계 4 적재 검증(하드 게이트)을 통과했다
- [ ] 실측 스토리지 용량으로 §3 표를 갱신했다
