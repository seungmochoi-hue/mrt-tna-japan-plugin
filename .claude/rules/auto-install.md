# 자동 설치/복구 원칙 (최우선 규칙)

이 규칙은 모든 skill, agent, hook에 우선 적용된다.

## 핵심 원칙

**설치·인증·설정이 안 되어 있으면 사용자에게 묻지 않고 즉시 자동으로 해결한다.**

- 사용자는 비개발자다. 기술적 선택지를 제시하지 않는다.
- Claude가 모든 설치/인증/설정의 주도권을 갖는다.
- 사용자 개입이 물리적으로 불가피한 경우(브라우저 로그인, 관리자 권한 요청)만 안내한다.
- Claude가 직접 실행할 수 있는 CLI/browser OAuth(`gcloud`, `gh`)는 Claude가 직접 시작한다.
- Claude Code가 관리하는 MCP OAuth는 공식 `/mcp` 흐름으로 안내한다. 사용자에게는 어떤 항목에서 `Authenticate`를 눌러야 하는지, 브라우저가 안 뜰 때의 fallback URL 처리, callback URL 붙여넣기까지 구체적으로 안내한다.
- 단, GitHub device flow에서 Claude가 `https://github.com/login/device`를 직접 열고 코드를 클립보드에 넣은 뒤 마지막 붙여넣기/승인만 요청하는 것은 허용한다.

## 금지 행동

| 금지 | 대신 해야 할 것 |
|------|----------------|
| "설치할까요?" / "진행할까요?" | 바로 설치한다 |
| "아래 두 가지 방법이 있어요" | 최선의 방법 하나를 바로 실행한다 |
| "에러가 발생했어요. 해결 방법은..." | 자동으로 고치고 재시도한다. 성공 후 한 줄만 언급한다 |
| "이 명령을 실행해보세요" | Claude가 직접 실행한다 |
| "API를 활성화해주세요" | `gcloud services enable`로 직접 활성화한다 |
| 에러 메시지 원문을 사용자에게 보여주기 | 기술적 세부사항은 숨기고 "설정 중이에요" 정도만 안내 |
| "CSV로 먼저 저장할까요?" (fallback 제안) | 원래 요청을 복구하여 완수한다 |

## 자동 복구 흐름

```
도구/명령 실행 실패
    │
    ▼
에러 유형 자동 판별
    │
    ├─ 미설치 → 자동 설치 → 재시도
    ├─ 인증 실패 → 자동 인증 프로세스 → 재시도
    ├─ API 미활성화 → gcloud services enable → 재시도
    ├─ 스코프 부족 → 재인증 → 재시도
    ├─ 토큰 만료/손상 → 삭제 후 재인증 → 재시도
    └─ 기타 → 최선의 자동 조치 시도 → 실패 시만 사용자에게 상황 설명
    │
    ▼
복구 성공 → 원래 작업 이어서 완료
```

## 사용자 안내 메시지 템플릿

복구 중에는 간결하게만 안내한다:

| 상황 | 메시지 |
|------|--------|
| 도구 설치 중 | "필요한 도구를 설치하고 있어요. 잠시만 기다려주세요!" |
| 인증 진행 중 | "인증을 설정하고 있어요. 브라우저에서 로그인해 주세요!" |
| API 활성화 중 | "연결을 설정하고 있어요. 잠시만 기다려주세요!" |
| 복구 완료 후 | "설정 완료! 이어서 진행할게요." |
| MCP OAuth 진행 중 | "연결을 설정하고 있어요. Claude Code에서 `/mcp`를 입력하고 해당 항목의 `Authenticate`를 선택해 주세요! 브라우저가 안 뜨면 터미널에 표시된 URL을 직접 복사해서 브라우저에 붙여넣어 주세요." |
| GitHub OAuth 진행 중 | "GitHub 인증을 진행하고 있어요. 인증 창을 직접 열어두었어요. 창이 안 보이면 https://github.com/login/device 로 들어가 주세요!" |
| GitHub code 페이지 복구 중 | "GitHub 인증 페이지를 다시 열어두었어요. 창이 안 보이거나 code 칸이 비어 있으면 https://github.com/login/device 로 들어가 클립보드 값을 붙여넣고 승인만 해 주세요!" |

## 브라우저 OAuth 실행 규칙

- `gcloud auth login` 계열은 반드시 브라우저 launch 모드로 실행한다.
  - 예: `gcloud auth login --launch-browser`
  - 예: `gcloud auth application-default login --launch-browser ...`
- `gh` 인증은 반드시 웹 브라우저 모드로 실행한다.
  - 예: `gh auth login --hostname github.com --git-protocol https --web --clipboard`
  - 브라우저가 일반 GitHub 페이지를 열거나 code 입력 칸이 보이지 않으면 Claude가 `https://github.com/login/device`를 직접 다시 연다.
  - one-time code는 사용자가 터미널에서 찾게 하지 말고, `--clipboard`와 Claude의 출력 파악으로 처리한다.
- Atlassian/Slack 같은 MCP OAuth 인증 에러가 나면 Claude Code의 `/mcp`에서 해당 항목의 `Authenticate`를 선택하도록 안내한다.
  - 브라우저가 자동으로 열리지 않으면 Claude Code가 제공한 URL을 직접 열도록 안내한다.
  - 인증 후 redirect가 connection error로 실패하면 브라우저 주소창의 전체 callback URL을 Claude Code의 URL prompt에 붙여넣도록 안내한다.
- OAuth 시작 후에는 같은 도구 상태를 다시 확인하고, 성공할 때까지 원래 작업을 자동 재시도한다.

## 적용 범위

이 원칙은 아래 모든 상황에 적용된다:

- 세션 시작 환경 점검 (`check-env-readonly.sh` / `check-env-readonly.ps1`) 후 MISSING 항목 발견
- Google Sheets MCP 에러 (API 미활성화, 인증 실패 등)
- BigQuery `bq` 명령 실패
- GitHub `gh` 명령 실패
- gcloud 미설치/미인증
- Python 3.12 미설치
- uv/uvx 미설치
- Python/pandas 미설치
- jq 미설치
- Homebrew 미설치
- 기타 모든 도구 의존성 누락

## 유일한 예외

사용자에게 직접 행동을 요청해야 하는 경우 (Claude가 대신할 수 없는 것):

1. **브라우저 OAuth 로그인** — "브라우저에서 로그인해 주세요!" (`gcloud`, `gh`, MCP OAuth 인증 시)
2. **Claude Code `/mcp` 메뉴 상호작용** — 사용자가 해당 서버의 `Authenticate`를 선택해야 하는 경우
3. **IAM 권한 부족** — 관리자에게 권한 요청이 필요한 경우 (사용자에게 상황 설명)
