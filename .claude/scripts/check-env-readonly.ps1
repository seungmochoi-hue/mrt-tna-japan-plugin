#!/usr/bin/env pwsh

# Read-only 환경 진단 스크립트.
# Windows PowerShell 기준으로 주요 CLI와 인증 상태를 점검한다.

$ErrorActionPreference = "Stop"

function Print-Header {
    param([string]$Title)
    Write-Output "=== $Title ==="
}

function Print-Output {
    param(
        [string]$Fallback,
        [scriptblock]$Command
    )

    try {
        & $Command
    } catch {
        Write-Output $Fallback
    }
}

function Get-AdcPath {
    if ($HOME) {
        $homeConfigPath = Join-Path $HOME ".config/gcloud/application_default_credentials.json"
        if (Test-Path $homeConfigPath) {
            return $homeConfigPath
        }
    }

    if ($env:APPDATA) {
        $appDataPath = Join-Path $env:APPDATA "gcloud\application_default_credentials.json"
        if (Test-Path $appDataPath) {
            return $appDataPath
        }
    }

    if ($env:USERPROFILE) {
        $userProfilePath = Join-Path $env:USERPROFILE "AppData\Roaming\gcloud\application_default_credentials.json"
        if (Test-Path $userProfilePath) {
            return $userProfilePath
        }
    }

    return $null
}

function Get-PythonCommand {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        return "python"
    }

    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        return "python3"
    }

    return $null
}

function Get-Python312Command {
    $candidates = @(
        @{ Command = "python3.12"; Args = @("--version") },
        @{ Command = "python3"; Args = @("--version") },
        @{ Command = "python"; Args = @("--version") },
        @{ Command = "py"; Args = @("-3.12", "--version") }
    )

    foreach ($candidate in $candidates) {
        if (-not (Get-Command $candidate.Command -ErrorAction SilentlyContinue)) {
            continue
        }

        try {
            $version = (& $candidate.Command @($candidate.Args) 2>&1 | Out-String).Trim()
            if ($version -match '^Python 3\.12\.') {
                return @{
                    Command = $candidate.Command
                    Version = $version
                    RunArgs = if ($candidate.Command -eq "py") { @("-3.12") } else { @() }
                }
            }
        } catch {
            continue
        }
    }

    return $null
}

Print-Header "Git"
Print-Output "MISSING" { git --version }
Write-Output ""

Print-Header "Git branch"
Print-Output "MISSING" { git rev-parse --abbrev-ref HEAD }
Write-Output ""

Print-Header "gcloud"
if (Get-Command gcloud -ErrorAction SilentlyContinue) {
    Print-Output "MISSING" { (gcloud --version 2>$null | Select-Object -First 1) }
} else {
    Write-Output "MISSING"
}
Write-Output ""

Print-Header "gcloud auth"
if (Get-Command gcloud -ErrorAction SilentlyContinue) {
    Print-Output "MISSING" { gcloud auth list }
} else {
    Write-Output "MISSING"
}
Write-Output ""

Print-Header "gcloud project"
if (Get-Command gcloud -ErrorAction SilentlyContinue) {
    Print-Output "MISSING" { gcloud config get-value project }
} else {
    Write-Output "MISSING"
}
Write-Output ""

Print-Header "bq"
Print-Output "MISSING" { bq version }
Write-Output ""

Print-Header "gh"
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Print-Output "MISSING" { (gh --version | Select-Object -First 1) }
} else {
    Write-Output "MISSING"
}
Write-Output ""

Print-Header "gh auth"
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Print-Output "MISSING" { gh auth status }
} else {
    Write-Output "MISSING"
}
Write-Output ""

$pythonCmd = Get-PythonCommand
$python312 = Get-Python312Command

Print-Header "Python 3.12"
if ($python312) {
    Write-Output $python312.Version
} else {
    Write-Output "MISSING - Python 3.12 설치 필요"
}
Write-Output ""

Print-Header "pandas"
if ($python312) {
    try {
        & $python312.Command @($python312.RunArgs) -c "import pandas; print('pandas', pandas.__version__)" 2>$null
    } catch {
        Write-Output "MISSING"
    }
} else {
    Write-Output "MISSING"
}
Write-Output ""

Print-Header "uv/uvx"
if ((Get-Command uv -ErrorAction SilentlyContinue) -and (Get-Command uvx -ErrorAction SilentlyContinue)) {
    Write-Output (& uv --version)
    Write-Output (& uvx --version)
} else {
    Write-Output "MISSING - uv 설치 필요"
}
Write-Output ""

Print-Header "Google Sheets MCP"
$adcPath = Get-AdcPath
if ($adcPath -and (Test-Path $adcPath)) {
    Write-Output "ADC token: OK"
    Write-Output "ADC path: $adcPath"
    Write-Output "runtime: uvx mcp-google-sheets"
} else {
    Write-Output "MISSING - gsheets-auth skill로 인증 필요"
}
Write-Output ""

Print-Header "Atlassian MCP"
Write-Output "Atlassian 인증 상태는 MCP 도구 직접 호출로 확인합니다."
Write-Output "인증 필요 시: Claude Code의 /mcp 에서 Atlassian Authenticate 후 브라우저 로그인을 진행합니다."
Write-Output ""

Print-Header "Slack MCP"
Write-Output "Slack 인증 상태는 MCP 도구 직접 호출로 확인합니다."
Write-Output "인증 필요 시: Claude Code의 /mcp 에서 Slack Authenticate 후 브라우저 로그인을 진행합니다."
Write-Output ""

Print-Header "Redash API Key"
$redashEnv = Join-Path $PSScriptRoot "..\credentials\redash.env"
if ((Test-Path $redashEnv) -and (Select-String -Path $redashEnv -Pattern 'REDASH_API_KEY' -Quiet)) {
    Write-Output "OK"
} else {
    Write-Output "MISSING - https://redash.myrealtrip.net/users/me 에서 API Key 복사 필요"
}
Write-Output ""

Print-Header "KST date"
try {
    $kst = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), "Korea Standard Time")
    Write-Output $kst.ToString("yyyy-MM-dd")
} catch {
    (Get-Date).ToString("yyyy-MM-dd")
}
