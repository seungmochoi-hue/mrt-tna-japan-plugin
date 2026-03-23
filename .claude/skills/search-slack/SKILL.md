---
name: search-slack
description: Slack에서 특정 주제에 대한 논의·히스토리를 검색하여 실제 클릭 가능한 permalink 링크와 함께 정리한다. "슬랙에서 찾아줘", "슬랙 검색", "슬랙에서 관련 논의", "슬랙 링크 줘" 등 Slack 한정 검색 요청 시 사용한다.
---

# Search Slack — Slack 검색

공통 절차는 `.claude/rules/search-template.md`를 따른다.

## 검색 도구

`slack_search_public_and_private`를 검색어별로 **병렬 호출**한다.

```
query: <검색어>
limit: 10
response_format: "detailed"    ← Permalink를 받으려면 반드시 detailed
include_context: false          ← 결과 크기 줄이기 (필요시 true로 재검색)
```

**검색 팁**:
- `from:` 필터는 **영문 username**만 동작한다. 한글 이름은 사용하지 않는다.
- `in:#채널명` 필터는 잘 동작한다. 채널을 알고 있으면 적극 활용한다.
- 정확한 문구를 찾을 때는 `"큰따옴표"`로 감싼다.
- 기간 필터: `after:2025-01-01`, `before:2026-01-01`

## 스레드 맥락

중요한 메시지의 전후 맥락이 필요하면 `slack_read_thread`로 스레드를 읽는다. 병렬로 실행한다.

## 결과 포맷

```
## 검색 결과: {주제} (Slack)

### #{채널명}

**1. {메시지 요약 (1줄)}**
- 작성자: {이름} | 날짜: {YYYY-MM-DD}
- {핵심 내용 2-3줄 요약}
- {permalink URL}
```

## 소스 고유 규칙

- 같은 스레드의 메시지는 하나로 묶고, 가장 관련 높은 메시지의 permalink를 사용한다
- **Permalink는 반드시 검색 결과의 `Permalink` 필드 값을 그대로 사용한다.** message_ts에서 URL을 구성하면 링크가 깨진다
