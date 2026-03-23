# mrt-dp-dbt-airflow

데이터팀의 dbt + Airflow 모노레포. Claude Code 에이전트가 데이터 분석·추출·시각화·사내 지식 검색을 수행합니다.

## 핵심 원칙

- **읽기 중심**: main 브랜치는 읽기 중심. 파괴적 bq 명령은 hook에서 차단.
- **정확성 >> 속도**: 데이터 분석 시 교차 검증 필수. 수치를 추측하지 않고 쿼리로 확인.
- **안전장치**: BQ는 SELECT만 허용, DML/DDL 차단, 100GB 스캔 제한, DW_BIZ_LOG 7일 제한.
- **친절한 UX**: 비개발자 대상. 두괄식 결론, 후속 옵션 루프, 요건 구체화 플로우.
- **모델+YAML 함께 읽기**: dbt 모델 분석 시 SQL과 YAML 양쪽 모두 확인.

## 시스템 구조

| 디렉토리 | 역할 |
|----------|------|
| `.claude/rules/` | 응답 형식, BQ 규칙, 라우팅, 인사, 읽기 전용 정책, 터미널 guardrails |
| `.claude/hooks/` | BQ wrapper/guard, env wrapper, main 자동 동기화 |
| `.claude/agents/` | analyst, chart-builder, setup-helper, redash-analyzer |
| `.claude/skills/` | bq-query, analyze-model, csv-summarizer, redash-query, save-to-gsheets, slack-share, setup, gcloud-auth, gh-auth, gsheets-auth, search-all, search-slack, search-confluence, search-jira, search-gsheets |
| `.claude/credentials/` | Redash API Key (`redash.env`) 등 로컬 인증 정보 |
| `.claude/evals/` | Hook 동작 검증 테스트 |

## 개인 메모리

Claude Code 빌트인 `autoMemoryEnabled` 기능을 사용한다. 별도 `.claude/MEMORY.md` 파일은 사용하지 않는다.

- **"기억해줘"**: 빌트인 auto memory에 저장한다.
- 자동 수집 대상(URL, 지표 패턴, 피드백 등)은 `.claude/rules/personal-memory.md` 참조.
