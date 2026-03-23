---
name: bq-query
description: bq CLI로 BigQuery 쿼리를 실행하는 skill. 쿼리 실행, dry-run, 비용 제어, 출력 형식 제어, 파라미터화 쿼리. Use when executing BigQuery queries via bq command-line tool.
---

# bq Query

> **제약 규칙은 `bigquery-rules.md`를 따른다.** 이 skill은 bq CLI 사용법에 집중한다.

**전제 조건**: `gcloud auth login` 완료 (미인증 시 `gcloud-auth` skill 참조)

## 쿼리 전: 테이블 구조 확인

처음 접하는 테이블이면 `bq show`로 파티션/클러스터링 구조를 먼저 확인한다.

```bash
./.claude/hooks/run-bq-readonly.sh bq show --format=prettyjson mrtdata:<dataset>.<table> 2>&1
```

| 확인 항목 | JSON 경로 | 역할 |
|-----------|-----------|------|
| 파티션 컬럼 | `timePartitioning.field` / `rangePartitioning.field` | WHERE 필터 필수 |
| 클러스터링 | `clustering.fields[]` | WHERE/ORDER BY에 쓰면 스캔량 감소 |
| 파티션 타입 | `timePartitioning.type` | 날짜 형식 결정 |

## 쿼리 전: 필터 값 선확인

enum 성격 컬럼(`status`, `type`, `category`, `domain`, `channel` 등)은 추측하지 않고 실제 분포를 먼저 확인한다. 같은 세션에서 이미 확인한 값은 재확인 생략.

```sql
SELECT <column>, COUNT(*) AS cnt
FROM `mrtdata.<dataset>.<table>`
WHERE <partition_col> >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY 1 ORDER BY 2 DESC LIMIT 20
```

## 기본 실행

```bash
./.claude/hooks/run-bq-readonly.sh bq query \
  --use_legacy_sql=false \
  --location=asia-northeast3 \
  --format=pretty \
  --max_rows=10 \
  'SELECT * FROM `mrtdata.edw_fpna.MART_FPNA_AIR_PROFIT_D` WHERE date_id >= "2025-01-01" LIMIT 10'
```

### 출력 제어 플래그

| 플래그 | 설명 | 기본값 |
|--------|------|--------|
| `--format` | `pretty` / `json` / `csv` / `prettyjson` | pretty |
| `--max_rows` | 최대 반환 행 수 | 100 |
| `--dry_run` | 실행 없이 스캔량만 확인 | false |
| `--maximum_bytes_billed` | 비용 안전망 (초과 시 실패) | 없음 |

## dry-run

대용량 테이블 쿼리 시 반드시 먼저 수행한다.

```bash
./.claude/hooks/run-bq-readonly.sh bq query --dry_run --use_legacy_sql=false --location=asia-northeast3 \
  'SELECT order_id, amount FROM `mrtdata.edw_mart.FACT_ORDER` WHERE date_id >= "2025-01-01" LIMIT 10'
```

## 비용 절감

1. **필요한 컬럼만 SELECT** — columnar 저장이므로 `SELECT *` 지양.
2. **파티션 필터는 상수 표현식** — 컬럼에 함수 씌우면 전체 스캔.
   ```sql
   -- Good: WHERE date_id >= '2025-01-01'
   -- Bad:  WHERE DATE_ADD(date_id, INTERVAL 5 DAY) > '2025-01-01'
   ```
3. **`--maximum_bytes_billed`** — 예상치 못한 대용량 스캔 방지.
4. **LIMIT의 한계** — 비클러스터드 테이블에서는 스캔 자체를 줄이지 않음. 파티션 필터와 컬럼 선택이 핵심.

## 파라미터화 쿼리

```bash
./.claude/hooks/run-bq-readonly.sh bq query \
  --use_legacy_sql=false \
  --location=asia-northeast3 \
  --parameter='target_date:DATE:2025-01-15' \
  --parameter='min_amount:INT64:1000' \
  'SELECT order_id, amount
   FROM `mrtdata.edw_mart.FACT_ORDER`
   WHERE date_id = @target_date AND amount >= @min_amount
   LIMIT 10'
```

형식: `name:type:value` (타입: `STRING`, `INT64`, `FLOAT64`, `BOOL`, `DATE`, `TIMESTAMP`, `DATETIME`, `NUMERIC`)

## 쿼리 템플릿

### 스키마 조회

```bash
./.claude/hooks/run-bq-readonly.sh bq query --use_legacy_sql=false --location=asia-northeast3 \
  'SELECT column_name, data_type, is_nullable
   FROM `mrtdata.<dataset>.INFORMATION_SCHEMA.COLUMNS`
   WHERE table_name = "<table>" ORDER BY ordinal_position'
```

### 샘플 데이터

```bash
./.claude/hooks/run-bq-readonly.sh bq query --use_legacy_sql=false --location=asia-northeast3 --max_rows=10 \
  'SELECT * FROM `mrtdata.<dataset>.<table>`
   WHERE <partition_col> >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
   ORDER BY <partition_col> DESC LIMIT 10'
```
