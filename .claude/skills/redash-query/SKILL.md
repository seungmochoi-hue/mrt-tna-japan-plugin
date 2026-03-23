---
name: redash-query
description: Redash 쿼리/대시보드를 URL 기반으로 조회하는 skill. Redash URL이 포함된 메시지 또는 "Redash", "리대시" 키워드 시 사용. API Key 미설정 시 사용자에게 발급 안내 후 로컬 저장.
---

# Redash Query

Redash 쿼리 또는 대시보드를 URL 기반으로 조회한다.

- API wrapper: `.claude/scripts/redash-api.py` (uv run으로 실행)
- 인증: Redash API Key (사용자별 로컬 저장)
- Base URL: `https://redash.myrealtrip.net`

> **Note**: Redash MCP 도구(`mcp__redash__*`)가 별도로 존재하지만, API Key 관리와 에러 핸들링의 일관성을 위해 이 skill은 로컬 Python wrapper를 사용한다.
> Redash API Key는 초기 `setup` skill 범위에 포함되지 않는다. 사용자가 Redash URL을 처음 제공할 때 on-demand로 설정한다.

---

## 전제 조건: API Key 설정

### API Key 확인

skill 실행 전 반드시 API Key 파일 존재 여부를 확인한다.

```bash
test -f .claude/credentials/redash.env && echo "OK" || echo "MISSING"
```

### API Key 미설정 시 — 자동 안내

API Key 파일이 없으면:

1. **브라우저를 바로 열어준다** (사용자에게 묻지 않고 즉시):

```bash
# macOS
open "https://redash.myrealtrip.net/users/me"

# Windows PowerShell
Start-Process "https://redash.myrealtrip.net/users/me"
```

2. 아래 메시지를 **그대로** 출력한다:

```
Redash API Key 페이지를 열어두었어요!

페이지 하단 **API Key** 항목에서 키를 복사해서 여기에 붙여넣어 주세요!
```

### API Key 저장

사용자가 API Key를 제공하면:

1. credentials 디렉토리 생성 (없으면)
2. API Key 파일 작성 + 권한 제한
3. 저장 완료 안내

```bash
mkdir -p .claude/credentials
chmod 700 .claude/credentials
```

`.claude/credentials/redash.env` 파일 내용:

```
REDASH_API_KEY=<사용자가_제공한_키>
```

파일 작성 후 권한 설정:

```bash
chmod 600 .claude/credentials/redash.env
```

저장 후 안내: "Redash API Key 저장 완료! 이어서 조회할게요."

---

## 호출 규칙

| 규칙 | 설명 |
|------|------|
| **URL 필수** | 사용자가 Redash URL을 명시적으로 제공한 경우에만 조회. URL 없이 탐색 금지 |
| **읽기 전용** | 쿼리 정의 조회, 캐시된 결과 확인만 허용. 새 쿼리 생성/수정 불가 |
| **민감 정보 마스킹** | 결과에 credential, 토큰 등이 포함되면 마스킹 후 경고 |

---

## 사용 가능한 명령 — 3개

스크립트 실행 형식:

```bash
uv run .claude/scripts/redash-api.py <command> <args...>
```

### 1. get-query — 쿼리 정의 조회 (실행하지 않음)

```bash
uv run .claude/scripts/redash-api.py get-query "https://redash.myrealtrip.net/queries/31615"
```

반환: 쿼리 이름, SQL, 파라미터, 참조 테이블 목록

### 2. check-query — 쿼리 조회 + 실행 결과 확인

```bash
uv run .claude/scripts/redash-api.py check-query "https://redash.myrealtrip.net/queries/31615" --max-age=3600 --sample-rows=10
```

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `--max-age=N` | 캐시 재사용 허용 시간(초). 3600이면 1시간 내 캐시 사용 | 3600 |
| `--sample-rows=N` | 반환할 샘플 행 수 | 20 |
| `--timeout=N` | job polling 최대 대기 시간(초) | 180 |
| `--parameters='{"name":"value"}'` | 쿼리 파라미터를 JSON으로 직접 전달 | 없음 |

