# 측정 결과

> 이 디렉터리의 수치를 읽기 전에 **[measurement-conditions.md](measurement-conditions.md)** 를 먼저 볼 것.
> 현재 결과는 채점용이 아니라 **파이프라인 검증을 겸한 예비 측정**이다.

## 파일

| 파일 | 내용 |
|---|---|
| `measurement-conditions.md` | 측정 조건 및 채점 불가 사유 (필독) |
| `performance-report.md` | 성능 측정 결과 정리 |
| `scoring/final_score.md` | 채점 집계 (측정 항목만 반영, 나머지는 0점 + 경고) |
| `dataset/load_timing.csv` | 적재 단계별 소요 시간 (P5 입력) |
| `functional/dataset_verification.csv` | 두 엔진 행수·체크섬 대조 (하드 게이트) |
| `performance/p1_latency_tpch.csv` | TPC-H 22개 쿼리별 원시 측정값 |
| `performance/p1_summary.csv` | 스위트별 기하평균 요약 |
| `performance/p2_dashboard.csv` | 대시보드 8개 원시 측정값 |
| `performance/p3_concurrency.csv` | 동시성 단계별 원시 측정값 |
| `performance/p3_summary.csv` | 포화점 및 최대 QPS |
| `templates/` | 수동 입력 양식 (운영성·비용·장애·결격 조건) |

## 결과 읽는 법

- 모든 행에 `track`(A/B)과 `cache`(cold/warm)가 붙어 있다. 이 둘이 없는 수치는 무효다.
- 실패한 쿼리는 평균에서 제외되지 않고 타임아웃 값이 대입된 뒤 `status` 에 표기된다.
  따라서 `failed_queries > 0` 인 요약 행의 기하평균은 실패를 포함한 값이다.
- Track A 는 두 엔진이 **같은 Iceberg 테이블**을 읽는다. 엔진 자체의 레이크 조회 성능 비교에 쓴다.
- Track B 는 각 엔진의 최적 구성이다. 실사용 구성 비교에 쓰며, 튜닝 비대칭을 함께 봐야 한다.
