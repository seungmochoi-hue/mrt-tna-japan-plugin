---
name: analyze-model
description: dbt 모델의 SQL과 YAML을 체계적으로 읽고 로직을 파악하는 분석 skill. 모델 구조 이해, 데이터 탐색, 영향도 분석 시 사용. Use when analyzing dbt model logic, exploring data sources, or evaluating change impact.
---

# Analyze dbt Model

> **모델(.sql)과 YAML은 반드시 함께 읽는다.** 둘 중 하나만 읽고 판단하면 불완전하다.

## When to Use

- 모델 로직 / 비즈니스 의도 파악
- 소스 데이터 탐색 및 프로파일링
- 모델 변경 전 영향도 평가
- 데이터 품질 이슈 조사

**NOT for**: 모델 개발/수정, 테스트 작성, 리팩토링

---

## Analysis Procedure

사용자가 특정 단계만 요청하면 해당 단계만 수행한다.

### Step 1: 모델 파일 탐색

`mrt_dbt/models/` 하위에서 SQL + 같은/인접 경로의 YAML(.yml/.yaml) 확인. 못 찾으면 사용자에게 확인.

### Step 2: YAML 읽기

| 항목 | 확인 내용 |
|------|----------|
| `description` | 모델 목적, 비즈니스 의도 |
| column `description` | 컬럼 의미, 계산 로직, 분기 조건 |
| `meta` | 비즈니스 규칙, 갱신 주기 |
| `tests` | 데이터 제약조건 (unique, not_null, accepted_values 등) |

미정의 컬럼은 기록해둔다.

### Step 3: SQL 로직 분석

1. **config**: materialized, partition_by, cluster_by, tags, incremental_strategy
2. **CTE 구조**: 각 CTE 역할 (staging, filtering, aggregation, join, pivot 등). **분석 깊이**: 최상위 CTE만 역할 정의하고, nested subquery나 매크로 내부 CTE는 해당 CTE가 핵심 로직에 직접 관여할 때만 분석한다.
3. **핵심 로직**: WHERE, CASE WHEN, 집계/윈도우 함수
4. **의존성**: `ref()`, `source()` -> upstream 모델/소스
5. **매크로**: 커스텀 매크로 호출 시 매크로 내용도 확인. **분석 경계**: 매크로가 다른 매크로를 호출하는 경우 1단계까지만 추적. 그 이상은 "추가 분석 필요"로 표기.
6. **하드코딩**: 매직 넘버, 하드코딩 날짜/ID/문자열 -> 유지보수 이슈로 기록

### Step 4: 의존성 / Lineage

```bash
# Upstream
cd mrt_dbt && dbt ls --select +<model_name> --output name
# Downstream
cd mrt_dbt && dbt ls --select <model_name>+ --output name
```

dbt ls 불가 시 SQL 내 `ref()`/`source()` + Grep 검색으로 대체. Grep도 결과가 없으면 "lineage 자동 탐색 실패 — 모델명을 직접 알려주시면 확인 가능합니다"로 안내. downstream 10+ 시 직접/간접 분류.

### Step 5: BigQuery 데이터 검증 (선택)

| 확인 항목 | 쿼리 목적 |
|----------|----------|
| 메타데이터 | row count, 파티션 범위, 테이블 크기 |
| 샘플 데이터 | 최근 10건 (기본 LIMIT 10, 컬럼 수 20+ 시 LIMIT 5로 축소) |
| 컬럼 분포 | distinct count, NULL 비율, 상위 빈도값 |
| 데이터 기간 | 파티션 min/max, 최신 적재일 |
| grain 검증 | PK 기준 중복 여부 |

쿼리 시 `bq-query` skill + `bigquery-rules.md` 규칙 적용.

---

## Data Discovery (소스 탐색 시 추가)

1. 소스 목록: `dbt ls --select "source:<name>.*" --output json`
2. 샘플링: 각 테이블 50건 내외
3. Grain: "[entity] 당 [시간단위] 1건인가?"
4. PK 검증: 유일성/NULL 확인
5. 관계 매핑: FK, orphan record
6. Soft delete: `deleted_at`, `is_active`, `status` 필터링 컬럼 존재 여부

---

## Output Format

### 개요

| 항목 | 값 |
|------|---|
| 모델명 / 파일 경로 | |
| 레이어 | staging / intermediate / marts |
| materialized / partition_by / cluster_by | |

### 핵심 로직 요약 (3-5줄)

### CTE 구조

| CTE명 | 역할 | 참조 모델/소스 |
|--------|------|--------------|

### 컬럼 정의

| 컬럼명 | 타입 | 설명 | 비고 |
|--------|------|------|------|

YAML 미정의 컬럼은 비고에 표시.

### Lineage (ASCII 다이어그램, Mermaid 금지)

```
upstream_1 ──┐                  ┌──> downstream_1
             ├──> TARGET_MODEL ─┤
upstream_2 ──┘                  └──> downstream_2
```

### 의존성

- **Upstream**: 참조하는 모델 목록
- **Downstream**: 참조받는 모델 목록

### Sample Data (최근 5-10건)

### 데이터 현황 (총 row 수, 데이터 기간, 최신 적재일)

### 주의사항 (하드코딩, 미정의 컬럼, 복잡한 조인, row explosion 등)

---

## Impact Evaluation

| 수준 | 기준 | 대응 |
|------|------|------|
| Low | downstream 1-5개 | 변경 진행 |
| Medium | downstream 6-15개 | 영향 모델 목록 확인 후 진행 |
| High | downstream 16개+ | 사용자와 범위 협의 |

컬럼 변경/삭제 시:
```bash
grep -r "column_name" mrt_dbt/models/ --include="*.sql"
```

---

## Red Flags -- STOP and Verify

- SQL만 읽고 YAML 건너뛰려 할 때
- 컬럼명만 보고 의미 추측하려 할 때
- 데이터 확인 없이 분포/건수 추측하려 할 때
- upstream 미확인 상태로 로직 판단하려 할 때
