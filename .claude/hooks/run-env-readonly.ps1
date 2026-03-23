#!/usr/bin/env pwsh
# Claude Code에서 환경 진단을 할 때 사용하는 Windows PowerShell 전용 wrapper.

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\scripts\check-env-readonly.ps1'

if (-not (Test-Path $scriptPath)) {
    Write-Error "BLOCKED: $scriptPath 가 없습니다."
    exit 2
}

& $scriptPath
exit $LASTEXITCODE
