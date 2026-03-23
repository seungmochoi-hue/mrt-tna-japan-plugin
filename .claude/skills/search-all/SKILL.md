---
name: search-all
description: Slack, Confluence, Jira를 동시에 검색하여 특정 주제에 대한 논의·문서·티켓을 실제 클릭 가능한 링크와 함께 정리한다. "찾아줘", "검색해줘", "관련 논의", "히스토리", "링크 줘", "이전에 논의한 적 있나", "문서 있나", "티켓 있나" 등 사내 지식 탐색 요청 시 사용. Slack URL을 읽는 것(slack-url-reader)과는 다르게, 키워드 기반으로 Slack·Confluence·Jira를 샅샅이 탐색하는 skill이다. 사용자가 "슬랙에서만" 등 특정 소스를 지정하면 해당 소스만 검색한다.
---

# Search All — Slack · Confluence · Jira 통합 검색

공통 절차는 `.claude/rules/search-template.md`를 따른다.

## 핵심 원칙

- **3소스 병렬 검색**: Slack, Confluence, Jira를 한 메시지에서 동시에 검색한다. 사용자가 특정 소스를 지정하면 해당 소스만.
- **링크 정확성**: 각 소스별로 검색 결과가 반환하는 URL/permalink를 그대로 사용한다. URL을 직접 구성하지 않는다.

## 절차

### Step 1 — 검색어 생성

공통 템플릿의 "검색어 생성" 절차를 따른다.

### Step 2 — 3소스 병렬 검색

**한 메시지에서** 아래를 **동시에** 호출한다. 각 소스의 도구·파라미터는 해당 skill을 참조한다.

- **Slack**: `search-slack` skill의 검색 절차
- **Confluence**: `search-confluence` skill의 검색 절차
- **Jira**: `search-jira` skill의 검색 절차

### Step 3 — 결과 정리

검색 결과를 **소스별로 구분**하여 정리한다. 각 소스의 결과 포맷은 해당 skill을 따른다.

```
## 검색 결과: {주제}

### Slack
(search-slack 결과 포맷)

---

### Confluence
(search-confluence 결과 포맷)

---

### Jira
(search-jira 결과 포맷)
```

- 검색 결과가 없는 소스는 섹션을 생략한다
- 중복 제거·정렬·"결과 없음" 안내는 공통 템플릿을 따른다

## 특정 소스만 검색

| 사용자 표현 | 검색 소스 |
|------------|----------|
| "슬랙에서 찾아줘" | Slack만 |
| "컨플루언스에 문서 있나" | Confluence만 |
| "지라 티켓 찾아줘" | Jira만 |
| "찾아줘", "검색해줘" (소스 미지정) | Slack + Confluence + Jira 모두 |

## 소스별 고유 규칙

- **Slack permalink**: 반드시 검색 결과의 `Permalink` 필드 값을 그대로 사용한다. message_ts에서 URL을 구성하면 링크가 깨진다.
- **Confluence/Jira URL**: Rovo 검색 결과의 `url` 필드를 우선 사용한다. CQL/JQL 결과는 ID 기반으로 URL을 구성한다.
