# Slack 디스패처 모드 (최우선 규칙)

## 개요

`<channel source="slack-channel">` 메시지를 수신하면, main agent는 **항상** 디스패처로 동작한다. 직접 분석하거나 직접 reply하지 않는다.

## 핵심 원칙

**main agent는 Slack 메시지를 절대 직접 처리하지 않는다.** 모든 메시지는 워커 세션에 위임한다.

단, **워커 세션은 `slack-colleague-mode.md`의 reply/silence 규칙을 그대로 따른다.**

- 즉, 모든 Slack 메시지를 dispatch하되 **모든 메시지에 답하는 것은 아니다**.
- 워커는 스레드 follow-up에서 `slack-colleague-mode.md` 기준으로 reply 또는 침묵을 결정한다.
- main agent의 역할은 어디까지나 dispatch + done이며, 실제 응답 여부 판단은 워커가 맡는다.

## 절차 (모든 Slack 메시지에 적용)

`<channel source="slack-channel">` 메시지를 수신하면:

1. 메시지 태그에서 메타데이터를 추출한다:

   | 필드 | 추출 위치 | 예시 |
   |------|----------|------|
   | `channel_id` | 태그의 `channel_id` 속성 | `C0ANJN5C4CR` |
   | `thread_ts` | 태그의 `thread_ts` 속성. 없으면 `message_ts` 사용 | `1774244008.648069` |
   | `message_ts` | 태그의 `message_ts` 속성 | `1774244014.694359` |
   | `user_name` | 태그의 `user_name` 속성 (**`user_id` 아님**) | `정현영` |
   | 본문 | 태그 내부 텍스트 (멘션 `<@...>` 제거) | `거래액 숙박 최근 7일 뽑아봐` |

   **주의**: `user_name`은 반드시 태그의 `user_name` 속성에서 가져온다. user_id(`U0A6K1DDSF6` 형태)를 넘기지 않는다.

2. 디스패치 스크립트를 **background로** 실행한다:
   ```bash
   .claude/dispatcher/dispatch.sh "<channel_id>" "<thread_ts>" "<message_ts>" "<user_name>" "<message_body>" &
   ```

3. **즉시** `done`을 호출하여 다음 메시지를 수신한다.

**금지 행동**:
- `slack-channel - reply` MCP 호출 금지 (워커가 Bot Token curl로 답변함)
- analyst subagent 직접 호출 금지 (워커가 함)
- 분석, 쿼리 실행, 파일 읽기 금지 (워커가 함)
- "바로 시작합니다!" 같은 중간 메시지 전송 금지

## 워커 세션 관리

- 스레드별로 세션 ID가 매핑됨 (`.claude/dispatcher/sessions.json`)
- 새 스레드: 새 세션 생성 (`--session-id`)
- 기존 스레드 follow-up: 세션 resume (`--resume`) → 이전 맥락 유지
- 같은 스레드 내 동시 요청은 lock으로 직렬화 (레이스 컨디션 방지)
- 워커는 Bot Token + python3 urllib로 Analytix Helper 봇으로 스레드에 응답

## 제약사항

- 디스패처 모드에서 main agent는 분석을 하지 않는다. 메타데이터 추출 + dispatch + done만 한다.
- 워커가 실패하면 main agent는 감지할 수 없다. 로그는 `.claude/dispatcher/logs/`에 남는다.
- 워커는 파일 수정 금지 (slack-channel-readonly 규칙 적용).
- 워커가 침묵 케이스로 판단하면 Slack에 아무 메시지도 보내지 않고 종료할 수 있다.
