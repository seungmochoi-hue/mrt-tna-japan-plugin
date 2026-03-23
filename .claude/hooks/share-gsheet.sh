#!/bin/bash
# Google Sheets 스프레드시트를 myrealtrip.com 도메인 전체에 writer 권한으로 공유한다.
# Usage: ./.claude/hooks/share-gsheet.sh <spreadsheet_id>

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: ./.claude/hooks/share-gsheet.sh <spreadsheet_id>" >&2
  exit 1
fi

SPREADSHEET_ID="$1"
ADC_PATH="$HOME/.config/gcloud/application_default_credentials.json"

if [ ! -f "$ADC_PATH" ]; then
  echo "ERROR: ADC not found at $ADC_PATH. Run: gcloud auth application-default login" >&2
  exit 1
fi

QUOTA_PROJECT=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(d.get('quota_project_id',''))" "$ADC_PATH")
ACCESS_TOKEN=$(gcloud auth application-default print-access-token 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
  echo "ERROR: Failed to get access token. Run: gcloud auth application-default login" >&2
  exit 1
fi

# Drive API로 도메인 전체 공유 설정
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "https://www.googleapis.com/drive/v3/files/${SPREADSHEET_ID}/permissions" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: $QUOTA_PROJECT" \
  -d '{"type":"domain","role":"writer","domain":"myrealtrip.com"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "OK: myrealtrip.com domain writer permission set for spreadsheet $SPREADSHEET_ID"
else
  echo "ERROR: HTTP $HTTP_CODE — $BODY" >&2
  exit 1
fi
