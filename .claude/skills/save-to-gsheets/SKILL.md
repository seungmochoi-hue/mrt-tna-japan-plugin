---
name: save-to-gsheets
description: 쿼리 결과나 분석 데이터를 Google Sheets에 내보낸다. Use when user asks to save, download, export, or store data/query results.
---

# Save to Google Sheets

## 절차

1. **범위 확인**: 사용자가 저장 범위를 명시하지 않았으면 먼저 아래 중 하나를 짧게 확인한다.

   - `세션 전체`
   - `특정 결과만` (예: "방금 쿼리 결과", "두 번째 분석 결과")

   예: `세션에서 조회한 데이터 중 어떤 것을 내보낼까요? (전체 / 특정 결과 지정)`

   **모호한 답변 처리**: 사용자가 "최근 3개", "아까 그거" 등 모호하게 답하면, 세션 내 쿼리 결과 목록을 번호와 함께 보여주고 선택하게 한다.

2. **저장할 데이터 확인**: 직전 쿼리 결과 또는 사용자가 지정한 특정 결과를 사용한다. 저장 대상이 없으면 쿼리를 먼저 실행한다.

3. **행 수 기준 분기**:

   - **50행 미만** → Step 4 (Google Sheets MCP로 저장)
   - **50행 이상** → Step 5 (로컬 CSV 다운로드)
   - 사용자가 명시적으로 "구글시트에 저장"이라고 한 경우에만 행 수와 무관하게 Google Sheets로 저장한다.

4. **Google Sheets 생성/저장** (50행 미만): Google Sheets MCP 도구로 스프레드시트에 저장한다.

   - **스프레드시트 생성**: `mcp__gsheets__create_spreadsheet`로 새 스프레드시트 생성
     - 제목: `{주제}_{YYYYMMDD}` (KST 기준)
   - **탭 확인**: 생성 직후 `mcp__gsheets__list_sheets`로 기본 탭명을 확인한다.
     - 기본 탭이 그대로면 그 탭에 기록한다.
     - 탭명을 바꾸고 싶으면 `mcp__gsheets__rename_sheet`로 `results` 같은 이름으로 변경한 뒤 사용한다.
   - **데이터 입력**: 확인한 탭명으로 `mcp__gsheets__update_cells`를 호출해 데이터 입력
     - 데이터 형식: `data` 파라미터에 2D 배열 (`[[헤더1, 헤더2, ...], [값1, 값2, ...], ...]`)
     - 첫 행: 헤더 (컬럼명)
     - 이후 행: 데이터
     - 입력 범위: `{탭명}!A1` (기본)
   - **서식 적용** (선택):
     - 헤더 행 bold 처리
     - 숫자 컬럼에 천 단위 쉼표 포맷
   - **전체공유 설정** (필수): 데이터 입력 직후, 반드시 아래 스크립트를 실행하여 조직 전체(`myrealtrip.com`)에 편집(writer) 권한으로 공유한다.
     ```bash
     # macOS / Linux / Git Bash
     ./.claude/hooks/share-gsheet.sh {spreadsheet_id}
     ```
     ```powershell
     # Windows PowerShell
     & '.claude/hooks/share-gsheet.ps1' '{spreadsheet_id}'
     ```
     - 출력이 `OK:`로 시작하면 성공. `ERROR:`로 시작하면 ADC 재인증 후 1회 재시도.
     - **이 단계를 건너뛰지 않는다.** 링크를 공유하기 전에 반드시 전체공유가 설정되어야 한다.
   - **결과 보고**: 간결하게 한 줄로 안내한다. "포함된 데이터", "데이터 설명" 같은 부가 설명을 붙이지 않는다.
     - 예: "Google Sheets에 저장했어요! 🔗 [제목](URL) (`results` 탭, `N`행, 조직 전체 공유 완료)"

5. **로컬 CSV 다운로드** (50행 이상): bq query의 `--format=csv`로 CSV 파일을 OS별 Downloads 폴더에 저장한다.

   ```bash
   # macOS
   ./.claude/hooks/run-bq-readonly.sh bq query --use_legacy_sql=false --location=asia-northeast3 --format=csv --max_rows=1000000 "쿼리" > ~/Downloads/{주제}_{YYYYMMDD_HHMMSS}.csv

   # Windows (PowerShell)
   & '.claude/hooks/run-bq-readonly.ps1' bq query --use_legacy_sql=false --location=asia-northeast3 --format=csv --max_rows=1000000 "쿼리" > "$HOME\Downloads\{주제}_{YYYYMMDD_HHMMSS}.csv"
   ```

   - 파일명: `{주제}_{YYYYMMDD_HHMMSS}.csv` (KST 기준, 한글 포함 가능, 공백은 `_`로 대체)
   - **결과 보고**: 파일 경로, 행 수, 파일 크기를 안내한다.
     - 예: "CSV로 저장했어요! `~/Downloads/항공_거래액_20260320_143000.csv` (`1,234`행, `256KB`)"

## 인증 에러 처리

Google Sheets MCP 도구 호출 시 인증 에러가 발생하면 `.claude/rules/mcp-auth-recovery.md`의 Google Sheets 절차를 따른다.

## 규칙

- 10만 행 초과 예상 시 dry-run으로 규모 알려주고 확인 후 실행.
- Google Sheets 행 제한 (약 1,000만 셀). 초과 예상 시 사용자에게 알린다.
- 쿼리 규칙(`bigquery-rules.md`) 동일 적용.
- 별도 중간 agent를 거치지 않고 이 skill이 직접 범위 확인부터 저장까지 처리한다.
