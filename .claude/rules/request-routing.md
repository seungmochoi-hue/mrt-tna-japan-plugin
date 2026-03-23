# 요청 라우팅 및 분석 실행 규칙

- 모델(.sql)과 YAML은 반드시 함께 읽는다. 둘 중 하나만 읽고 판단하지 않는다.
- 데이터 수치/분포/건수는 추측하지 않고 BigQuery 쿼리로 확인한다.

## Main Agent 역할 (최우선 원칙)

**main agent가 전체 작업을 이끈다.** subagent는 전문 작업을 위임받아 실행하는 실무자이고, main agent는 라우팅·검수·최종 응답을 책임지는 오케스트레이터다.

### main agent가 직접 하는 일

| 작업 | 설명 |
|------|------|
| 사용자 요청 해석 | 요청 유형 판단, 모호도 분류, 요건 구체화 질문 |
| 라우팅 결정 | 어떤 subagent에, 어떤 모델로, 어떤 지시를 줄지 결정 |
| Slack 스레드 읽기 | Slack MCP로 직접 스레드 읽기·요약 (subagent 위임 안 함) |
| subagent 결과 검수 | 결과를 받아서 품질 확인, 부족하면 반려·재지시 |
| 최종 응답 구성 | subagent 결과를 종합하여 사용자에게 응답 (EDA 스타일) |
| 후속 옵션 제시 | 다음 탐색 방향을 사용자에게 제안 |

### subagent 결과 검수 규칙

subagent가 결과를 반환하면, main agent가 아래 기준으로 검수한다.

| 검수 항목 | 반려 조건 | 반려 시 조치 |
|----------|----------|------------|
| 쿼리 원문 누락 | 사용한 쿼리가 결과에 포함되지 않음 | 쿼리 원문을 포함하여 재실행 지시 |
| YAML 미확인 | dbt 모델 YAML을 읽지 않고 컬럼 의미를 추측 | YAML 확인 후 재실행 지시 |
| 잘못된 테이블/컬럼 | 존재하지 않는 테이블·컬럼 사용, 규칙 위반 (`DOMAIN_NM` 버티컬 분류 등) | 올바른 테이블·컬럼으로 재실행 지시 |
| 규칙 위반 | `sales-query-rules.md`, `bigquery-rules.md` 등의 규칙 위반 | 규칙을 명시하여 재실행 지시 |
| 결과 부실 | 데이터가 비어 있거나, 요청과 다른 지표를 반환 | 원인 파악 후 수정 지시 또는 다른 접근 시도 |

**반려 프로세스**:
1. subagent 결과를 검토한다
2. 위 기준에 해당하면 **사용자에게 부실한 결과를 전달하지 않고**, subagent에 재지시한다
3. 재지시 시 무엇이 부족한지, 어떻게 수정해야 하는지를 구체적으로 명시한다
4. 2회 반려 후에도 해결되지 않으면, main agent가 직접 처리하거나 사용자에게 상황을 설명한다

## 지원 범위 (필수 확인)

핵심 수치 조회와 데이터 검증의 기본 소스는 **BigQuery(`bq` CLI)** 다. 다만 URL 기반 맥락 파악이나 문서/시트 분석은 아래 전용 도구를 예외적으로 사용한다.

| 요청 | 대응 |
|------|------|
| 운영 DB 직접 조회 (MySQL, PostgreSQL 등) | **불가**. "이 에이전트는 BigQuery만 조회할 수 있어요"라고 안내 |
| 운영 DB 접속 정보 요청 (host, port, 계정) | **금지**. 접속 정보를 묻거나 터널링/VPN 접속을 제안하지 않는다 |
| 운영 DB 데이터가 필요한 경우 | BigQuery `edw` 데이터셋의 `DW_MRT_*` 복제 테이블로 대체 가능한지 안내 |
| Slack permalink 맥락 읽기 | main agent가 Slack 도구로 스레드 읽기·요약 |
| Redash URL 분석 | `redash-analyzer`가 API로 SQL/메타데이터 조회 후 BQ 검증 |
| Google Sheets URL 분석 | `analyst`가 Google Sheets MCP로 시트 내용·수식 분석 |
| Confluence URL 분석 | `analyst`가 Atlassian MCP로 문서 내용 요약 |

**핵심 원칙: 할 수 없는 일을 할 수 있는 것처럼 답변하지 않는다.**

## 데이터 추출/분석 요청 라우팅

사용자가 요청하면, 요청 유형을 판단하여 적절한 subagent/skill에 위임한다.

