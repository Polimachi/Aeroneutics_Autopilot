# TASK-004: 원격 저장소(`origin main`) 푸시 및 인증 완료 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 로컬 `main` 브랜치의 모든 검증 완료 커밋을 원격 GitHub 저장소(`origin`: `https://github.com/Polimachi/Aeroneutics_Autopilot.git`)로 푸시하고 업스트림 추적 브랜치(`origin/main`)를 설정한다.

**Architecture:** 비대화형 환경에서 Git 원격 접속 및 인증 상태를 사전 진단(`ls-remote`)하고, 사용자의 인증 준비 완료 확인 후 안전한 표준 푸시(`git push -u origin main`)를 수행하며, 원격 ref 일치 검증 후 `TASK.md`와 `GEMINI.md`를 동기화한다.

**Tech Stack:** Git 2.x for Windows (`C:\Program Files\Git\cmd\git.exe`), Windows PowerShell, GitHub HTTPS/PAT/GCM.

**Spec:** [TASK.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/TASK.md) (`TASK-004`), [GEMINI.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/GEMINI.md), [AGENTS.md](file:///c:/Users/sjmik/Desktop/Create_Aeroneutics/AGENTS.md).

## Global Constraints

- **Git 실행 파일 절대 경로**: PowerShell `PATH` 미등록 환경 대응을 위해 `& "C:\Program Files\Git\cmd\git.exe"`를 사용한다.
- **Git 안전 가드레일**: 파괴적 플래그(`--force`, `--hard` 등)는 절대 사용하지 않으며, 단방향 클린 패스트포워드 푸시만 수행한다.
- **비대화형 행(Hang) 방지**: 비대화형 세션에서 GCM UI 대기로 인한 무한 대기를 방지하기 위해 타임아웃 및 `$env:GIT_TERMINAL_PROMPT="0"` 진단을 선행한다.
- **컨텍스트 상한 준수**: `GEMINI.md` 스냅샷은 80줄 상한을 엄수한다.

## Review Focus

1. **원격 저장소 미생성 (GitHub 404)**: GitHub 상에 `Polimachi/Aeroneutics_Autopilot` 저장소가 미생성된 경우 즉각 감지하고 생성 안내를 제공해야 한다.
2. **인증 자격증명 부재/만료 (403/401)**: GCM 또는 Personal Access Token(PAT) 부재 시 원인을 정확히 분류하고 브라우저 로그인 또는 자격증명 저장 방법을 안내해야 한다.
3. **비대화형 서브프로세스 행(Hang)**: 대화형 자격증명 입력창이 백그라운드에 갇히지 않도록 사전 진단 스크립트로 도달성을 검증해야 한다.
4. **원격 비패스트포워드(Non-fast-forward) 충돌**: 원격에 기존 이력이 있을 경우 `--force`를 금지하고 `fetch`로 원격 트리를 먼저 확인해야 한다.
5. **네트워크 단절 및 SSL 핸드셰이크 실패**: 네트워크 도달 실패 시 구체적 원인(프록시, SSL, DNS)을 분리 보고해야 한다.

---

### Task 1: 원격 저장소 및 인증 환경 사전 진단 (Pre-flight Diagnosis)

**Files:**
- Create: `scratch/check_remote_auth.ps1`
- Reference: `.git/config`

**Interfaces:**
- Consumes: `origin` URL (`https://github.com/Polimachi/Aeroneutics_Autopilot.git`), Git config
- Produces: 원격 저장소 접근 가능 여부 (Boolean), 인증 필요 조치 안내

- [ ] **Step 1: 사전 진단 스크립트 작성 (`scratch/check_remote_auth.ps1`)**

원격 저장소의 HTTP 응답 상태 및 Git 인증 도달성을 비대화형으로 안전하게 검사하는 스크립트를 작성한다.

```powershell
# scratch/check_remote_auth.ps1
$gitExe = "C:\Program Files\Git\cmd\git.exe"
$repoUrl = "https://github.com/Polimachi/Aeroneutics_Autopilot.git"
$apiUrl = "https://api.github.com/repos/Polimachi/Aeroneutics_Autopilot"

Write-Host "=== 1. Checking GitHub Repository via API ==="
try {
    $res = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Host "GitHub API Status: $($res.StatusCode) (Repository exists and is public)" -ForegroundColor Green
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 404) {
        Write-Host "GitHub API Status: 404 (Repository is private OR does not exist yet)" -ForegroundColor Yellow
    } else {
        Write-Host "GitHub API Status: $statusCode ($($_.Exception.Message))" -ForegroundColor Red
    }
}

Write-Host "`n=== 2. Checking Git Credential Storage ==="
$cmdkeyGit = cmdkey /list | Select-String "git:"
$cmdkeyGh = cmdkey /list | Select-String "github"
if ($cmdkeyGit -or $cmdkeyGh) {
    Write-Host "Stored Windows credentials found for Git/GitHub." -ForegroundColor Green
} else {
    Write-Host "No Windows credentials stored for Git/GitHub in cmdkey." -ForegroundColor Yellow
}

Write-Host "`n=== 3. Testing Non-interactive Git Reachability ==="
$env:GIT_TERMINAL_PROMPT = "0"
$env:GCM_INTERACTIVE = "never"
$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = $gitExe
$processInfo.Arguments = "ls-remote --heads origin"
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($processInfo)
$finished = $proc.WaitForExit(10000)

if (-not $finished) {
    $proc.Kill()
    Write-Host "Git ls-remote TIMED OUT (10s) - likely awaiting interactive GUI authentication." -ForegroundColor Red
    exit 2
} else {
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    if ($proc.ExitCode -eq 0) {
        Write-Host "Git ls-remote SUCCESSFUL! Remote is reachable and authenticated." -ForegroundColor Green
        if ($stdout.Trim()) {
            Write-Host "Remote Heads:`n$stdout"
        } else {
            Write-Host "Remote repository is empty (ready for initial push)." -ForegroundColor Cyan
        }
        exit 0
    } else {
        Write-Host "Git ls-remote FAILED with Exit Code $($proc.ExitCode):`n$stderr" -ForegroundColor Red
        exit 1
    }
}
```

- [ ] **Step 2: 진단 스크립트 실행 및 결과 판정**

Run: `powershell -ExecutionPolicy Bypass -File scratch/check_remote_auth.ps1`
Expected:
- If Exit Code 0: 원격 인증 이미 완료됨 $\to$ Task 2로 직행.
- If Exit Code 1 or 2: 원격 미생성 또는 인증 필요.

- [ ] **Step 3: 인증 미완료 시 사용자 조치 수행 확인**

만약 Exit Code != 0인 경우:
1. GitHub(`https://github.com/new`)에서 `Aeroneutics_Autopilot` 저장소가 생성되어 있는지 확인.
2. 터미널 또는 Git GUI를 통해 사용자 인증 완료 (PAT 토큰 등록 또는 1회 대화형 로그인):
   ```powershell
   # 대화형 인증 1회 트리거 (브라우저 또는 GUI 로그인 창 팝업)
   & "C:\Program Files\Git\cmd\git.exe" ls-remote origin
   ```
3. 재검증: `powershell -ExecutionPolicy Bypass -File scratch/check_remote_auth.ps1` 실행하여 Exit Code 0 확인.

- [ ] **Step 4: Commit (진단 스크립트 보존)**

```powershell
& "C:\Program Files\Git\cmd\git.exe" add scratch/check_remote_auth.ps1
& "C:\Program Files\Git\cmd\git.exe" commit -m "tool(git): add pre-flight remote authentication check script"
```

---

### Task 2: 원격 저장소 푸시 및 업스트림 추적 설정 (Push & Track)

**Files:**
- None (Git 원격 상태 갱신)

**Interfaces:**
- Consumes: Task 1의 인증 완료 상태
- Produces: 원격 `origin/main` 브랜치에 로컬 커밋 동기화, 로컬 `main`의 업스트림 설정

- [ ] **Step 1: 로컬 워킹 트리 클린 상태 사전 확인**

Run: `& "C:\Program Files\Git\cmd\git.exe" status -sb`
Expected: `## main` (워킹 트리가 깨끗하고 커밋되지 않은 파일이 없어야 함)

- [ ] **Step 2: 원격 저장소 푸시 실행**

Run: `& "C:\Program Files\Git\cmd\git.exe" push -u origin main`
Expected:
```
Enumerating objects: ...
Counting objects: 100% ...
Compressing objects: 100% ...
Writing objects: 100% ...
To https://github.com/Polimachi/Aeroneutics_Autopilot.git
 * [new branch]      main -> main
branch 'main' set up to track 'origin/main'.
```
Exit Code: 0

- [ ] **Step 3: 브랜치 추적 상태 검증**

Run: `& "C:\Program Files\Git\cmd\git.exe" branch -vv`
Expected: `* main <commit_hash> [origin/main] ...` 출력 확인.

---

### Task 3: 원격 무결성 검증 및 프로젝트 로드맵·컨텍스트 동기화 (Verification & Context Sync)

**Files:**
- Modify: `TASK.md`
- Modify: `GEMINI.md`
- Delete: `scratch/check_remote_auth.ps1` (일회성 진단 완료 후 정리)

**Interfaces:**
- Consumes: Task 2의 성공적인 푸시 결과
- Produces: `TASK-004` 완료 마킹, Phase 0 완료 및 다음 단계(`TASK-005`) 활성화

- [ ] **Step 1: 원격 ref와 로컬 HEAD 일치 검증**

Run:
```powershell
$localHead = (& "C:\Program Files\Git\cmd\git.exe" rev-parse HEAD).Trim()
$remoteHead = (& "C:\Program Files\Git\cmd\git.exe" ls-remote origin refs/heads/main).Split("`t")[0].Trim()
Write-Host "Local Head:  $localHead"
Write-Host "Remote Head: $remoteHead"
if ($localHead -eq $remoteHead) { Write-Host "VERIFICATION SUCCESS: Remote matches Local HEAD exactly!" -ForegroundColor Green } else { throw "Mismatch!" }
```
Expected: `VERIFICATION SUCCESS: Remote matches Local HEAD exactly!`

- [ ] **Step 2: `TASK.md` 갱신 (`TASK-004` 완료 처리)**

`TASK.md`에서 `TASK-004` 및 `TASK-004-1` 항목을 `[x]`로 갱신하고 완료일자 및 푸시 커밋 해시를 기록한다.

- [ ] **Step 3: `GEMINI.md` 스냅샷 갱신**

`GEMINI.md`의 `## 1. Current Phase & Active Handover`를 갱신하여 원격 푸시 완료를 명시하고 차기 착수 과제를 `TASK-005`(통합 인스톨러)로 일원화한다 (80줄 상한 준수).

- [ ] **Step 4: 일회성 스크립트 정리 및 컨텍스트 변경 커밋 & 최종 푸시**

```powershell
Remove-Item -Force scratch/check_remote_auth.ps1
& "C:\Program Files\Git\cmd\git.exe" add TASK.md GEMINI.md
& "C:\Program Files\Git\cmd\git.exe" commit -m "docs(task): complete TASK-004 remote push and advance to TASK-005"
& "C:\Program Files\Git\cmd\git.exe" push origin main
```

- [ ] **Step 5: 최종 원격 및 로컬 상태 확인**

Run: `& "C:\Program Files\Git\cmd\git.exe" status -sb`
Expected: `## main...origin/main` (Up to date, clean working tree)
