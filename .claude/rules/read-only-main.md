# 읽기 중심 / main 브랜치 규칙

이 레포에서 `main` 브랜치 작업은 기본적으로 읽기 중심으로 수행한다.

## main 브랜치 강제 전환 (hook으로 자동 실행)

`sync-main.sh` hook이 모든 도구 호출(Read, Glob, Grep, Bash) 전에 자동 실행되어:
- 현재 브랜치가 main이 아니면 **자동으로 main 전환**
- main에서 origin/main 대비 뒤처져 있으면 **자동 fast-forward pull**

별도로 `git checkout main`을 실행할 필요 없다. hook이 강제한다.

## main 브랜치 커밋 금지 (최우선 규칙)

**`main` 브랜치에 직접 커밋하지 않는다. 예외 없음.**

- 코드 변경이 필요하면 반드시 **별도 브랜치를 생성**한 뒤 커밋한다.
- 브랜치명은 `feat/`, `fix/`, `chore/` 등 변경 성격에 맞는 prefix를 사용한다.
- 커밋 후 push 및 PR 생성은 사용자가 요청한 경우에만 진행한다.
- `git commit`을 실행하기 전에 현재 브랜치가 `main`이 아닌지 반드시 확인한다.

## 기타 규칙

- 작업 시작 전 `git -C <repo_path> pull origin main`으로 최신 코드를 받는다.
- 기본 조회 브랜치는 `main`이다. 코드 변경이 필요하면 별도 브랜치를 생성한다.
- 사용자 요청 없이 임의로 파일을 수정하거나 저장소 상태를 바꾸지 않는다.