**주의**: `max-age=0`은 Redash 서버에서 쿼리를 새로 실행한다. 무거운 쿼리의 경우 서버 부하를 줄 수 있으므로, 캐시된 결과로 충분한 경우 `max-age=3600` 이상을 사용한다. 기본값은 `3600`.

추가 규칙:

- URL에 `?p_date=2026-03-01&p_country=KR`처럼 파라미터가 붙어 있으면 자동으로 함께 전달한다.
- URL 파라미터와 `--parameters`를 같이 주면 `--parameters` 값이 우선한다.
- 저장된 기본값이 있는 파라미터는 명시값이 없을 때 자동으로 사용한다.

### 3. get-dashboard — 대시보드 위젯/쿼리 목록 조회

```bash
uv run .claude/scripts/redash-api.py get-dashboard "my-dashboard"
```

URL에서 slug 추출도 가능:

```bash
uv run .claude/scripts/redash-api.py get-dashboard "https://redash.myrealtrip.net/dashboard/my-dashboard"
```

반환: 대시보드 이름, 포함된 쿼리 ID/이름/SQL/참조 테이블

---

## 에러 처리

| 에러 | 스크립트 출력 | 동작 |
|------|-------------|------|
| API Key 파일 없음 | `{"error": "API_KEY_NOT_FOUND", ...}` | 위 안내 메시지 출력 후 사용자에게 Key 요청 |
| API Key 비어있음 | `{"error": "API_KEY_EMPTY", ...}` | 같은 안내 |
| HTTP 403 | `{"status_code": 403, ...}` | "API Key가 만료되었거나 권한이 없어요. Redash Settings에서 Key를 재발급해 주세요!" |
| HTTP 404 | `{"status_code": 404, ...}` | "해당 쿼리/대시보드를 찾을 수 없어요. URL을 다시 확인해 주세요!" |
| Job 타임아웃 | `{"timeout": ...}` | "쿼리 실행이 오래 걸리고 있어요. Redash에서 직접 확인해 주세요!" |

---

## 응답 형식

Redash 쿼리 조회 결과는 아래 구조로 정리한다.

```
## Redash 쿼리 정보

- **쿼리 이름**: {name}
- **쿼리 ID**: {query_id}
- **URL**: https://redash.myrealtrip.net/queries/{query_id}

### SQL

​```sql
{sql}
​```

### 참조 테이블
- `{table_1}`
- `{table_2}`

### 파라미터 (있는 경우)
| 이름 | 타입 | 현재 값 |
|------|------|--------|
| {name} | {type} | {value} |
```

`check-query`로 결과 샘플이 있으면 추가:

```
### 실행 결과 (샘플 {N}행 / 전체 {total}행)

| col1 | col2 | ... |
|------|------|-----|
| val  | val  | ... |
```

대시보드 조회 시:

```
## Redash 대시보드 정보

- **대시보드 이름**: {name}
- **URL**: https://redash.myrealtrip.net/dashboard/{slug}
- **포함 쿼리**: {N}개

### 쿼리 목록

| # | 쿼리 ID | 쿼리 이름 | 참조 테이블 |
|---|---------|----------|-----------|
| 1 | {id}    | {name}   | `{table}` |
```

---

## 후속 제안

Redash 쿼리를 조회한 후, 아래 후속 작업을 제안한다.

1. 이 쿼리의 SQL을 BigQuery에서 직접 실행하여 최신 결과 확인
2. 쿼리에서 참조하는 dbt 모델 분석 (lineage, 컬럼 정의)
3. 이 쿼리의 로직을 기반으로 추가 분석 (기간 변경, 필터 추가 등)

---

## 주의사항

- Redash URL 없이 "Redash에서 대시보드 목록 보여줘" 같은 탐색 요청은 지원하지 않는다. URL이 필요하다고 안내한다.
- `check-query`는 캐시 갱신을 트리거할 수 있으므로, 기본적으로 `max-age=3600`을 사용하여 기존 캐시를 활용한다.
- 쿼리 SQL에서 추출한 테이블명은 정규식 기반이므로 CTE 별칭 등 false positive가 있을 수 있다.
