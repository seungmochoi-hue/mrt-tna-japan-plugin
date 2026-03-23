#!/usr/bin/env pwsh
# Claude Code에서 bq query를 실행할 때 guard를 통과시키는 Windows PowerShell 전용 wrapper.

if ($args.Count -lt 2) {
    Write-Error "Usage: run-bq-readonly.ps1 bq <query|show|ls|head|version> <args...>"
    exit 1
}

if ($args[0] -ne 'bq') {
    Write-Error "BLOCKED: run-bq-readonly.ps1는 bq 명령 전용입니다."
    exit 2
}

$subcommand = $args[1]
if ($subcommand -notin @('query', 'show', 'ls', 'head', 'version')) {
    Write-Error "BLOCKED: bq는 query / show / ls / head / version 명령만 허용됩니다."
    exit 2
}

$commandStr = $args -join ' '
$inputJson = @{ tool_name = 'Bash'; tool_input = @{ command = $commandStr; argv = @($args) } } | ConvertTo-Json -Compress

$guardScript = Join-Path $PSScriptRoot 'bq-query-guard.ps1'
$inputJson | & $guardScript
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$bqArgs = $args[1..($args.Count - 1)]
& bq @bqArgs
