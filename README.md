# MRT T&A Japan Plugin

마이리얼트립 T&A 일본팀 Claude Code 스킬 마켓플레이스

## 스킬 목록

| 스킬 | 설명 | 트리거 |
|------|------|--------|
| [gmail-triage](./skills/gmail-triage/) | Gmail 읽지 않은 메일 분류 + 라벨 + Slack 요약 | "메일 정리해줘", "inbox triage" |

## 설치

```bash
# settings.json의 extraKnownMarketplaces에 등록
{
  "mrt-tna-japan": {
    "source": {
      "source": "github",
      "repo": "seungmochoi-hue/mrt-tna-japan-plugin"
    }
  }
}
```

## 스킬 추가 방법

`skills/` 디렉토리에 새 폴더를 만들고 `SKILL.md`를 작성한 뒤 `.claude-plugin/marketplace.json`의 `skills` 배열에 경로를 추가합니다.
