---
name: gsheets-auth
description: Google Sheets MCP 사용을 위한 OAuth 인증 설정. ADC(Application Default Credentials)에 Sheets/Drive 스코프를 추가한다. Use when Google Sheets MCP tools fail with authentication errors or when setting up Google Sheets access.
---

# Google Sheets Auth

> **모든 명령은 Claude가 즉시 자동 실행한다.** 미설치/미인증/에러 발견 시 묻지 않고 바로 복구한다.
> 사용자는 Claude가 띄운 브라우저 창에서 Google 로그인만 하면 된다. "설치할까요?", "해결 방법이 있어요" 같은 확인/선택지 제시 금지.
> 자동 설치 원칙: `.claude/rules/auto-install.md` 참조.

Google Sheets MCP는 `uvx mcp-google-sheets` 런타임과 `gcloud auth application-default login`으로 생성된 ADC 토큰을 함께 사용한다.
기존 `gcloud auth login`(bq CLI용)과는 별개의 인증이다.

---

## 실행 순서

### 1. gcloud 및 uv/uvx 설치 확인

```bash
which gcloud 2>&1 || echo "NOT_INSTALLED"
which uv >/dev/null 2>&1 && which uvx >/dev/null 2>&1 || echo "UV_NOT_INSTALLED"
```

미설치 시:

- `gcloud`가 없으면 `gcloud-auth` skill의 설치 절차를 따른다.
- `uv` 또는 `uvx`가 없으면 아래 명령으로 즉시 설치한다.

```bash
# macOS
brew install uv

# Windows (PowerShell)
winget.exe install --id=astral-sh.uv -e --accept-source-agreements --accept-package-agreements
```

### 2. ADC 토큰 존재 확인

```bash
# macOS / Linux / Git Bash
ls -la "$HOME/.config/gcloud/application_default_credentials.json" 2>&1 || echo "NOT_FOUND"
```

```powershell
# Windows PowerShell
Test-Path "$env:APPDATA\gcloud\application_default_credentials.json"
```

### 3. 인증 실행

토큰이 없거나, Google Sheets MCP에서 인증 에러가 발생한 경우 실행한다.

> Claude가 Google Sheets 인증 브라우저 창을 직접 띄운다. Google 계정 로그인과 권한 동의만 완료하면 된다.

```bash
gcloud auth application-default login --launch-browser \
  --scopes="openid,https://www.googleapis.com/auth/userinfo.email,https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/spreadsheets,https://www.googleapis.com/auth/drive"
```

- Claude가 브라우저를 열고, Google 로그인 후 권한 동의 화면이 나온다.
- 동의하면 토큰이 macOS/Linux에서는 `~/.config/gcloud/application_default_credentials.json`, Windows PowerShell에서는 `$env:APPDATA\gcloud\application_default_credentials.json`에 자동 저장된다.

### 4. 검증

```bash
# macOS / Linux / Git Bash
cat "$HOME/.config/gcloud/application_default_credentials.json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('Type:', data.get('type', 'unknown'))
print('Client ID:', data.get('client_id', 'N/A')[:20] + '...')
print('Token present:', bool(data.get('refresh_token')))
"
```

```powershell
# Windows PowerShell
$adcPath = Join-Path $env:APPDATA "gcloud\application_default_credentials.json"
Get-Content $adcPath | python -c "
import json, sys
data = json.load(sys.stdin)
print('Type:', data.get('type', 'unknown'))
print('Client ID:', data.get('client_id', 'N/A')[:20] + '...')
print('Token present:', bool(data.get('refresh_token')))
"
```

---

## 인증 구조

```
gcloud auth login                          ← bq CLI용 (기존)
gcloud auth application-default login      ← Google Sheets MCP용 (신규)
uvx mcp-google-sheets                      ← Google Sheets MCP 서버 런타임
    │
    └── macOS/Linux: ~/.config/gcloud/application_default_credentials.json
        Windows: %APPDATA%\gcloud\application_default_credentials.json
            │
            └── mcp-google-sheets가 ADC fallback으로 자동 참조
```

- 두 인증은 독립적이다. ADC 인증을 해도 기존 bq CLI 인증에 영향 없음.
- ADC 토큰은 refresh_token을 포함하므로 만료 시 자동 갱신된다.

## 필요 스코프

| 스코프 | 용도 |
|--------|------|
| `openid` | OpenID Connect 기본 |
| `userinfo.email` | 사용자 이메일 식별 |
| `cloud-platform` | GCP 리소스 접근 (BQ 등 호환) |
| `spreadsheets` | Google Sheets 읽기/쓰기 |
| `drive` | Google Drive 파일 접근 (시트 목록 조회) |

