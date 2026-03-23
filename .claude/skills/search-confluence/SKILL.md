---
name: search-confluence
description: Confluence에서 특정 주제에 대한 문서·설계서·가이드를 검색하여 실제 클릭 가능한 링크와 함께 정리한다. "컨플루언스에서 찾아줘", "문서 있나", "컨플루언스 검색", "위키에서 찾아줘" 등 Confluence 한정 검색 요청 시 사용한다.
---

# Search Confluence — Confluence 문서 검색

공통 절차는 `.claude/rules/search-template.md`를 따른다.

## 검색 도구

### 기본: Rovo Search

`searchAtlassian`을 검색어별로 **병렬 호출**한다. 결과에서 `type: "page"` 항목만 사용한다.

```
query: <검색어>
```

결과에 `url` 필드가 바로 포함되므로 URL 구성이 불필요하다.

### 보완: CQL 정밀 검색

Rovo 결과가 부족하거나 정밀한 필터가 필요하면 `searchConfluenceUsingCql`을 추가로 사용한다.

| 상황 | CQL 예시 |
|------|----------|
| 특정 스페이스 검색 | `type=page AND space=DATA AND title~"매출"` |
| 특정 기간 문서 | `type=page AND modified>=2026-01-01` |
| 특정 라벨 | `type=page AND label="architecture"` |

CQL 사용 시 `cloudId`는 `"myrealtrip.atlassian.net"`을 사용한다.

### 페이지 본문 읽기 (선택)

검색 결과 중 본문 확인이 필요한 페이지는 `getConfluencePage`로 읽는다.

```
cloudId: "myrealtrip.atlassian.net"
pageId: <검색 결과의 id에서 추출>
contentFormat: "markdown"
```

## 결과 포맷

```
## 검색 결과: {주제} (Confluence)

**1. {페이지 제목}**
- 스페이스: {스페이스명} | 수정일: {YYYY-MM-DD}
- {핵심 내용 2-3줄 요약}
- {URL}
```

## 소스 고유 규칙

- **Rovo 결과의 `url` 필드를 그대로 사용한다.** CQL 결과는 `https://myrealtrip.atlassian.net/wiki/spaces/{spaceKey}/pages/{pageId}` 형식으로 구성한다
