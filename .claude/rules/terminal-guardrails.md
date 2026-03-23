# 터미널 명령 Guardrails

Claude Code에서 read-only 환경 진단과 BigQuery 조회는 wrapper 경로를 우선 사용한다.

## 목적

- macOS / Linux / Git Bash / Windows PowerShell에서 같은 진입점을 제공
- read-only 진단과 bq guard를 재사용하여 운영체제별 차이를 줄임
- Cursor에서 검증된 wrapper 흐름을 Claude Code에도 최대한 맞춤

## 환경 진단 wrapper

```bash
# macOS / Linux / Git Bash
./.claude/hooks/run-env-readonly.sh
```

```powershell
# Windows PowerShell
& '.claude/hooks/run-env-readonly.ps1'
```

## BigQuery wrapper

```bash
# macOS / Linux / Git Bash
./.claude/hooks/run-bq-readonly.sh bq query --use_legacy_sql=false --location=asia-northeast3 'SELECT 1'
```

```powershell
# Windows PowerShell
& '.claude/hooks/run-bq-readonly.ps1' bq query --use_legacy_sql=false --location=asia-northeast3 'SELECT 1'
```

## 규칙

- 환경 점검은 `run-env-readonly.sh` / `run-env-readonly.ps1` wrapper를 우선 사용한다.
- BigQuery 조회는 `run-bq-readonly.sh` / `run-bq-readonly.ps1` wrapper를 우선 사용한다.
- `bq query`는 `SELECT`만 허용하며 `--location=asia-northeast3` 포함이 필요하다.
- 자동 hook 런타임은 여전히 `.sh` 기반이므로 Windows에서는 `Git Bash` 호환 환경이 필요하다.
