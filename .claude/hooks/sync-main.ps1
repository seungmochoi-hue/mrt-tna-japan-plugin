#!/usr/bin/env pwsh
# main 브랜치 동기화 보장. 10분 이내 체크 이력이 있으면 스킵한다.
# 현재 브랜치가 main이고 작업 트리가 깨끗할 때만 fast-forward sync를 시도한다.

param([Parameter(ValueFromPipeline = $true)][string]$InputJson)
process { if (-not $InputJson) { $InputJson = $_ } }

end {
    # stdin 소비 완료

    $projDir = $env:CLAUDE_PROJECT_DIR
    if (-not $projDir) { exit 0 }

    $hash = [System.BitConverter]::ToString(
        [System.Security.Cryptography.MD5]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($projDir)
        )
    ).Replace('-', '').ToLower()
    $syncFlag = Join-Path $env:TEMP "claude-sync-$hash"
    $lockFile = Join-Path $env:TEMP "claude-sync-lock-$hash"
    $syncInterval = 600

    # Mutex lock to prevent race conditions from concurrent invocations
    try {
        [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write).Close()
    } catch {
        exit 0  # Another instance is running
    }
    try {

    # 최근 체크 이력이 있으면 즉시 통과
    if (Test-Path $syncFlag) {
        $last = (Get-Item $syncFlag).LastWriteTime
        $elapsed = ((Get-Date) - $last).TotalSeconds
        if ($elapsed -lt $syncInterval) { exit 0 }
    }

    Set-Location $projDir 2>$null
    if (-not $?) { exit 0 }

    $currentBranch = git symbolic-ref --quiet --short HEAD 2>$null
    if ($currentBranch -ne 'main') {
        $switched = git checkout main --quiet 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[sync] 브랜치를 main으로 전환했습니다. (이전: $currentBranch)" -ForegroundColor Yellow
        } else {
            Write-Host "[sync] main 전환 실패 — 로컬 변경사항이 있을 수 있습니다. (현재: $currentBranch)" -ForegroundColor Yellow
            exit 0
        }
    }

    # fetch 후 로컬 vs 리모트 비교
    git fetch origin main --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { New-Item $syncFlag -Force >$null; exit 0 }

    $local = git rev-parse HEAD 2>$null
    $remote = git rev-parse origin/main 2>$null

    if (-not $local -or -not $remote) {
        New-Item $syncFlag -Force >$null
        exit 0
    }

    if ($local -ne $remote) {
        git diff --quiet --ignore-submodules HEAD -- 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[sync] main에 로컬 변경사항이 있어 자동 동기화를 건너뜁니다." -ForegroundColor Yellow
            New-Item $syncFlag -Force >$null
            exit 0
        }

        git merge-base --is-ancestor $local $remote 2>$null
        if ($LASTEXITCODE -eq 0) {
            git pull --ff-only origin main --quiet 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[sync] main 브랜치를 origin/main 최신 커밋으로 동기화했습니다." -ForegroundColor Green
            }
        } else {
            Write-Host "[sync] 로컬 main이 origin/main과 fast-forward 관계가 아니어서 자동 동기화를 건너뜁니다." -ForegroundColor Yellow
        }
    }

    New-Item $syncFlag -Force >$null

    } finally {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }
    exit 0
}
