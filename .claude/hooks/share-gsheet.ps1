# Google Sheets 스프레드시트를 myrealtrip.com 도메인 전체에 writer 권한으로 공유한다.
# Usage: .\.claude\hooks\share-gsheet.ps1 <spreadsheet_id>

param(
    [Parameter(Mandatory = $true)]
    [string]$SpreadsheetId
)

$ErrorActionPreference = "Stop"

$adcPath = Join-Path $env:APPDATA "gcloud\application_default_credentials.json"
if (-not (Test-Path $adcPath)) {
    Write-Error "ERROR: ADC not found at $adcPath. Run: gcloud auth application-default login"
}

$quotaProject = (Get-Content $adcPath | ConvertFrom-Json).quota_project_id
$accessToken = gcloud auth application-default print-access-token 2>$null

if (-not $accessToken) {
    Write-Error "ERROR: Failed to get access token. Run: gcloud auth application-default login"
}

$headers = @{
    Authorization         = "Bearer $accessToken"
    "Content-Type"        = "application/json"
    "x-goog-user-project" = $quotaProject
}

$body = @{
    type   = "domain"
    role   = "writer"
    domain = "myrealtrip.com"
} | ConvertTo-Json -Compress

try {
    $null = Invoke-RestMethod `
        -Method Post `
        -Uri "https://www.googleapis.com/drive/v3/files/$SpreadsheetId/permissions" `
        -Headers $headers `
        -Body $body

    Write-Output "OK: myrealtrip.com domain writer permission set for spreadsheet $SpreadsheetId"
}
catch {
    $message = $_.Exception.Message
    Write-Error "ERROR: $message"
}
