---
name: csv-summarizer
description: CSV 파일 또는 BigQuery 쿼리 결과를 pandas로 종합 분석한다. EDA, 프로파일링, 통계 요약, 분포 분석, 상관관계 파악을 수행. Use when user uploads CSV, asks to analyze/summarize/profile tabular data, or requests exploratory data analysis.
---

# CSV Data Summarizer

> **핵심 원칙: 분석을 즉시 실행한다.** "어떤 분석을 원하시나요?", "옵션을 선택해주세요" 금지.
> 데이터를 받으면 바로 전체 분석 수행.

**NOT for**: 단순 쿼리 실행(-> `bq-query`), dbt 모델 분석(-> `analyze-model`)

---

## 데이터 소스

### 로컬 CSV

```python
import pandas as pd
df = pd.read_csv('/path/to/file.csv')
```

### BigQuery 결과

```bash
# macOS / Linux / Git Bash
./.claude/hooks/run-bq-readonly.sh bq query --use_legacy_sql=false --location=asia-northeast3 --format=csv --max_rows=100000 \
  'SELECT ... FROM ... WHERE ... LIMIT ...' > /tmp/bq_result.csv

# Windows PowerShell
& '.claude/hooks/run-bq-readonly.ps1' bq query --use_legacy_sql=false --location=asia-northeast3 --format=csv --max_rows=100000 `
  'SELECT ... FROM ... WHERE ... LIMIT ...' > "$env:TEMP\bq_result.csv"
```

```python
df = pd.read_csv('/tmp/bq_result.csv')
```

BigQuery 쿼리 시 `bq-query` skill + `bigquery-rules.md` 규칙 적용.

---

## 분석 절차 (자동 전부 수행)

### Step 1: 데이터 구조

```python
print(f"Shape: {df.shape[0]:,} rows x {df.shape[1]} columns")
print(f"\nColumn Types:\n{df.dtypes}")
print(f"\nFirst 5 rows:\n{df.head()}")
```

### Step 2: 기술 통계

```python
df.describe()                    # 수치형
df.describe(include='object')    # 범주형
```

### Step 3: 결측치

```python
missing = df.isnull().sum()
missing_pct = (missing / len(df) * 100).round(2)
pd.DataFrame({'count': missing, 'pct': missing_pct}).query('count > 0').sort_values('pct', ascending=False)
```

### Step 4: 데이터 유형별 적응 분석

| 감지 조건 | 추가 분석 |
|----------|----------|
| 날짜 컬럼 | 시계열 트렌드 (일/주/월별 집계) |
| 수치 컬럼 2개+ | 상관관계 |
| 범주 컬럼 | 빈도 분포 (Top 10 + 기타) |
| 금액/매출 컬럼 | 합계, 평균, 중앙값, 분위 |
| 수치 컬럼 (이상치) | IQR 기반 이상치 탐지 (Q1-1.5*IQR ~ Q3+1.5*IQR 범위 밖), 이상치 비율 |
| ID 컬럼 | unique count, 중복 검사 |

### Step 5: 인사이트 도출

패턴/트렌드, 이상치, 데이터 품질 이슈, 후속 분석 제안을 비즈니스 맥락에서 해석.

---

## 출력 구조

1. **결론** (두괄식 1-2문장)
2. **데이터 개요** (shape, 타입, 기간)
3. **기술 통계** (표)
4. **결측치 현황** (표)
5. **주요 분포/트렌드** (해석)
6. **인사이트** (비즈니스 맥락)
7. **후속 옵션** (`response-format.md` 규칙 따름)

---

## 실행 환경

- macOS / Linux / Git Bash는 `python3`, Windows PowerShell은 `python`으로 실행
- 패키지 없으면 macOS / Linux는 `pip3 install pandas`, Windows는 `pip install pandas` 안내

## 연계 Skill

| 상황 | 연계 |
|------|------|
| BigQuery 데이터 추출 | `bq-query` |
| 결과 Google Sheets 내보내기 | `save-to-gsheets` |
| dbt 모델 로직 파악 | `analyze-model` |
