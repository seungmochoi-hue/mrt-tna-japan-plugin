#!/bin/bash

# Read-only 환경 진단 스크립트.
# 훅 친화적으로 한 번의 Bash 호출로 주요 CLI와 인증 상태를 점검한다.

set -u
set -o pipefail

resolve_adc_path() {
  if [ -n "${APPDATA:-}" ] && [ -f "$APPDATA/gcloud/application_default_credentials.json" ]; then
    printf '%s' "$APPDATA/gcloud/application_default_credentials.json"
    return
  fi

  if [ -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
    printf '%s' "$HOME/.config/gcloud/application_default_credentials.json"
    return
  fi

  if [ -n "${USERPROFILE:-}" ] && [ -f "$USERPROFILE/AppData/Roaming/gcloud/application_default_credentials.json" ]; then
    printf '%s' "$USERPROFILE/AppData/Roaming/gcloud/application_default_credentials.json"
    return
  fi

  return 1
}

print_header() {
  echo "=== $1 ==="
}

print_command_output() {
  local fallback="$1"
  shift

  if "$@" 2>/dev/null; then
    return 0
  fi

  echo "$fallback"
}

resolve_python_312_cmd() {
  local version

  if command -v python3.12 >/dev/null 2>&1; then
    version="$(python3.12 --version 2>&1)"
    if printf '%s\n' "$version" | grep -Eq '^Python 3\.12\.'; then
      printf '%s\n' "python3.12"
      return 0
    fi
  fi

  if command -v python3 >/dev/null 2>&1; then
    version="$(python3 --version 2>&1)"
    if printf '%s\n' "$version" | grep -Eq '^Python 3\.12\.'; then
      printf '%s\n' "python3"
      return 0
    fi
  fi

  if command -v python >/dev/null 2>&1; then
    version="$(python --version 2>&1)"
    if printf '%s\n' "$version" | grep -Eq '^Python 3\.12\.'; then
      printf '%s\n' "python"
      return 0
    fi
  fi

  return 1
}

print_header "Git"
print_command_output "MISSING" git --version
echo ""

print_header "Git branch"
git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "MISSING"
echo ""

print_header "gcloud"
if command -v gcloud >/dev/null 2>&1; then
  gcloud --version 2>/dev/null | head -1
else
  echo "MISSING"
fi
echo ""

print_header "gcloud auth"
if command -v gcloud >/dev/null 2>&1; then
  gcloud auth list 2>&1
else
  echo "MISSING"
fi
echo ""

print_header "gcloud project"
if command -v gcloud >/dev/null 2>&1; then
  gcloud config get-value project 2>&1
else
  echo "MISSING"
fi
echo ""

print_header "bq"
print_command_output "MISSING" bq version
echo ""

print_header "gh"
if command -v gh >/dev/null 2>&1; then
  gh --version 2>/dev/null | head -1
else
  echo "MISSING"
fi
echo ""

print_header "gh auth"
if command -v gh >/dev/null 2>&1; then
  gh auth status 2>&1
else
  echo "MISSING"
fi
echo ""

print_header "Python 3.12"
if PYTHON_312_CMD="$(resolve_python_312_cmd)"; then
  "$PYTHON_312_CMD" --version 2>&1
else
  echo "MISSING - Python 3.12 설치 필요"
fi
echo ""

print_header "pandas"
if PYTHON_312_CMD="$(resolve_python_312_cmd)"; then
  "$PYTHON_312_CMD" -c "import pandas; print('pandas', pandas.__version__)" 2>/dev/null || echo "MISSING"
else
  echo "MISSING"
fi
echo ""

print_header "uv/uvx"
if command -v uv >/dev/null 2>&1 && command -v uvx >/dev/null 2>&1; then
  uv --version 2>/dev/null | head -1
  uvx --version 2>/dev/null | head -1
else
  echo "MISSING - uv 설치 필요"
fi
echo ""

print_header "Google Sheets MCP"
if ADC_PATH=$(resolve_adc_path); then
  echo "ADC token: OK"
  echo "ADC path: $ADC_PATH"
  echo "runtime: uvx mcp-google-sheets"
else
  echo "MISSING - gsheets-auth skill로 인증 필요"
fi
echo ""

print_header "Atlassian MCP"
echo "Atlassian 인증 상태는 MCP 도구 직접 호출로 확인합니다."
echo "인증 필요 시: Claude Code의 /mcp 에서 Atlassian Authenticate 후 브라우저 로그인을 진행합니다."
echo ""

print_header "Slack MCP"
echo "Slack 인증 상태는 MCP 도구 직접 호출로 확인합니다."
echo "인증 필요 시: Claude Code의 /mcp 에서 Slack Authenticate 후 브라우저 로그인을 진행합니다."
echo ""

print_header "Redash API Key"
REDASH_ENV=".claude/credentials/redash.env"
if [ -f "$REDASH_ENV" ] && grep -q 'REDASH_API_KEY' "$REDASH_ENV" 2>/dev/null; then
  echo "OK"
else
  echo "MISSING - https://redash.myrealtrip.net/users/me 에서 API Key 복사 필요"
fi
echo ""

print_header "KST date"
TZ=Asia/Seoul date +%Y-%m-%d
