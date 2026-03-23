---
name: search-gsheets
description: Google Drive에서 특정 주제와 관련된 Google Sheets 스프레드시트를 검색하여 제목·링크와 함께 정리한다. "구글시트에서 찾아줘", "시트 검색", "관련 시트 있나", "스프레드시트 검색" 등 Google Sheets 검색 요청 시 사용한다.
---

# Search Google Sheets — Google Drive 스프레드시트 검색

공통 절차는 `.claude/rules/search-template.md`를 따른다.

## 검색 도구

Google Sheets MCP에는 검색 API가 없으므로, **폴더 탐색 + 제목 매칭**으로 관련 시트를 찾는다.

### 폴더 탐색

1. `list_folders`로 Google Drive 루트의 폴더 목록을 조회한다
2. 폴더 이름에서 주제와 관련된 폴더를 식별한다
3. `list_spreadsheets`로 루트 + 관련 폴더의 스프레드시트 목록을 **병렬로** 조회한다

### 제목 매칭

조회된 스프레드시트 목록에서 검색 키워드와 제목이 매칭되는 시트를 필터링한다.

- 대소문자 무시
- 부분 일치 허용 (제목에 키워드가 포함되면 매칭)
- 한국어/영어 모두 체크

### 시트 요약 (선택)

매칭된 시트가 있으면 `get_multiple_spreadsheet_summary`로 시트 구조(탭 이름, 헤더, 첫 몇 행)를 조회하여 관련성을 확인한다.

## 결과 포맷

```
## 검색 결과: {주제} (Google Sheets)

**1. {스프레드시트 제목}**
- 폴더: {폴더명}
- 시트 탭: {탭1}, {탭2}, ...
- https://docs.google.com/spreadsheets/d/{spreadsheet_id}
```

## 소스 고유 규칙

- 스프레드시트 URL은 `https://docs.google.com/spreadsheets/d/{spreadsheet_id}` 형식으로 구성한다