| 조건 | 위임 대상 | 모델 | 예시 |
|------|----------|------|------|
| 데이터 추출/분석 | `analyst` (Agent) | opus | "최근 7일 항공 매출", "왜 매출이 떨어졌는지" |
| dbt 모델 탐색 (로직/lineage/스키마) | `analyst` (Agent) | opus | "이 테이블 어디서 와?", "MART_SALE_D 컬럼 뭐야" |
| Slack/Confluence/Jira/Google Sheets 검색 | `analyst` (Agent) | opus | "찾아줘", "검색해줘", "관련 논의", "문서 있나" |
| Slack URL 공유 (대화 맥락 파악) | **main agent 직접 처리** | — | Slack 링크 붙여넣기, "이 스레드 봐줘" |
| Redash URL 분석 (쿼리/대시보드) | `redash-analyzer` (Agent) | opus | Redash URL 포함 메시지, "Redash", "리대시" |
| Google Sheets URL 분석 (로직/수식 파악) | `analyst` (Agent) | opus | Google Sheets URL 포함 메시지, "이 시트 봐줘" |
| 데이터 내보내기 (Google Sheets) | `analyst` (Agent) | sonnet | "저장해줘", "다운로드", "내보내기", 후속 5번 |
| 시각화/대시보드 | `chart-builder` (Agent) | sonnet | "시각화해줘", "차트", "대시보드", 후속 6번 |
| Slack 공유 | `slack-share` (Skill) | — | "슬랙에 공유해줘", "채널에 올려줘" |
| 환경 설정, 초기 세팅 점검, 인증 에러 | `setup-helper` (Agent) | sonnet | 인증 실패, "로그인", "초기세팅 다 되어 있나?" |

판단 기준:
- "뽑아줘", "조회해줘", "보여줘", "분석해줘", "원인", "왜", "추이", "비교" -> `analyst`
- "이 테이블 어디서 와?", "컬럼 뭐야", "upstream", "lineage" -> `analyst`
- "찾아줘", "검색해줘", "관련 논의", "히스토리", "링크 줘", "문서 있나", "티켓 있나" -> `analyst`
- "슬랙에서 찾아줘", "컨플루언스에서 찾아줘", "지라에서 찾아줘", "구글시트에서 찾아줘" -> `analyst`
- Slack URL(`*.slack.com/archives/*`) 포함 메시지 -> **main agent가 직접** 스레드 읽기 + 요약. subagent로 위임하지 않는다. 스레드 내 Redash/Google Sheets/Confluence 링크가 발견되면 **각각 opus subagent로 병렬 분사**
- Redash URL(`*redash.myrealtrip.net/*`) 포함 메시지, "Redash", "리대시" -> `redash-analyzer` (opus). API를 통해 쿼리 SQL 조회, 로직 분석, BQ에서 직접 실행하여 결과 검증
- Google Sheets URL(`docs.google.com/spreadsheets/*`) 포함 메시지, "이 시트 봐줘", "이 시트 분석" -> `analyst` (opus). Google Sheets MCP로 시트 내용 읽기, 수식 파악(`get_sheet_formulas`), 데이터 구조·로직 분석. API Key 미설정 시 `gsheets-auth` skill 자동 실행
- "저장해줘", "다운로드", "CSV로 뽑아줘", "export", "구글시트에 저장", "내보내기", 후속 5번 -> `analyst` (sonnet)로 `save-to-gsheets` skill 실행. 50행 미만은 Google Sheets MCP, 50행 이상은 로컬 CSV 다운로드. 사용자가 명시적으로 "구글시트에 저장"이라고 한 경우에만 행 수와 무관하게 Google Sheets로 저장. Google Sheets MCP 에러 발생 시 `gsheets-auth` skill 자동 실행 후 재시도. **최종 fallback**: 2차 재시도도 실패하면 로컬 CSV 다운로드로 자동 전환.
- "시각화", "차트", "대시보드", "그래프", 후속 6번 -> `chart-builder` (sonnet)
- "슬랙", "Slack", "채널에 공유", "채널에 올려", "슬랙으로 보내" -> `slack-share` skill. 인증 에러 시 Claude Code의 `/mcp` 공식 OAuth 흐름으로 안내한다 (선택지 제시 금지)
- "구글시트", "Google Sheets", "스프레드시트", "시트에서 읽어", "시트에 저장", "시트에 올려" -> Google Sheets MCP 도구 직접 호출. 에러 발생 시 `gsheets-auth` skill 자동 실행 후 재시도 (선택지 제시 금지)
- bq/gh/python/uv/uvx/Atlassian/Google Sheets 인증 에러, "인증", "로그인", "설정", "연동", "세팅", "초기 세팅", "초기세팅", "환경 점검", "준비 됐나", "다 되어 있나", "온보딩" -> `setup-helper` (sonnet) (자동 설치/인증. 선택지 제시 금지. `.claude/rules/auto-install.md` 참조)
- 초기 세팅/환경 점검 질문은 일반 분석 응답으로 처리하지 말고 반드시 `setup-helper`를 먼저 실행
- "EDA", "프로파일링", "분포", "통계", "요약", "상관관계", CSV 파일 분석 -> `csv-summarizer` (Skill)

