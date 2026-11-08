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
