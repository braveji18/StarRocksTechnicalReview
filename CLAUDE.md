# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

The procedure (절차서) **and the executable harness** for a technical evaluation comparing
**StarRocks** and **Trino**. `docs/` defines what is measured and how it is scored; `bench/`,
`scripts/`, `sql/`, and `env/` actually run it. There is no product code here — the deliverable
is the evaluation itself.

## Language and style

All documents are in **Korean**; code comments and CLI output are Korean too. Match the existing
conventions: numbered sections (`## 1. 목적`, `### 5.1 …`), tables over prose for anything holding
a measurement or judgment, and a `## 완료 조건` (exit criteria) checklist ending each doc.

## Commands

```bash
cp env/.env.example env/.env
scripts/00-preflight.sh                       # tooling check + dependency install
scripts/01-env-up.sh all                      # local smoke stack (docker compose)
scripts/03-load-dataset.sh --normalize --preagg
scripts/04-verify-dataset.sh                  # exits 1 on checksum mismatch — hard gate
scripts/05-run-functional.sh
scripts/06-run-p1.sh <engine> <track> <cold|warm> [suite]
scripts/07-run-p2.sh <engine> <track>         # dashboard, compared against SLA
scripts/08-run-p3.sh <engine> <track>         # concurrency
scripts/09-run-p6.sh <engine> <track>         # resource efficiency via Prometheus
scripts/11-fault-inject.sh <engine> F1..F6    # fault scenarios under load
scripts/12-score.sh --primary-track B         # mechanical scoring
scripts/13-apply-profile.sh <smoke|small|medium|large>   # scale profile
scripts/run-all.sh smoke|measure
```

Run a single query set or check: `python -m bench.run_latency --engine trino --queries q01,q06`,
`python -m bench.run_functional --filter F-0,F-4`.

`scripts/00-preflight.sh` prefers `.venv`, and falls back to `.pylibs` (pip `--target`) where
`python3-venv` is unavailable. `scripts/lib/common.sh:require_venv` resolves whichever exists.

## Architecture

- `bench/engines.py` — the load-bearing abstraction. `TrinoEngine` (HTTP, `trino` client) and
  `StarRocksEngine` (MySQL protocol, `pymysql`) behind one `Engine` interface, so both engines are
  driven through an identical client path. Track selection happens here via session context, not
  via different SQL.
- `bench/sqlfile.py` — `${VAR}` template rendering, quote-aware statement splitting, and the
  `-- @check` / `-- @fallback` block parser for the functional checklist.
- `bench/score.py` — reads only `results/**.csv` and applies the docs/01 formulas.
- Runners (`run_latency`, `run_concurrency`, `run_functional`, `run_resource`, `verify_dataset`,
  `load_dataset`) each call `Engine.ping()` before measuring.

## Design invariants

Decisions already made. Preserve them; do not silently relax them.

- **2-track comparison** ([docs/02 §4](docs/02-test-environment.md)) — Track A has both engines read
  the *same* Iceberg tables; Track B lets each use its optimal configuration. The engines differ in
  kind (Trino is storage-less federation, StarRocks an MPP OLAP DB with native storage), so a
  single-track comparison is biased. Never collapse the tracks, never mix them (performance from
  Track B with storage cost from Track A).
- **One portable query set.** `sql/tpch/` is a single set both engines run unmodified — dates are
  precomputed literals, `year()`/`substr()` replace dialect-specific forms, Q15's view is a CTE, and
  table names are unqualified so session context selects the track. Per-engine query files would
  reintroduce "different SQL" as a confound. All 22 are verified to run on both engines.
- **Symmetric tuning.** If StarRocks gets MVs in Track B, Trino gets equivalent pre-aggregated
  tables (`sql/ddl/31-trino-preagg.sql`). Asymmetric tuning must be recorded in the result table.
- **Functional check sets must stay equal across engines** (currently 63 items each). An
  `engine=`-limited block needs a counterpart on the other engine, or it only inflates that
  engine's denominator.
- **Fallback SQL means 부분지원, not 미지원.** When standard syntax fails but engine-specific syntax
  works, that is 1 point — the need for a workaround *is* the finding. Verify a fallback really
  fails before scoring 미지원.
- **Client wall-clock is the primary metric**; engine-reported stats are supplementary and
  asymmetric (Trino always, StarRocks only with AuditLoader). Never fill missing stats with 0.
- **Cache state and track are recorded on every performance row**; unlabeled numbers are void.
- **Failed queries take the timeout value**, are flagged, and are not dropped from averages.
- **Scoring is mechanical** — every point traces to a CSV row through a stated formula. No
  subjective score fields, no manual adjustment path.
- **Knock-outs (K1–K5)** override total score; thresholds are fixed at kickoff.
- **Equal query-available memory, not just equal container memory.** StarRocks BE is C++ with no
  JVM headroom, so identical container sizes hand it ~3x more usable query memory than Trino.
  Pin Trino `query.max-memory-per-node` and StarRocks `query_mem_limit` to the *same* value and
  verify actual peak memory before measuring ([docs/10 §4–5](docs/10-scaling-guide.md)).

## Upstream projects under review

- Trino — https://github.com/trinodb/trino.git
- StarRocks — https://github.com/StarRocks/starrocks.git

Neither is vendored. Version-specific behavior (SQL support, licence, config keys) changes between
releases, so the procedure says "fix the version at kickoff and verify at that version" rather than
baking in version claims. Preserve that hedging; `env/.env` is where versions get pinned.

## Related local context

`/home/ubuntu/work/trino/trino-k8s/docs` holds Trino-on-Kubernetes operational notes relevant to
[docs/02](docs/02-test-environment.md) and [docs/06](docs/06-operability-test.md). A running lab
(Trino on :18080, StarRocks FE on :9030, shared `iceberg.bench` schema) may exist on this machine —
see [docs/09 §3.1](docs/09-test-scripts.md) for pointing the harness at it instead of the smoke stack.
