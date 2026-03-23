#!/usr/bin/env pwsh
# bq 명령은 read-only 조회 패턴만 허용한다.
# exit 0 = 허용, exit 2 = 차단

param([Parameter(ValueFromPipeline = $true, Position = 0)][string]$InputJson)

process {
    if (-not $InputJson) { $InputJson = $_ }
}

end {
    try { $data = $InputJson | ConvertFrom-Json } catch { exit 0 }
    if ($data.tool_name -ne 'Bash') { exit 0 }

    $cmd = $data.tool_input.command
    if ($cmd -notmatch '^\s*bq\s') { exit 0 }

    $argv = @()
    if ($null -ne $data.tool_input.argv) { $argv = @($data.tool_input.argv) }

    $guardTarget = $cmd
    $queryTarget = $cmd
    if ($argv.Count -ge 3 -and $argv[0] -eq 'bq' -and $argv[1] -eq 'query') {
        $lastArg = [string]$argv[$argv.Count - 1]
        if ($lastArg -match '\s' -or $lastArg.Contains('`') -or $lastArg -match '^(?i)\s*(SELECT|WITH|DECLARE|EXPLAIN|#STANDARDSQL)\b') {
            $guardTarget = ($argv[0..($argv.Count - 2)] -join ' ')
            $queryTarget = $lastArg
        }
    }

    $stripped = $guardTarget -replace "'[^']*'", 'STR' -replace '"[^"]*"', 'STR'

    if ($stripped -match '[;`]|&&|\|\||\$\(') {
        Write-Error "BLOCKED: 명령 체이닝(; && || 백틱 `$())은 허용되지 않습니다."
        exit 2
    }
    if ($stripped -match '(?<!>)&(?![&>\d])') {
        Write-Error "BLOCKED: 명령 체이닝(; && || 백틱 `$())은 허용되지 않습니다."
        exit 2
    }

    if ($cmd -match '^\s*bq\s+(show|ls|head|version)(\s|$)') { exit 0 }
    if ($cmd -notmatch '^\s*bq\s+query(\s|$)') {
        Write-Error "BLOCKED: bq는 query / show / ls / head / version 명령만 허용됩니다."
        exit 2
    }

    if ($cmd -notmatch '--location(?:=|\s+)asia-northeast3(?:\s|$)') {
        Write-Error "BLOCKED: --location=asia-northeast3 플래그가 필요합니다."
        exit 2
    }

    $upper = $cmd.ToUpper()

    if ($upper -match '(^|[^A-Z0-9_])DW_BIZ_LOG([^A-Z0-9_]|$)') {
        $pythonCmd = $null
        if (Get-Command python3 -ErrorAction SilentlyContinue) {
            $pythonCmd = 'python3'
        } elseif (Get-Command python -ErrorAction SilentlyContinue) {
            $pythonCmd = 'python'
        }

        if (-not $pythonCmd) {
            Write-Error "BLOCKED: DW_BIZ_LOG 기간 제한 검증에 python 또는 python3가 필요합니다."
            exit 2
        }

        $pyScript = @'
import os, re, sys
from datetime import date, timedelta

cmd = os.environ["COMMAND_ENV"]
sql = os.environ.get("QUERY_ENV") or cmd
sql = re.sub(r'(?m)--[^\n]*$', '', sql)
sql = re.sub(r'/\*.*?\*/', '', sql, flags=re.DOTALL)
normalized = " ".join(sql.upper().split())

if not re.search(r"(^|[^A-Z0-9_])DW_BIZ_LOG([^A-Z0-9_]|$)", normalized):
    sys.exit(0)

current_date_expr = r"CURRENT_DATE(?:\([^)]*\))?"
date_literal = r"(?:DATE\s*)?['\"](\d{4}-\d{2}-\d{2})['\"]"

def fail(message):
    print("BLOCKED: DW_BIZ_LOG 조회는 basis_dt 기준 최대 7일 범위만 허용됩니다. " + message)
    sys.exit(1)

def ensure_max_7_days(span_days):
    if span_days < 1:
        fail("시작일과 종료일이 올바른지 확인하세요.")
    if span_days > 7:
        fail("basis_dt 범위를 7일 이하로 줄여주세요.")
    sys.exit(0)

def explicit_span(ld, lo, ud, uo):
    l = date.fromisoformat(ld)
    u = date.fromisoformat(ud)
    if lo == ">":
        l += timedelta(days=1)
    if uo == "<":
        u -= timedelta(days=1)
    return (u - l).days + 1

def relative_span(li, lo, ui, uo):
    return (li - (1 if lo == ">" else 0)) - (ui + (1 if uo == "<" else 0)) + 1

if "BASIS_DT" not in normalized:
    fail("basis_dt 조건이 필요합니다.")
if re.search(rf"\bBASIS_DT\s*=\s*{date_literal}", normalized):
    sys.exit(0)

m = re.search(rf"\bBASIS_DT\s+BETWEEN\s+{date_literal}\s+AND\s+{date_literal}", normalized)
if m:
    ensure_max_7_days(explicit_span(m.group(1), ">=", m.group(2), "<="))

le = re.search(rf"\bBASIS_DT\s*(>=|>)\s*{date_literal}", normalized)
ue = re.search(rf"\bBASIS_DT\s*(<=|<)\s*{date_literal}", normalized)
if le and ue:
    ensure_max_7_days(explicit_span(le.group(2), le.group(1), ue.group(2), ue.group(1)))

m = re.search(rf"\bBASIS_DT\s+BETWEEN\s+DATE_SUB\(\s*{current_date_expr}\s*,\s*INTERVAL\s*(\d+)\s+DAY\s*\)\s+AND\s+DATE_SUB\(\s*{current_date_expr}\s*,\s*INTERVAL\s*(\d+)\s+DAY\s*\)", normalized)
if m:
    ensure_max_7_days(relative_span(int(m.group(1)), ">=", int(m.group(2)), "<="))

lr = re.search(rf"\bBASIS_DT\s*(>=|>)\s*DATE_SUB\(\s*{current_date_expr}\s*,\s*INTERVAL\s*(\d+)\s+DAY\s*\)", normalized)
urs = re.search(rf"\bBASIS_DT\s*(<=|<)\s*DATE_SUB\(\s*{current_date_expr}\s*,\s*INTERVAL\s*(\d+)\s+DAY\s*\)", normalized)
urn = re.search(rf"\bBASIS_DT\s*(<=|<)\s*{current_date_expr}", normalized)
if lr and urs:
    ensure_max_7_days(relative_span(int(lr.group(2)), lr.group(1), int(urs.group(2)), urs.group(1)))
if lr and urn:
    ensure_max_7_days(relative_span(int(lr.group(2)), lr.group(1), 0, urn.group(1)))

fail("검증 가능한 basis_dt 범위 조건이 없습니다. 예: basis_dt BETWEEN '2026-03-01' AND '2026-03-07'")
'@

        $env:COMMAND_ENV = $cmd
        $env:QUERY_ENV = $queryTarget
        $pyOutput = @($pyScript | & $pythonCmd 2>&1)
        $pyExitCode = $LASTEXITCODE
        $pyResult = $pyOutput | Out-String
        $env:COMMAND_ENV = $null
        $env:QUERY_ENV = $null

        if ($pyExitCode -ne 0) {
            Write-Error $pyResult.Trim()
            exit 2
        }
    }

    $dmlPatterns = @(
        '\bINSERT\s+INTO\b',
        '\bUPDATE\s+[A-Z0-9_`\.]+',
        '\bDELETE\s+FROM\b',
        '\bCREATE\s+(OR\s+REPLACE\s+)?(TABLE|VIEW|SCHEMA|DATABASE|FUNCTION|PROCEDURE|MATERIALIZED\s+VIEW)\b',
        '\bDROP\s+(TABLE|VIEW|SCHEMA|DATABASE|FUNCTION|PROCEDURE|MATERIALIZED\s+VIEW)\b',
        '\bALTER\s+(TABLE|VIEW|SCHEMA|DATABASE)\b',
        '\bTRUNCATE\s+TABLE\b',
        '\bMERGE\s+INTO\b',
        '\bEXPORT\s+DATA\b',
        '\bCALL\s+'
    )

    foreach ($pattern in $dmlPatterns) {
        if ($upper -match $pattern) {
            Write-Error "BLOCKED: 데이터 변경(DML/DDL) 쿼리는 허용되지 않습니다. SELECT 문만 사용하세요."
            exit 2
        }
    }

    if ($cmd -match '--dry[_-]run') { exit 0 }

    try {
        if ($argv.Count -ge 2 -and $argv[0] -eq 'bq' -and $argv[1] -eq 'query') {
            $dryArgv = @([string]$argv[0], [string]$argv[1], '--dry_run')
            if ($argv.Count -gt 2) {
                $dryArgv += @($argv[2..($argv.Count - 1)] | ForEach-Object { [string]$_ })
            }

            $dryExe = $dryArgv[0]
            $dryArgs = if ($dryArgv.Count -gt 1) { @($dryArgv[1..($dryArgv.Count - 1)]) } else { @() }
            $dryResult = & $dryExe @dryArgs 2>&1 | Out-String
        } else {
            $dryCmd = $cmd -replace '(bq\s+query)', '$1 --dry_run'
            $dryResult = bash -c $dryCmd 2>&1 | Out-String
        }
        if ($dryResult -match '(\d+) bytes of data') {
            [long]$bytes = $Matches[1]
            if ($bytes -gt 100GB) {
                $gb = [math]::Round($bytes / 1GB, 1)
                Write-Error "BLOCKED: 이 쿼리는 약 ${gb}GB를 처리할 예정이에요 (허용 한도: 100GB)."
                Write-Error "날짜 범위나 파티션 조건을 더 좁혀서 다시 시도해주세요."
                exit 2
            }
        }
    } catch {
        # dry-run 실패 시 fail-open
    }

    exit 0
}
