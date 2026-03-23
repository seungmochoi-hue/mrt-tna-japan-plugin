---
name: gcloud-auth
description: BigQuery bq CLI 사용을 위한 gcloud 인증 설정. 인증 상태 확인, 로그인, 프로젝트/리전 설정. Use when setting up or troubleshooting gcloud authentication for BigQuery access.
---

# gcloud Auth for BigQuery

> **모든 명령은 Claude가 즉시 자동 실행한다.** 미설치/미인증 발견 시 묻지 않고 바로 설치/인증한다.
> 사용자는 Claude가 띄운 브라우저 창에서 Google 로그인만 하면 된다. "설치할까요?" 같은 확인 질문 금지.
> 자동 설치 원칙: `.claude/rules/auto-install.md` 참조.

## 실행 순서

### 1. 설치 확인

```bash
which gcloud 2>&1 && gcloud version 2>&1 || echo "NOT_INSTALLED"
which bq 2>&1 || echo "BQ_NOT_FOUND"
```

### 2. 미설치 시 자동 설치

| OS | 명령 |
|----|------|
| macOS (brew 있음) | `brew install --cask google-cloud-sdk` |
| macOS (brew 없음) | Homebrew 먼저 설치 후 위 명령 |
| Windows (PowerShell) | `winget.exe install Google.CloudSDK --accept-source-agreements --accept-package-agreements` |

macOS Homebrew 미설치 시:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
[[ "$(uname -m)" == "arm64" ]] && \
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile && \
  eval "$(/opt/homebrew/bin/brew shellenv)"
```

### 3. 인증 상태 확인

```bash
gcloud auth list 2>&1
gcloud config get-value project 2>&1
```

### 4. 인증 필요 시

> Claude가 Google 계정 로그인 창을 직접 띄운다. 브라우저에서 로그인만 완료하면 된다.

```bash
gcloud auth login --launch-browser
```

### 5. 프로젝트/기본값 설정

```bash
gcloud config set project mrtdata
gcloud config set compute/region asia-northeast3

cat > "$HOME/.bigqueryrc" << 'EOF'
[query]
use_legacy_sql=false
location=asia-northeast3
project_id=mrtdata
EOF
```

### 6. 검증

```bash
bq query --use_legacy_sql=false --location=asia-northeast3 --max_rows=1 'SELECT 1 AS test'
```

---

## 인증 방법

| 명령 | 용도 |
|------|------|
| `gcloud auth login` | bq CLI -- 이것만으로 충분 |
| `gcloud auth application-default login` | ADC 기반 라이브러리 -- bq에는 불필요 |

## 트러블슈팅

| 증상 | 자동 조치 |
|------|---------|
| `Not logged in` | `gcloud auth login --launch-browser` 실행 |
| `Access Denied: Project mrtdata` | 관리자에게 IAM 권한 요청이 필요하다고 간단히 안내 (선택지 제시 금지) |
| `Location ... is not supported` | `gcloud config set compute/region asia-northeast3` |
| `command not found: gcloud` | 설치 스크립트 실행 |
