#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

try {
    [void][Console]::In.ReadToEnd()
} catch {
}

$message = '이 레포의 Cursor Agent 지원은 종료되었습니다. 이 레포를 agent로 사용하려면 Claude Code를 이용해주세요.'

@{
    permission = 'deny'
    user_message = $message
    agent_message = $message
} | ConvertTo-Json -Compress
