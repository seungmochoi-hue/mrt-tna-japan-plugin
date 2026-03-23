# BigQuery 규칙

- 기본 프로젝트: `mrtdata`. Dataset: prod = `edw_{domain}`.
- 쿼리 시 파티션 필터 필수, LIMIT 필수 (기본 10건). SELECT 문만 허용. **enforcement**: SELECT 제한 및 DML/DDL 차단은 `bq-query-guard.sh/.ps1` hook이 자동 적용. 파티션 필터와 LIMIT은 agent가 쿼리 작성 시 준수.
- 데이터 사이즈가 큰 테이블은 필요한 수준의 날짜/데이터 범위만 쿼리하도록 최선을 다한다. LOG 테이블(`*_log`, `*_LOG` 등)은 이 규칙이 필수로 적용된다.
- `DW_BIZ_LOG` 조회는 `basis_dt` 기준 최대 7일 범위만 허용한다. 검증 가능한 날짜 조건이 없으면 hook에서 실행을 차단한다.

## 데이터셋 우선순위

- 기본 소스는 배치 데이터셋(`edw_mart`, `edw_air`, `edw_fpna` 등)을 사용한다.
- `edw_stream` 데이터셋은 **당일(오늘) 데이터를 포함한 추출/분석 요청**에만 사용한다. 그 외 요청에서는 사용하지 않는다.
- 사용자가 명시적으로 `edw_stream`을 지정하거나, "실시간", "오늘 데이터 포함" 등 당일 데이터가 필요한 맥락이 있을 때만 `edw_stream`을 사용한다.
- **의사결정 트리**: 당일 데이터 필요? → YES: `edw_stream` 사용 / NO: 배치 데이터셋(`edw_mart` 등) 사용. `edw_stream`과 배치 데이터셋은 집계 기준이 다를 수 있으므로 교차 비교 시 주의.

## 테이블/컬럼 사전 확인 (lookup-first 원칙)

처음 쿼리하는 테이블은 반드시 아래 순서를 따른다. 추정으로 바로 쿼리하지 않는다.

1. **데이터셋 확인** — 테이블이 어느 dataset에 있는지 모르면 `list-tables` MCP 도구 또는 `INFORMATION_SCHEMA.TABLES`로 먼저 검색
2. **스키마 확인** — 컬럼명을 모르면 `describe-table` MCP 도구 또는 `INFORMATION_SCHEMA.COLUMNS`로 먼저 조회
3. **본 쿼리 실행** — 확인된 dataset/column으로 쿼리

- 세션 내 이미 확인한 테이블은 재확인 불필요
- 쿼리 템플릿은 `bigquery-mcp` skill 참조

## bq CLI 필수 옵션

`bq query` 실행 시 반드시 `--location=asia-northeast3` 포함:

```
./.claude/hooks/run-bq-readonly.sh bq query --use_legacy_sql=false --location=asia-northeast3 --format=prettyjson --max_rows=10 "쿼리"
```

운영체제별 wrapper 경로:

```bash
# macOS / Linux / Git Bash
./.claude/hooks/run-bq-readonly.sh bq query --use_legacy_sql=false --location=asia-northeast3 "쿼리"
```

```powershell
# Windows PowerShell
& '.claude/hooks/run-bq-readonly.ps1' bq query --use_legacy_sql=false --location=asia-northeast3 "쿼리"
```

## 날짜 기준

- 오늘 날짜는 KST(Asia/Seoul) 기준으로 판단한다. 세션 시작 시 `date -u -v+9H +%Y-%m-%d` 등으로 정확히 확인한다.
- **배치 데이터셋에서는 오늘 날짜의 데이터를 항상 제외한다.** 배치 파이프라인 특성상 당일 데이터는 미적재/불완전하다.
- `edw_stream`을 사용하는 명시적 당일 데이터 요청만 오늘 날짜 포함을 예외로 허용한다.
- "최근 N일"은 배치 데이터셋 기준으로 오늘을 제외한 직전 N일을 의미한다. 예: 오늘이 2월 28일이고 "최근 7일"이면 `date_id BETWEEN '2025-02-21' AND '2025-02-27'`.
- **날짜→요일 매핑 금지**: 날짜별 결과에 요일을 표시할 때는 반드시 쿼리에서 요일을 직접 추출한다. `DATE` 컬럼이면 `FORMAT_DATE('%a', date_column) AS day_of_week`를 사용하고, `TIMESTAMP`/`DATETIME`이면 컬럼 타입에 맞는 `FORMAT_*` 함수를 사용한다. 문자열/정수 날짜 키는 먼저 `DATE`로 변환한 뒤 요일을 추출한다. LLM이 날짜→요일을 직접 계산하거나 추측하지 않는다. 전주 비교 시에도 동일하게 쿼리 결과의 요일을 사용한다.
