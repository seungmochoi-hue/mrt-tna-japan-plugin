---
name: search-jira
description: Jira에서 특정 주제에 대한 티켓·이슈를 검색하여 실제 클릭 가능한 링크와 함께 정리한다. "지라에서 찾아줘", "티켓 있나", "지라 검색", "이슈 찾아줘" 등 Jira 한정 검색 요청 시 사용한다.
---

# Search Jira — Jira 티켓 검색

공통 절차는 `.claude/rules/search-template.md`를 따른다.

## 검색 도구

### 기본: Rovo Search

`searchAtlassian`을 검색어별로 **병렬 호출**한다. 결과에서 `type: "issue"` 항목만 사용한다.

```
query: <검색어>
```

결과에 `url` 필드가 바로 포함되므로 URL 구성이 불필요하다.

### 보완: JQL 정밀 검색

Rovo 결과가 부족하거나 정밀한 필터가 필요하면 `searchJiraIssuesUsingJql`을 추가로 사용한다.

| 상황 | JQL 예시 |
|------|----------|
| 특정 프로젝트 검색 | `project=DP AND summary~"패키지 인원"` |
| 특정 상태 티켓 | `status="In Progress" AND text~"reservation"` |
| 특정 담당자 | `assignee="이승오" AND text~"travelers"` (한국어 이름은 표시 이름과 정확히 일치해야 함. 실패 시 account ID 사용 권장) |
| 최근 생성 티켓 | `created >= -30d AND text~"여행자 정보"` |

JQL 사용 시 `cloudId`는 `"myrealtrip.atlassian.net"`을 사용한다.

## 결과 포맷

```
## 검색 결과: {주제} (Jira)

**1. {이슈 키}: {이슈 제목}**
- 상태: {상태} | 수정일: {YYYY-MM-DD}
- {핵심 내용 2-3줄 요약}
- {URL}
```

## 소스 고유 규칙

- **Rovo 결과의 `url` 필드를 그대로 사용한다.** JQL 결과는 `https://myrealtrip.atlassian.net/browse/{issueKey}` 형식으로 구성한다