## Skill 연계 흐름

각 skill은 독립적으로 사용할 수도, 연계할 수도 있다. 데이터 소스는 **BigQuery 쿼리 결과** 또는 **Google Sheets** 모두 가능.

```
                    ┌──> csv-summarizer (EDA/통계 분석)
bq-query ──────────┤
  또는              ├──> analyst:sonnet (save-to-gsheets 실행)
Google Sheets ─────┤
                    ├──> chart-builder:sonnet (반응형 대시보드)
                    └──> slack-share (채널 스레드 공유)

analyst:opus (통합 분석/EDA) ──> 위 어느 것이든 선행 가능

Google Sheets URL ──> analyst:opus (시트 읽기·수식 파악·로직 분석) ──> 분석 제안

Slack URL ──> main agent가 직접 스레드 읽기·요약
              └── 링크 발견 시 opus subagent 병렬 분사:
                  ├── redash-analyzer:opus (Redash 링크)
                  ├── analyst:opus (GSheets 링크)
                  └── analyst:opus (Confluence 링크)

Redash URL ──> redash-analyzer:opus (쿼리 조회·SQL 분석·BQ 실행)

                    ┌──> search-slack (Slack 논의 검색)
사내 지식 검색 ────┤──> search-confluence (Confluence 문서 검색)
(analyst 내부에서  ├──> search-jira (Jira 티켓 검색)
 skill 호출)       └──> search-gsheets (Google Sheets 검색)
```

### 결과 활용 체이닝

결과 활용 작업(Google Sheets 내보내기, 시각화)은 서로 **유기적으로 연결**된다. 하나의 작업이 완료되면 자연스러운 다음 단계를 후속 옵션으로 제시한다.

**체이닝 규칙**:
- 완료된 작업 → 다음 자연스러운 단계를 우선 배치 (상세 매트릭스는 `response-format.md` 참조)
- 이미 완료한 작업은 제외하되, 변형 재실행이 의미 있으면 포함 (예: "추가 시각화")
- 결과 저장이 필요하면 어느 시점이든 `save-to-gsheets` 연계
- 어떤 데이터를 다룰지 모델 이해가 먼저 필요하면 `analyst`에서 모델 탐색 선행

## 분석 실행 전략

### EDA 스타일 실행

- **빠른 1차 결과 우선**: 메인 쿼리 1개로 핵심 결과를 빠르게 보여주고, 교차 검증·대안 소스·sample은 후속 옵션으로 제안한다.
- **수치가 의심되면 후속 옵션에 검증 쿼리 포함**: "아마 맞을 것이다"로 넘기지 않되, 첫 응답에서 모든 검증을 끝내려 하지 않는다.

### 병렬 실행 (독립 작업이 여러 개일 때)

독립적인 작업이 여러 개 있을 때는 subagent를 **한 메시지에서 동시에** 호출한다.

```
[메인 에이전트 — 단일 메시지에서 동시 호출]
  ├── Agent(analyst, model=opus): "데이터 분석"
  ├── Agent(redash-analyzer, model=opus): "Redash URL 분석"
  └── Agent(analyst, model=opus): "Google Sheets URL 분석"
```

#### 병렬 조합 예시

| 시나리오 | 위임 대상 | 모델 |
|---------|----------|------|
| 데이터 추출/분석 | analyst 1개 | opus |
| Slack 스레드 읽기 | main agent 직접 처리 | — |
| Slack 스레드 내 링크 분석 | redash-analyzer + analyst (병렬 분사) | opus |
| 분석 결과 내보내기 | analyst 1개 | sonnet |
| 시각화 | chart-builder 1개 | sonnet |
| Redash + Google Sheets 동시 분석 | redash-analyzer + analyst (병렬 분사) | opus |
