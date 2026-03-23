---
name: gh-auth
description: GitHub CLI(gh) 인증 설정. gh 명령 인증 실패 시 OAuth 브라우저 로그인을 자동 수행하고, 필요하면 device code 입력 페이지까지 직접 복구한다. Use when gh commands fail with authentication errors such as "not logged into any GitHub hosts", "HTTP 403", or "Resource not accessible".
---

# GitHub CLI Auth

OAuth 웹 브라우저 로그인. PAT 발급 불필요.

## 워크플로우

### Step 1. gh 설치 확인

```bash
gh --version
```

미설치 시:

| OS | 명령 |
|----|------|
| macOS | `brew install gh` |
| Ubuntu/Debian | `sudo apt install gh` |
| Windows | `winget install GitHub.cli` |

### Step 2. 인증 확인

```bash
gh auth status
```

`Logged in` -> 완료. 원래 작업 재개.

### Step 3. OAuth 로그인 실행 (2단계 Bash)

Claude Code의 Bash 환경에서는 `gh auth login --web`이 "Press Enter" 프롬프트에서 멈춘다.
또한 `wait`을 사용하면 인증이 끝난 뒤에야 출력이 보여서, 코드를 사용자에게 미리 안내할 수 없다.

**반드시 Bash를 2단계로 나눠 실행**한다:

#### Bash 호출 1: 코드 캡처 + 브라우저 열기 (즉시 반환)

```bash
TMPFILE=$(mktemp)
yes "" | gh auth login --hostname github.com --git-protocol https --web --clipboard > "$TMPFILE" 2>&1 &
sleep 3
cat "$TMPFILE"

DEVICE_URL="https://github.com/login/device"
if command -v open >/dev/null 2>&1; then
  open "$DEVICE_URL"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$DEVICE_URL"
elif command -v cmd.exe >/dev/null 2>&1; then
  cmd.exe /c start "" "$DEVICE_URL"
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command "Start-Process '$DEVICE_URL'"
else
  echo "OPEN_BROWSER_FALLBACK: $DEVICE_URL"
fi
```

- `yes ""`로 "Press Enter" 프롬프트를 자동 통과
- `> "$TMPFILE"`로 출력을 파일에 캡처
- `sleep 3` 후 `cat`으로 코드를 즉시 읽기
- OS에 맞는 브라우저 실행 명령으로 device code 페이지를 직접 열기
- **`wait` 없이 즉시 반환** — 이것이 핵심. 인증 전에 코드를 볼 수 있게 한다.

**금지**: `wait $GH_PID`를 같은 Bash 호출에 넣는 것. 인증 완료까지 블로킹되어 코드를 미리 보여줄 수 없다.

**cross-platform 보강**:
- macOS: `open`
- Linux: `xdg-open`
- Windows Git Bash: `cmd.exe /c start` 우선, 없으면 `powershell.exe Start-Process`
- 어떤 opener도 없으면 `OPEN_BROWSER_FALLBACK:` 라인을 사용자 안내에 그대로 활용

### Step 4. 코드 추출 및 사용자 안내

Step 3 Bash 호출 1의 출력에서 one-time code를 파싱하여 **사용자에게 즉시** 보여준다.

출력 예시: `! One-time code (D6D9-8E41) copied to clipboard`

Claude는 이 출력에서 코드를 추출한 뒤, 아래 형식으로 **즉시** 사용자에게 보여준다:

> **GitHub 인증 코드: `XXXX-XXXX`**
>
> 브라우저가 열렸어요! 위 코드를 붙여넣고 (클립보드에 복사되어 있어요) **Continue → Authorize** 를 눌러주세요.
> 브라우저가 안 열렸으면 https://github.com/login/device 에 직접 들어가 주세요.

**핵심 규칙**:
- 코드를 출력 로그에 묻히게 두지 않는다. 반드시 별도 메시지로 크게 보여준다.
- `--clipboard` 덕에 클립보드에도 들어가지만, 사용자가 코드를 **눈으로도 확인**할 수 있어야 한다.
- 코드 안내 메시지는 Bash 호출 1 직후, **인증 완료 대기 전에** 출력한다.

#### Bash 호출 2: 인증 완료 대기 (polling)

코드 안내를 사용자에게 보여준 뒤, 별도 Bash 호출로 인증 완료를 polling한다:

```bash
for i in $(seq 1 60); do
  if gh auth status 2>&1 | grep -q "Logged in"; then
    gh auth status 2>&1
    exit 0
  fi
  sleep 2
done
echo "Timeout"
```

- 2초 간격으로 최대 120초(60회) polling
- 인증 완료 시 `gh auth status` 출력 후 종료
- Timeout 시 Step 3부터 재시도

### Step 5. 완료 확인

Bash 호출 2에서 `Logged in`이 확인되면 원래 실패했던 작업을 자동 재시도.

## 트러블슈팅

| 증상 | 해결 |
|------|------|
| `command not found: gh` | Step 1 설치 |
| `not logged into any GitHub hosts` | Step 3부터 재실행 |
| 브라우저가 code 입력 페이지가 아닌 곳을 엶 | OS에 맞는 opener(`open` / `xdg-open` / `cmd.exe start` / `powershell.exe Start-Process`)로 `https://github.com/login/device`를 Claude가 직접 다시 열기 |
| `HTTP 403` / `Resource not accessible` | `gh auth refresh -s repo,read:org` |
| Token expired | Step 3부터 재실행 |
