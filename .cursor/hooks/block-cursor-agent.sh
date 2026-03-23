#!/bin/bash

set -euo pipefail

# Cursor beforeShellExecution hook.
# This repository no longer supports Cursor Agent execution.

cat >/dev/null || true

MESSAGE="이 레포의 Cursor Agent 지원은 종료되었습니다. 이 레포를 agent로 사용하려면 Claude Code를 이용해주세요."

printf '{"permission":"deny","user_message":"%s","agent_message":"%s"}\n' "$MESSAGE" "$MESSAGE"
