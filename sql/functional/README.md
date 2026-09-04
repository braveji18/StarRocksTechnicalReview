# 기능 체크리스트 SQL

`scripts/06-run-functional.sh` 가 이 디렉터리의 `.sql` 파일을 읽어 두 엔진에서 실행하고
판정 결과를 `results/functional/` 에 기록한다.

## 블록 문법

```
-- @check <ID> | <카테고리> | <설명> [| mode=manual] [| engine=trino|starrocks]
<표준 SQL - 성공하면 '지원'(2점)>
-- @fallback engine=starrocks
<엔진별 우회 SQL - 표준이 실패하고 이것이 성공하면 '부분지원'(1점)>
```

- 표준 SQL 과 우회 SQL 모두 실패하면 **미지원(0점)** 으로 판정하고 에러 메시지를 기록한다.
- `mode=manual` 은 SQL 만으로 판정할 수 없는 항목(설정·연계·보안)이다.
  러너는 판정란을 비운 채 행만 생성하며, 검토자가 직접 채운다.
- `engine=` 이 지정된 블록은 해당 엔진에서만 실행한다.
- 카테고리와 가중치는 [docs/01 §3.1](../../docs/01-evaluation-criteria.md) 을 따른다.
