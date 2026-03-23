---
name: setup
description: Claude Code 에이전트가 정상 작동하기 위한 도구 설치 및 인증을 자동 수행한다. 세션 시작 시 greeting에 의해 매번 자동 실행되며, 미설치 항목을 탐지하고 설치/인증을 진행. Use when session starts (auto-triggered by greeting) or when user asks to set up, initialize, or configure the agent environment.
---

# Setup

> **모든 설치/설정은 Claude가 즉시 자동 실행한다.** "설치할까요?" 같은 확인 금지.
> CLI 인증(`gcloud`, `gh`)은 Claude가 브라우저 흐름을 직접 시작한다. MCP OAuth(Atlassian, Slack)는 `/mcp` -> `Authenticate`로 안내한다.
> **자동 설치 원칙**: `.claude/rules/auto-install.md` 참조.

---

## Fast-path

1. 진단 스크립트 실행:

```bash
./.claude/hooks/run-env-readonly.sh          # macOS / Linux
```
```powershell
& '.claude/hooks/run-env-readonly.ps1'       # Windows
```

2. `MISSING` 유무 확인:
   - **없음** -> "환경 점검 완료!" 출력 후 **즉시 종료**
   - **있음** -> 아래 체크리스트에서 해당 항목만 자동 설치/인증

3. **재시도**: 실패 시 1회 재시도. 2회 연속 실패 -> 실패 항목만 표시하고 나머지 기능으로 진행.

---

## UX 원칙

### 진행 상황 안내

| 시점 | 메시지 |
|------|--------|
| 진단 완료 | "**N개** 항목을 설정해야 해요. 자동으로 진행할게요!" |
| 도구 설치 | "도구 설치 중이에요... (1/N)" |
| 브라우저 인증 | "브라우저가 열릴 거예요! 로그인만 해주시면 돼요 (2/N)" |
| MCP 인증 | "마지막으로 Slack/Atlassian 연결이 필요해요 (N/N)" |
| 완료 | "모든 준비가 끝났어요! 이제 데이터 분석을 시작할 수 있어요." |

- 브라우저 인증이 여러 건이면: "설정 과정에서 브라우저 창이 **N번** 열릴 거예요."
- Homebrew 신규 설치 시: "Mac 비밀번호를 입력하라는 창이 뜰 수 있어요. Mac 로그인할 때 쓰는 비밀번호를 입력해 주세요!"

### 부분 실패 시 기능 안내

| 실패 항목 | 사용 가능 | 사용 불가 |
|----------|----------|----------|
| gcloud/bq | - | 데이터 조회, 분석 전체 |
| gh | 데이터 조회, 분석 | dbt 모델 파일 조회 (로컬은 가능) |
| Google Sheets MCP | 데이터 조회, 분석, Slack 공유 | Google Sheets 내보내기 |
| Atlassian MCP | 데이터 조회, 분석, Sheets 내보내기 | Confluence 문서 조회/검색, Jira 검색 |
| Slack MCP | 데이터 조회, 분석, Sheets 내보내기 | Slack 공유, Slack 검색 |

### 설치 실행 규칙

- **PATH 갱신**: 설치 직후 Claude가 직접 실행 (사용자에게 안내하지 않음)

```bash
eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null; hash -r 2>/dev/null  # macOS
```
```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")  # Windows
```

- **병렬 설치**: jq, gh, python@3.12, uv는 의존성이 없으므로 한 메시지에서 여러 Bash 호출로 동시 설치. gcloud SDK -> gcloud auth -> BQ 설정, python -> pandas는 순차.
- **Windows**: `py -3.12` launcher 우선 사용. `chmod` 생략. hook 런타임용 Git Bash 필수 (`winget install Git.Git`).

---

## 체크리스트

| # | 항목 | 점검 | macOS 설치 | Windows 설치 | 인증 subskill |
|---|------|------|-----------|-------------|--------------|
| 0 | OS 감지 | `uname -s` / `$env:OS` | - | - | - |
| 1 | 패키지 매니저 | `which brew` / `Get-Command winget.exe` | Homebrew 자동 설치 | 기본 내장 | - |
| 1.5 | Git (Win only) | `Get-Command git` | - | `winget install Git.Git` | - |
| 2 | jq | `which jq` | `brew install jq` | `winget install jqlang.jq` | - |
| 3 | Google Cloud SDK | `which gcloud` | `brew install --cask google-cloud-sdk` | `winget install Google.CloudSDK` | - |
| 4 | gcloud 인증 | `gcloud auth list` | (설치 후) | (설치 후) | `gcloud-auth` |
| 5 | BQ 기본값 | `gcloud config get-value project` | (설치 후) | (설치 후) | `gcloud-auth` |
| 6 | GitHub CLI | `which gh` | `brew install gh` | `winget install GitHub.cli` | - |
| 7 | GitHub 인증 | `gh auth status` | (설치 후) | (설치 후) | `gh-auth` |
| 8 | Python 3.12 + pandas | `python3.12 --version` / `py -3.12 --version` | `brew install python@3.12` -> `pip install pandas` | `winget install Python.Python.3.12` -> `pip install pandas` | - |
| 9 | uv/uvx | `which uvx` | `brew install uv` | `winget install --id=astral-sh.uv -e` | - |
| 10 | Atlassian MCP | MCP 도구 직접 호출 | `/mcp` -> Authenticate | 동일 | (아래 MCP 안내) |
| 11 | Google Sheets MCP | ADC 토큰 존재 확인 | (아래 참조) | 동일 | `gsheets-auth` |
| 12 | Slack MCP | MCP 도구 직접 호출 | `/mcp` -> Authenticate | 동일 | (아래 MCP 안내) |
| 13 | Redash API Key | `test -f .claude/credentials/redash.env` | 상태만 표시 (on-demand) | 동일 | `redash-query` |

