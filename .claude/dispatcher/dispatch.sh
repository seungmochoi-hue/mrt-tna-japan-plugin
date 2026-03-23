#!/usr/bin/env bash
# Slack Dispatcher - 스레드별 워커 세션 관리 및 spawn
#
# Usage:
#   .claude/dispatcher/dispatch.sh <channel_id> <thread_ts> <message_ts> <user_name> <message_body>
#
# - 새 스레드: 새 세션 생성 (claude -p --session-id)
# - 기존 스레드: 세션 resume (claude -p --resume)
# - 같은 스레드 내 동시 요청은 lock으로 직렬화
# - 세션 매핑은 sessions.json에 저장

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SESSIONS_FILE="$SCRIPT_DIR/sessions.json"
WORKER_PROMPT_FILE="$SCRIPT_DIR/worker-prompt.txt"
LOG_DIR="$SCRIPT_DIR/logs"
LOCK_DIR="$SCRIPT_DIR/locks"
CREDS_FILE="$REPO_DIR/credentials/slack-bot.env"

# Bot Token 로드
if [ -f "$CREDS_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CREDS_FILE"
fi
: "${SLACK_BOT_TOKEN:?SLACK_BOT_TOKEN not found in $CREDS_FILE}"

# Args
CHANNEL_ID="${1:?channel_id required}"
THREAD_TS="${2:?thread_ts required}"
MESSAGE_TS="${3:?message_ts required}"
USER_NAME_RAW="${4:?user_name required}"
MESSAGE_BODY="${5:?message_body required}"

# user_id(U로 시작)가 들어오면 Slack API로 display name 조회
if [[ "$USER_NAME_RAW" =~ ^U[0-9A-Z]+$ ]]; then
    USER_NAME=$(python3 -c "
import json, urllib.request
req = urllib.request.Request(
    'https://slack.com/api/users.info?user=$USER_NAME_RAW',
    headers={'Authorization': 'Bearer $SLACK_BOT_TOKEN'}
)
resp = json.loads(urllib.request.urlopen(req).read())
profile = resp.get('user', {}).get('profile', {})
print(profile.get('display_name') or profile.get('real_name') or '$USER_NAME_RAW')
" 2>/dev/null || echo "$USER_NAME_RAW")
else
    USER_NAME="$USER_NAME_RAW"
fi

# Init
mkdir -p "$LOG_DIR" "$LOCK_DIR"
[ -f "$SESSIONS_FILE" ] || echo '{}' > "$SESSIONS_FILE"

# 스레드별 lock 파일 경로 (. → _ 로 치환)
LOCK_FILE="$LOCK_DIR/thread_${THREAD_TS//./_}.lock"

# lock 획득 (같은 스레드 직렬화, 최대 180초 대기)
acquire_lock() {
    local max_wait=180
    local waited=0
    while ! mkdir "$LOCK_FILE" 2>/dev/null; do
        # lock을 잡은 프로세스가 죽었는지 확인
        if [ -f "$LOCK_FILE/pid" ]; then
            local lock_pid
            lock_pid=$(cat "$LOCK_FILE/pid" 2>/dev/null || echo "")
            if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                echo "[dispatch] stale lock detected (pid=$lock_pid dead), removing"
                rm -rf "$LOCK_FILE"
                continue
            fi
        fi
        if [ "$waited" -ge "$max_wait" ]; then
            echo "[dispatch] WARN: lock timeout after ${max_wait}s, proceeding anyway"
            rm -rf "$LOCK_FILE"
            mkdir "$LOCK_FILE" 2>/dev/null || true
            break
        fi
        sleep 2
        waited=$((waited + 2))
        echo "[dispatch] waiting for lock on thread=$THREAD_TS (${waited}s)"
    done
    echo $$ > "$LOCK_FILE/pid"
}

release_lock() {
    rm -rf "$LOCK_FILE"
}

# 세션 조회
get_session_id() {
    python3 -c "
import json
with open('$SESSIONS_FILE') as f:
    sessions = json.load(f)
print(sessions.get('$THREAD_TS', {}).get('session_id', ''))
"
}

# 세션 저장/업데이트
save_session() {
    local session_id="$1"
    local is_update="${2:-false}"
    python3 -c "
import json
with open('$SESSIONS_FILE', 'r') as f:
    sessions = json.load(f)
if '$is_update' == 'true' and '$THREAD_TS' in sessions:
    sessions['$THREAD_TS']['last_used'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
else:
    sessions['$THREAD_TS'] = {
        'session_id': '$session_id',
        'channel_id': '$CHANNEL_ID',
        'user_name': '$USER_NAME',
        'created_at': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
    }
with open('$SESSIONS_FILE', 'w') as f:
    json.dump(sessions, f, indent=2, ensure_ascii=False)
"
}

# 워커 프롬프트 구성
build_prompt() {
    cat <<PROMPT
[Slack Worker Mode]
channel_id: $CHANNEL_ID
thread_ts: $THREAD_TS
bot_token: $SLACK_BOT_TOKEN
user: $USER_NAME
message: $MESSAGE_BODY

위 Slack 메시지를 처리해줘.

- `slack-colleague-mode.md` 기준으로 reply가 필요한 경우에만 Slack 스레드에 답변해.
- 침묵 케이스면 Slack에 아무 메시지도 보내지 말고 조용히 종료해.
- 분석 요청이면 필요한 분석을 수행한 뒤 결과를 스레드에 답변해.

Slack 답변 방법 — 반드시 아래 python3 패턴을 사용해:

python3 -c "
import json, urllib.request
data = json.dumps({
    'channel': '$CHANNEL_ID',
    'thread_ts': '$THREAD_TS',
    'text': '''여기에 응답 내용'''
}).encode()
req = urllib.request.Request(
    'https://slack.com/api/chat.postMessage',
    data=data,
    headers={
        'Authorization': 'Bearer $SLACK_BOT_TOKEN',
        'Content-Type': 'application/json; charset=utf-8'
    }
)
resp = urllib.request.urlopen(req)
print(json.loads(resp.read())['ok'])
"

중요:
- 반드시 위 python3 패턴으로 답변해. slack_send_message MCP 도구는 사용하지 마 (사용자 계정으로 보내짐).
- slack-channel MCP의 reply/done 도구도 사용하지 마.
- python3 json.dumps가 특수문자를 자동 처리하므로 이스케이프 걱정 없음.
- 침묵 케이스면 위 python3 패턴도 호출하지 마.
PROMPT
}

# ── 메인 로직 ──

# 1. lock 획득 (같은 스레드 직렬화)
acquire_lock

# cleanup on exit
trap release_lock EXIT

SESSION_ID=$(get_session_id)
PROMPT=$(build_prompt)
LOG_FILE="$LOG_DIR/worker_${THREAD_TS//./_}_$(date +%s).log"

if [ -z "$SESSION_ID" ]; then
    # 새 스레드 → 새 세션
    SESSION_ID=$(uuidgen)
    save_session "$SESSION_ID"

    echo "[dispatch] NEW session=$SESSION_ID thread=$THREAD_TS user=$USER_NAME"

    claude -p \
        --session-id "$SESSION_ID" \
        --max-budget-usd 5.00 \
        --append-system-prompt "$(cat "$WORKER_PROMPT_FILE" 2>/dev/null || echo '')" \
        "$PROMPT" \
        > "$LOG_FILE" 2>&1
else
    # 기존 스레드 → resume
    save_session "$SESSION_ID" "true"

    echo "[dispatch] RESUME session=$SESSION_ID thread=$THREAD_TS user=$USER_NAME"

    claude -p \
        --resume "$SESSION_ID" \
        --max-budget-usd 5.00 \
        "$PROMPT" \
        > "$LOG_FILE" 2>&1
fi

echo "[dispatch] done log=$LOG_FILE"