## 자동 복구 워크플로우 (필수)

Google Sheets MCP 도구 호출 시 에러가 발생하면, **사용자에게 선택지를 주지 않고 자동으로 복구한 뒤 원래 작업을 재시도**한다.

```
Google Sheets MCP 호출
    │
    ├─ 성공 → 결과 반환
    │
    └─ 에러 발생 → 에러 유형 판별
            │
            ├─ API 미활성화 → gcloud services enable 자동 실행
            ├─ uvx 미설치 → uv 설치 후 재시도
            ├─ 인증 실패 → Step 3 자동 실행 (브라우저 인증)
            ├─ 스코프 부족 → Step 3 재실행 (스코프 갱신)
            ├─ ADC 파일 손상 → 삭제 후 Step 3 재실행
            └─ gcloud 미설치 → gcloud-auth skill 자동 실행
            │
            ▼
       복구 완료 → 원래 MCP 호출 자동 재시도
            │
            ▼
       사용자에게 결과 전달 (에러가 있었다는 사실은 간단히 한 줄만 언급)
```

## 빠른 참조: 에러별 자동 조치

| 증상 | 자동 조치 | 사용자 개입 |
|------|---------|-----------|
| `Google Drive API has not been used in project` / `drive.googleapis.com` 관련 403 | `gcloud services enable drive.googleapis.com --project={에러 메시지에서 추출한 project_id}` 실행 후 재시도 | 없음 |
| `Google Sheets API has not been used in project` / `sheets.googleapis.com` 관련 403 | `gcloud services enable sheets.googleapis.com --project={project_id}` 실행 후 재시도 | 없음 |
| `command not found: uvx` / `uvx: command not found` | `brew install uv` 또는 `winget.exe install --id=astral-sh.uv -e` 실행 후 재시도 | 없음 |
| `All authentication methods failed` | Step 3 인증 실행 후 재시도 | 브라우저 로그인만 |
| `Request had insufficient authentication scopes` | Step 3 재실행 (스코프 갱신) 후 재시도 | 브라우저 로그인만 |
| `file_cache is only supported with oauth2client<4.0.0` | 무시. 동작에 영향 없음 | 없음 |
| `command not found: gcloud` | `gcloud-auth` skill 자동 실행 후 Step 3 진행 | 브라우저 로그인만 |
| ADC 파일 있지만 인증 실패 | macOS/Linux는 `rm ~/.config/gcloud/application_default_credentials.json`, Windows는 `Remove-Item "$env:APPDATA\\gcloud\\application_default_credentials.json"` 후 Step 3 재실행 | 브라우저 로그인만 |
| `HttpError 403` (기타) | 위 항목에 해당하지 않으면 ADC 삭제 후 Step 3 재실행 | 브라우저 로그인만 |

### API 활성화 명령

에러 메시지에서 project ID를 추출하여 자동 실행한다. 추출 실패 시 `gcloud config get-value project`로 현재 프로젝트를 fallback으로 사용한다.

```bash
# Drive API 활성화 (project ID는 에러 메시지에서 파싱)
gcloud services enable drive.googleapis.com --project={project_id}

# Sheets API 활성화
gcloud services enable sheets.googleapis.com --project={project_id}
```

- 활성화 후 전파까지 최대 1–2분 소요될 수 있다. **재시도 전략**: 첫 재시도는 30초 대기, 실패 시 60초 대기 후 2차 재시도. 2차까지 실패하면 "API 활성화가 아직 전파 중이에요. 1–2분 후 다시 시도해주세요!"로 안내한다. 최대 재시도 횟수: 2회.
- 두 API를 동시에 활성화해도 된다: `gcloud services enable drive.googleapis.com sheets.googleapis.com --project={project_id}`

### 사용자 안내 메시지 (복구 중)

복구 과정에서 사용자에게 보이는 메시지는 간결하게만:

| 상황 | 메시지 |
|------|--------|
| 인증 시작 | "Google Sheets 인증을 설정하고 있어요. 브라우저에서 로그인해 주세요!" |
| API 활성화 | "연결을 설정하고 있어요. 잠시만 기다려주세요!" |
| 복구 완료 | "설정 완료! 이어서 진행할게요." |
| 최종 실패 | "Google Sheets 연결에 문제가 있어요. 잠시 후 다시 시도해주세요!" |
