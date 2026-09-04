# 수동 입력 양식

자동 측정으로 얻을 수 없는 항목의 기록 양식이다. 채운 뒤 아래 위치로 복사하면
`scripts/12-score.sh` 가 채점에 반영한다.

| 양식 | 복사 위치 | 근거 문서 |
|---|---|---|
| `operability_scores.csv` | `results/operability/operability_scores.csv` | [docs/06](../../docs/06-operability-test.md) |
| `fault_injection.csv` | `results/operability/fault_injection.csv` | [docs/06 §5](../../docs/06-operability-test.md#5-장애-주입-시나리오-안정성-10점) |
| `scalability.csv` | `results/operability/scalability.csv` | [docs/05 §4](../../docs/05-performance-test.md#4-확장성-측정-확장성-10점) |
| `p4_bulk.csv` | `results/performance/p4_bulk.csv` | [docs/05 §P4](../../docs/05-performance-test.md#p4-대용량-처리-배점-5) |
| `cost_tco.csv` | `results/cost/cost_tco.csv` | [docs/07](../../docs/07-cost-model.md) |
| `knockout.csv` | `results/scoring/knockout.csv` | [docs/01 §4](../../docs/01-evaluation-criteria.md#4-결격-조건-knock-out) |

`fault_injection.csv` 의 `verdict` 는 아래 값만 사용한다 (다른 값은 채점에서 경고 처리).

| verdict | 점수 |
|---|---:|
| `무중단+쿼리보존` | 1.67 |
| `무중단+쿼리실패` | 1.0 |
| `자동복구+일시중단` | 0.5 |
| `수동개입필요` | 0 |
| `데이터유실` | 0 (결격 조건 K3 검토) |
