"""SQL 파일/템플릿 파싱 유틸리티."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from . import config

_VAR = re.compile(r"\$\{(\w+)\}")


def render(text: str, extra: dict[str, str] | None = None) -> str:
    """${VAR} 치환. 미정의 변수는 즉시 오류로 알린다."""
    subs = config.substitutions()
    if extra:
        subs.update(extra)

    def repl(m: re.Match[str]) -> str:
        key = m.group(1)
        if key not in subs:
            raise KeyError(f"SQL 템플릿에 정의되지 않은 변수: ${{{key}}}")
        return subs[key]

    return _VAR.sub(repl, text)


def strip_comments(sql: str) -> str:
    out = []
    for line in sql.splitlines():
        stripped = line.strip()
        if stripped.startswith("--"):
            continue
        out.append(line)
    return "\n".join(out)


def split_statements(sql: str) -> list[str]:
    """세미콜론 기준 분리. 문자열 리터럴 안의 ';' 를 보호한다."""
    statements, buf, in_str = [], [], False
    i = 0
    while i < len(sql):
        ch = sql[i]
        if ch == "'":
            # '' 이스케이프 처리
            if in_str and i + 1 < len(sql) and sql[i + 1] == "'":
                buf.append("''")
                i += 2
                continue
            in_str = not in_str
            buf.append(ch)
        elif ch == ";" and not in_str:
            stmt = "".join(buf).strip()
            if stmt:
                statements.append(stmt)
            buf = []
        else:
            buf.append(ch)
        i += 1
    tail = "".join(buf).strip()
    if tail:
        statements.append(tail)
    return statements


def load_template(path: Path, extra: dict[str, str] | None = None) -> list[str]:
    """DDL 템플릿을 치환한 뒤 실행 가능한 문장 목록으로 반환."""
    rendered = render(path.read_text(encoding="utf-8"), extra)
    return split_statements(strip_comments(rendered))


def load_query_set(directory: Path) -> list[tuple[str, str]]:
    """벤치마크 쿼리 디렉터리를 (쿼리명, SQL) 목록으로 로드."""
    files = sorted(p for p in directory.glob("*.sql"))
    result = []
    for f in files:
        text = f.read_text(encoding="utf-8").strip().rstrip(";")
        result.append((f.stem, text))
    return result


# --- 기능 체크리스트 블록 파서 ------------------------------------------------

_CHECK = re.compile(r"^--\s*@check\s+(?P<body>.+)$")
_FALLBACK = re.compile(r"^--\s*@fallback(?:\s+engine=(?P<engine>\w+))?\s*$")


@dataclass
class Check:
    check_id: str
    category: str
    description: str
    sql: str
    engine: str | None = None          # 지정 시 해당 엔진에서만 실행
    manual: bool = False               # SQL 로 판정 불가 - 검토자가 직접 기재
    fallbacks: dict[str, str] = field(default_factory=dict)  # engine|'*' -> sql
    source: str = ""

    def fallback_for(self, engine: str) -> str | None:
        return self.fallbacks.get(engine) or self.fallbacks.get("*")


def parse_checks(path: Path) -> list[Check]:
    checks: list[Check] = []
    current: Check | None = None
    buf: list[str] = []
    fb_engine: str | None = None
    fb_buf: list[str] = []
    mode = "sql"

    def flush() -> None:
        nonlocal current, buf, fb_buf, fb_engine, mode
        if current is None:
            return
        if mode == "fallback":
            current.fallbacks[fb_engine or "*"] = "\n".join(fb_buf).strip()
        else:
            current.sql = "\n".join(buf).strip()
        checks.append(current)
        current, buf, fb_buf, fb_engine, mode = None, [], [], None, "sql"

    for raw in path.read_text(encoding="utf-8").splitlines():
        m = _CHECK.match(raw.strip())
        if m:
            flush()
            parts = [p.strip() for p in m.group("body").split("|")]
            check_id = parts[0]
            category = parts[1] if len(parts) > 1 else "misc"
            description = parts[2] if len(parts) > 2 else ""
            engine, manual = None, False
            for opt in parts[3:]:
                if opt.startswith("engine="):
                    engine = opt.split("=", 1)[1]
                elif opt in ("mode=manual", "manual"):
                    manual = True
            current = Check(check_id=check_id, category=category,
                            description=description, sql="", engine=engine,
                            manual=manual, source=path.name)
            buf, fb_buf, fb_engine, mode = [], [], None, "sql"
            continue

        fb = _FALLBACK.match(raw.strip())
        if fb and current is not None:
            if mode == "fallback":
                current.fallbacks[fb_engine or "*"] = "\n".join(fb_buf).strip()
            else:
                current.sql = "\n".join(buf).strip()
            mode, fb_engine, fb_buf = "fallback", fb.group("engine"), []
            continue

        if current is None:
            continue
        (fb_buf if mode == "fallback" else buf).append(raw)

    flush()
    return checks


def load_all_checks(directory: Path) -> list[Check]:
    checks: list[Check] = []
    for f in sorted(directory.glob("*.sql")):
        checks.extend(parse_checks(f))
    return checks
