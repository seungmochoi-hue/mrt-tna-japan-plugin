# MCP 인증 복구 절차

MCP 도구 호출 시 인증 에러가 발생하면 아래 절차를 따른다.

## Slack MCP 인증 복구

1. Claude Code에서 `/mcp`를 입력한다.
2. Slack 항목의 `Authenticate`를 선택한다.
3. 브라우저가 자동으로 열리면 로그인/권한 동의를 완료한다.
4. 인증 완료 후 원래 작업을 자동 재시도한다.

## Atlassian MCP 인증 복구

1. Claude Code에서 `/mcp`를 입력한다.
2. Atlassian 항목의 `Authenticate`를 선택한다.
3. 브라우저가 자동으로 열리면 로그인/권한 동의를 완료한다.
4. 인증 완료 후 원래 작업을 자동 재시도한다.

## Google Sheets MCP 인증 복구

Google Sheets MCP 에러 시 `gsheets-auth` skill을 자동 실행하여 복구 후 재시도한다 (사용자에게 선택지를 주지 않는다).

## 공통: 브라우저 fallback

- 브라우저가 자동으로 열리지 않으면 터미널에 표시된 URL을 직접 복사해서 브라우저에 붙여넣는다.
- redirect가 connection error로 실패하면 브라우저 주소창의 전체 callback URL을 Claude Code의 URL prompt에 붙여넣는다.

## 공통 규칙

- "재시도할까요?" 같은 확인 질문 없이 복구 후 자동 재시도한다.
- `claude plugin install`, `claude mcp list` 같은 CLI 명령으로 상태 확인을 시도하지 않는다.
- `settings.json`, IDE 캐시 파일을 읽어 상태를 추론하지 않는다.