이미 설치/인증된 항목은 건너뛴다.

---

## 항목별 설치/인증 디스패치

### Step 0–2: OS 감지 + 패키지 매니저 + jq

OS를 `uname -s`(macOS) / `$env:OS`(Windows)로 감지 후, Homebrew 미설치 시 자동 설치. jq 미설치 시 `brew install jq` / `winget install jqlang.jq`.

### Step 3–5: Google Cloud SDK + 인증 + BQ 기본값

설치 확인 후 미설치 시 brew/winget으로 설치. **인증 및 기본값 설정은 `gcloud-auth` skill의 절차를 따른다.** (`gcloud auth login --launch-browser`, 프로젝트/리전 설정 포함)

### Step 6–7: GitHub CLI + 인증

설치 확인 후 미설치 시 brew/winget으로 설치. **인증은 `gh-auth` skill의 절차를 따른다.** (`gh auth login --web`, device code 브라우저 열기, 코드 안내 포함)

### Step 8: Python 3.12 + pandas

`python3.12` / `py -3.12`가 없으면 brew/winget으로 설치. pandas 미설치 시 `pip install pandas`. `python3`이 다른 버전을 가리켜도 3.12 경로가 없으면 미설치로 본다.

### Step 9: uv/uvx

`uv`/`uvx`가 없으면 `brew install uv` / `winget install --id=astral-sh.uv -e`.

### Step 10, 12: Atlassian / Slack MCP

MCP 도구를 직접 호출하여 상태 확인. 실패 시 아래 안내를 출력한다:

> **{서비스명}** 연결이 필요해요!
>
> 1. 이 채팅창에 `/mcp` 를 입력해 주세요
> 2. 목록에서 **{서비스명}** 항목을 찾아주세요
> 3. **Authenticate** 버튼을 눌러주세요
> 4. 브라우저가 열리면 회사 계정으로 **로그인 -> 승인**
> 5. 완료되면 다시 여기로 돌아와 주세요!
>
> 브라우저가 자동으로 안 열리면, 터미널에 표시된 URL을 복사해서 브라우저에 붙여넣어 주세요.
> 로그인 후 "연결할 수 없음" 에러가 뜨면, 브라우저 주소창의 **전체 URL을 복사**해서 터미널에 붙여넣어 주세요.

인증 완료 후 같은 MCP 도구를 **자동 재확인**하고 나머지 세팅을 이어간다.

**금지**: `claude plugin install/list`, `claude mcp list`, 재시작 안내, 에러 원문 노출, `settings.json`/캐시 파일 추론.

### Step 11: Google Sheets MCP

ADC 토큰 존재 확인. **미인증 시 `gsheets-auth` skill의 절차를 따른다.** (`gcloud auth application-default login --launch-browser` + Sheets/Drive 스코프 포함)

### Step 13: Redash API Key

`.claude/credentials/redash.env` 존재 여부만 확인하여 출력 표에 반영한다. 초기 세팅에서 적극 설정하지 않는다 (사용자가 Redash URL을 처음 제공할 때 `redash-query` skill이 on-demand로 처리).

---

## 최종 검증

```bash
./.claude/hooks/run-env-readonly.sh
./.claude/hooks/run-bq-readonly.sh bq query --use_legacy_sql=false --location=asia-northeast3 --max_rows=1 'SELECT 1 AS test' 2>&1
```

---

## 출력 형식

초기 세팅 점검 요약 표에는 아래 항목을 **반드시 모두 포함**한다:

| 항목 | 상태 | 상세 |
|------|------|------|
| bq CLI | 정상 / 미설치 | 버전 |
| gcloud 인증 | 정상 / 필요 | 계정 |
| gcloud 프로젝트 | 정상 / 미설정 | 프로젝트 ID |
| GitHub CLI | 정상 / 미설치 | 계정 또는 버전 |
| Git 브랜치 | 확인 | 현재 브랜치 |
| Python 3.12 + pandas | 정상 / 미설치 | 버전 |
| uv/uvx | 정상 / 미설치 | 버전 |
| Google Sheets MCP | 정상 / 인증 필요 | ADC 토큰 존재 여부 |
| Atlassian 플러그인 | 정상 / 인증 필요 | MCP 도구 호출 결과 기준 |
| Confluence 연동 | 사용 가능 / 인증 필요 | MCP 도구 호출 결과 기준 |
| Slack MCP | 정상 / 인증 필요 | MCP 도구 호출 결과 기준 |
| Redash API Key | 설정됨 / 미설정 | `.claude/credentials/redash.env` 존재 여부 |
| 오늘 날짜 (KST) | 확인 | YYYY-MM-DD |

`Atlassian 플러그인`, `Confluence 연동`, `Slack MCP` 행이 모두 포함되지 않으면 "모든 초기 세팅이 정상적으로 완료" 문구를 쓰지 않는다. Atlassian/Slack 상태는 오직 MCP 도구 호출 결과에 기반해 작성한다.

**금지 표현** (Atlassian/Slack 공통):
- `settings.json에 true`, `mcp-needs-auth-cache.json에 기록`
- `MCP 도구가 이번 세션에 로드되지 않고 있어요` 등 추론형 문구
- `OAuth 인증 완료 여부 직접 확인 불가`, `연동은 확인 필요`
- `Claude Code를 재시작해주세요`, `claude plugin install` 관련 안내
