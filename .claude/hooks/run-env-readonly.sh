#!/bin/bash

# Claude Code에서 환경 진단을 할 때 사용하는 read-only wrapper.

set -euo pipefail

SCRIPT_PATH="./.claude/scripts/check-env-readonly.sh"

if [ ! -x "$SCRIPT_PATH" ]; then
  echo "BLOCKED: $SCRIPT_PATH 가 없거나 실행 권한이 없습니다." >&2
  exit 2
fi

exec "$SCRIPT_PATH"
