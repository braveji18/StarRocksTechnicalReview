# 규모별 프로파일

측정 규모에 따라 달라지는 **하네스 설정**을 모아둔 곳이다.
엔진(Trino/StarRocks) 쪽 메모리·CPU 설정은 여기가 아니라 각 배포 도구에서 바꾼다.
어디를 바꾸는지와 값 산출 근거는 [docs/10](../../docs/10-scaling-guide.md) 참조.

```bash
scripts/13-apply-profile.sh medium      # env/.env 에 병합
scripts/13-apply-profile.sh medium --show   # 적용될 값만 출력
```

| 프로파일 | SF | 용도 |
|---|---|---|
| `smoke` | 0.01 | 스크립트 검증. 채점 불가 |
| `small` | 100 | 채점 최소 요건 |
| `medium` | 300 | 동시성·확장성 포함 표준 채점 |
| `large` | 1000 | 대용량 조인·스필·고동시성 |

프로파일은 `env/.env` 를 덮어쓰지 않고 **해당 키만 병합**한다.
접속 정보(호스트/포트/자격증명)는 프로파일이 건드리지 않는다.
