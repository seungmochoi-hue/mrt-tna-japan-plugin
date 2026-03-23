#!/usr/bin/env bash
# 오래된 세션 정리 (기본 2시간)
# Usage: .claude/dispatcher/cleanup.sh [max_age_hours]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSIONS_FILE="$SCRIPT_DIR/sessions.json"
LOG_DIR="$SCRIPT_DIR/logs"
MAX_AGE_HOURS="${1:-2}"

[ -f "$SESSIONS_FILE" ] || exit 0

python3 -c "
import json
from datetime import datetime, timedelta, timezone

with open('$SESSIONS_FILE', 'r') as f:
    sessions = json.load(f)

cutoff = datetime.now(timezone.utc) - timedelta(hours=$MAX_AGE_HOURS)
expired = []

for thread_ts, info in sessions.items():
    ts = info.get('last_used', info.get('created_at', ''))
    if ts:
        dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        if dt < cutoff:
            expired.append(thread_ts)

for ts in expired:
    del sessions[ts]
    print(f'[cleanup] expired thread={ts}')

with open('$SESSIONS_FILE', 'w') as f:
    json.dump(sessions, f, indent=2, ensure_ascii=False)

print(f'[cleanup] removed={len(expired)} remaining={len(sessions)}')
"

# 오래된 로그, stale lock 정리
find "$LOG_DIR" -name "worker_*.log" -mmin +$((MAX_AGE_HOURS * 60)) -delete 2>/dev/null || true
find "$SCRIPT_DIR/locks" -name "thread_*" -mmin +30 -exec rm -rf {} + 2>/dev/null || true
