# Slack URL 읽기 규칙

## 트리거

사용자 메시지에 Slack URL이 포함되어 있으면 이 규칙이 자동 적용된다.

Slack URL 패턴:
- `https://*.slack.com/archives/<channel_id>/p<message_ts>`
- `https://app.slack.com/client/<team_id>/<channel_id>/thread/<channel_id>-<message_ts>`
- `https://*.slack.com/archives/<channel_id>/p<message_ts>?thread_ts=<thread_ts>`

## 핵심 원칙

**Slack URL이 주어지면, permalink 정보와 해당 스레드 전체를 파악한 뒤, 관련 내용에 대한 분석을 제안한다.**

## 절차

### Step 1 — URL 파싱

Slack URL에서 아래 정보를 추출한다.

| 항목 | 추출 방법 |
|------|----------|
| `channel_id` | URL 경로의 `/archives/<channel_id>/` 부분 |
| `message_ts` | `p` 뒤의 숫자를 `.` 포함 형식으로 변환 (예: `p1709876543210123` → `1709876543.210123`) |
| `thread_ts` | 쿼리파라미터 `?thread_ts=`가 있으면 추출. 없으면 `message_ts`를 스레드 루트로 간주 |

### Step 2 — 맥락 수집 (병렬 실행)

아래 작업을 **병렬로 동시에** 실행한다.

1. **Permalink 파싱**: `slack_parse_permalink`로 `channel_id`, `message_ts`, `thread_ts`를 추출한다.
2. **스레드 전체 읽기**: `slack_fetch_thread`로 해당 permalink의 스레드 전체를 읽는다.

### Step 3 — 맥락 요약 및 분석 제안

수집한 내용을 아래 형식으로 정리하여 사용자에게 보여준다.

```
## Slack 대화 요약

### 원본 메시지
- **작성자**: @이름
- **채널**: #채널명
- **시간**: YYYY-MM-DD HH:MM (KST)
- **내용**: 메시지 본문 요약

### 대화 맥락
(루트 메시지와 스레드 흐름 기준으로 어떤 논의가 이어졌는지 요약)

### 스레드 내용
(스레드에 달린 댓글들의 핵심 내용 요약. 참여자, 주요 논점, 결론 등)

---

이 대화를 바탕으로 아래 분석을 진행할 수 있어요.

### 제안 분석
1.  (대화 내용에서 파악된 데이터 분석 가능 항목 1)
2.  (대화 내용에서 파악된 데이터 분석 가능 항목 2)
3.  (대화 내용에서 파악된 데이터 분석 가능 항목 3)

**또는 요청사항을 글로 적어주셔도 됩니다!**
```

### 제안 분석 생성 규칙

- 대화 내용에서 **데이터 확인이 필요한 부분**을 찾아 분석 항목으로 제안한다.
  - 예: "매출이 떨어진 것 같다" → "최근 매출 추이 분석"
  - 예: "이 수치가 맞나?" → "해당 지표 교차 검증"
  - 예: "원인이 뭘까" → "원인 분석 (기간별/도메인별 분해)"
- 데이터 분석과 무관한 대화(일정 조율, 일반 논의 등)이면, 대화 요약만 제공하고 "추가로 궁금한 점이 있으시면 말씀해주세요!"로 마무리한다.
- 제안 항목은 이 프로젝트에서 실제로 실행 가능한 것만 포함한다 (BigQuery 쿼리, dbt 모델 분석 등).

## 규칙

- Slack URL이 주어지면 **확인 질문 없이 바로 읽기를 실행**한다. 요건 구체화 단계를 건너뛴다.
- `slack_parse_permalink`와 `slack_fetch_thread`는 반드시 병렬로 실행한다.
- Slack MCP 플러그인 인증이 필요하면 Claude Code에서 `/mcp`를 열고 Slack 항목의 `Authenticate`를 선택하도록 안내한다. 브라우저가 자동으로 열리지 않으면 제공된 URL을 직접 열고, redirect 실패 시 callback URL을 Claude Code prompt에 붙여넣도록 안내한다.
- 요약은 한국어로 작성한다.
- 채널 전체 타임라인 조회는 현재 표준 Slack MCP 범위에 없으므로, 요약 범위는 permalink와 해당 스레드로 한정한다.
- **스레드 깊이 제한**: 스레드 메시지가 100건을 초과하면 최근 100건만 읽고, "스레드가 매우 길어서 최근 100건만 요약했어요"로 안내한다.
- **스레드 없는 단일 메시지**: URL에 `thread_ts`가 없고, `slack_fetch_thread` 결과가 루트 메시지 1건뿐이면 스레드 섹션을 생략하고 해당 메시지만 요약한다.
- 사용자가 URL과 함께 별도 지시를 주면(예: "이 스레드에서 언급된 매출 분석해줘"), 요약 후 해당 지시를 바로 실행한다.
- **스레드 내 외부 링크 분석 (필수)**: main agent가 스레드 내 외부 링크(Redash URL, Google Sheets URL, Confluence URL 등)를 **모두 식별**하고, 각 링크를 **opus subagent로 병렬 분사**한다. URL만 나열하고 넘어가지 않는다.
  - **Redash URL**: `redash-analyzer` (opus) subagent로 위임. API를 통해 쿼리 SQL 조회, 로직 분석, BQ 실행 검증.
  - **Google Sheets URL**: `analyst` (opus) subagent로 위임. Google Sheets MCP로 시트 내용 읽기, 수식 파악, 로직 분석.
  - **Confluence URL**: `analyst` (opus) subagent로 위임. Atlassian MCP로 문서 내용 읽기, 핵심 요약.
  - 여러 링크가 있으면 **한 메시지에서 subagent를 동시에 호출**한다.
