param(
    [ValidateSet("all", "configs", "python", "compile", "report", "matlab", "gui")]
    [string]$Only = "all",
    [switch]$Fast,
    [switch]$SkipMatlab,
    [switch]$NoWord,
    [switch]$SkipReportBuild,
    [switch]$FullMatlab,
    [switch]$GuiSmoke,
    [switch]$SkipGuiSmoke,
    [int]$PythonTimeoutSeconds = 300,
    [int]$MatlabTimeoutSeconds = 1800
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$healthStart = Get-Date
$stepResults = @()
$projectPython = Join-Path $repo "reporting\.venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $projectPython -PathType Leaf)) {
    $pythonCommand = Get-Command python -ErrorAction Stop
    $projectPython = $pythonCommand.Source
}

if ($Fast) {
    $SkipMatlab = $true
    if ($PythonTimeoutSeconds -gt 180) { $PythonTimeoutSeconds = 180 }
    if ($MatlabTimeoutSeconds -gt 300) { $MatlabTimeoutSeconds = 300 }
}

if ($NoWord) {
    $env:BMS_NO_WORD = "1"
}

function Should-RunStep {
    param([string]$Group)
    return ($Only -eq "all" -or $Only -eq $Group)
}

function Invoke-Step {
    param(
        [string]$Name,
        [string]$Group,
        [scriptblock]$Body
    )
    if (-not (Should-RunStep -Group $Group)) {
        Write-Host ("[HEALTH] {0} skipped (Only={1})" -f $Name, $Only) -ForegroundColor DarkGray
        $script:stepResults += [ordered]@{
            name = $Name
            group = $Group
            status = "skipped"
            elapsed_sec = 0
            message = ""
        }
        return
    }
    $stepStart = Get-Date
    Write-Host ("[HEALTH] {0} start {1}" -f $Name, $stepStart.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Cyan
    try {
        & $Body
        $elapsed = [int]((Get-Date) - $stepStart).TotalSeconds
        $script:stepResults += [ordered]@{
            name = $Name
            group = $Group
            status = "ok"
            elapsed_sec = $elapsed
            message = ""
        }
        Write-Host ("[HEALTH] {0} done in {1}s" -f $Name, $elapsed) -ForegroundColor Green
    } catch {
        $elapsed = [int]((Get-Date) - $stepStart).TotalSeconds
        $script:stepResults += [ordered]@{
            name = $Name
            group = $Group
            status = "failed"
            elapsed_sec = $elapsed
            message = $_.Exception.Message
        }
        throw
    }
}

function ConvertTo-ArgumentLine {
    param([string[]]$Arguments)
    $quoted = @()
    foreach ($arg in $Arguments) {
        $text = [string]$arg
        if ($text -match '[\s"]') {
            $text = '"' + ($text -replace '"', '\"') + '"'
        }
        $quoted += $text
    }
    return ($quoted -join ' ')
}

function Stop-ProcessTree {
    param([int]$ProcessId)
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue
    foreach ($child in $children) {
        Stop-ProcessTree -ProcessId ([int]$child.ProcessId)
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function New-AsyncLineReaderState {
    param([System.IO.StreamReader]$Reader)
    return @{
        reader = $Reader
        task = $Reader.ReadLineAsync()
        lines = [System.Collections.Generic.List[string]]::new()
        eof = $false
    }
}

function Receive-AvailableLines {
    param([hashtable]$State)
    while (-not $State.eof -and $State.task.IsCompleted) {
        $line = $State.task.GetAwaiter().GetResult()
        if ($null -eq $line) {
            $State.eof = $true
            break
        }
        $State.lines.Add([string]$line)
        $State.task = $State.reader.ReadLineAsync()
    }
}

function Invoke-External {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments,
        [int]$TimeoutSeconds
    )

    $argLine = ConvertTo-ArgumentLine -Arguments $Arguments
    Write-Host ("[HEALTH] command: {0} {1}" -f $FilePath, $argLine) -ForegroundColor DarkGray

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $argLine
    $psi.WorkingDirectory = $repo
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    try {
        $consoleEncoding = [System.Text.Encoding]::GetEncoding(936)
        $psi.StandardOutputEncoding = $consoleEncoding
        $psi.StandardErrorEncoding = $consoleEncoding
    } catch {
    }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    [void]$proc.Start()
    $stdoutState = New-AsyncLineReaderState -Reader $proc.StandardOutput
    $stderrState = New-AsyncLineReaderState -Reader $proc.StandardError
    $lastHeartbeat = 0

    while (-not $proc.WaitForExit(100)) {
        Receive-AvailableLines -State $stdoutState
        Receive-AvailableLines -State $stderrState
        $elapsedSeconds = [int]$watch.Elapsed.TotalSeconds
        if ($elapsedSeconds -ge ($lastHeartbeat + 30)) {
            Write-Host ("[HEALTH] {0} still running, elapsed {1}s" -f $Name, $elapsedSeconds) -ForegroundColor DarkGray
            $lastHeartbeat = $elapsedSeconds
        }
        if ($TimeoutSeconds -gt 0 -and $watch.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
            Stop-ProcessTree -ProcessId $proc.Id
            throw ("{0} timed out after {1}s" -f $Name, $TimeoutSeconds)
        }
    }

    # Do not call parameterless WaitForExit() or await ReadToEndAsync here.
    # A native child can leave a MATLAB descendant holding inherited
    # stdout/stderr pipe handles after the direct parent exits. In that case
    # EOF never arrives and either operation blocks forever. Drain only for a
    # bounded grace period; the direct parent's exit code is authoritative.
    $drainDeadline = [DateTime]::UtcNow.AddMilliseconds(500)
    do {
        Receive-AvailableLines -State $stdoutState
        Receive-AvailableLines -State $stderrState
        if ($stdoutState.eof -and $stderrState.eof) { break }
        Start-Sleep -Milliseconds 10
    } while ([DateTime]::UtcNow -lt $drainDeadline)

    $exitCode = $proc.ExitCode
    foreach ($line in @($stdoutState.lines)) {
        Write-Host $line
    }
    foreach ($line in @($stderrState.lines)) {
        Write-Host $line -ForegroundColor Yellow
    }
    # Disposing a StreamReader while ReadLineAsync is still pending can itself
    # wait forever for a descendant-held pipe. Only dispose once both streams
    # reached EOF; otherwise let this short-lived PowerShell host reclaim the
    # handles when the health-check process exits.
    if ($stdoutState.eof -and $stderrState.eof) {
        $proc.StandardOutput.Dispose()
        $proc.StandardError.Dispose()
        $proc.Dispose()
    }

    if ($exitCode -ne 0) {
        throw ("{0} failed with exit code {1}" -f $Name, $exitCode)
    }
}

Invoke-Step "Validate configs" "configs" {
    Invoke-External -Name "validate-configs" `
        -FilePath "powershell" `
        -Arguments @("-ExecutionPolicy", "Bypass", "-File", ".\scripts\validate_configs.ps1") `
        -TimeoutSeconds $PythonTimeoutSeconds
}

Invoke-Step "Python report tests" "python" {
    Invoke-External -Name "python-tests" `
        -FilePath $projectPython `
        -Arguments @(".\scripts\run_python_tests.py") `
        -TimeoutSeconds $PythonTimeoutSeconds
}

Invoke-Step "Python compile reporting scripts" "compile" {
    $files = Get-ChildItem -Path .\reporting -Filter *.py -File
    if ($files.Count -gt 0) {
        Invoke-External -Name "python-compile" `
            -FilePath $projectPython `
            -Arguments (@("-m", "py_compile") + @($files.FullName)) `
            -TimeoutSeconds $PythonTimeoutSeconds
    }
}

if (-not $SkipReportBuild) {
    Invoke-Step "Report template precheck smoke" "report" {
        Invoke-External -Name "report-smoke-precheck" `
            -FilePath $projectPython `
            -Arguments @(".\reporting\smoke_report_generation.py", "--kind", "all") `
            -TimeoutSeconds $PythonTimeoutSeconds
    }
} else {
    Write-Host "[HEALTH] Report template precheck smoke skipped (-SkipReportBuild)." -ForegroundColor DarkGray
}

if (-not $SkipMatlab) {
    $runGuiSmoke = (-not $SkipGuiSmoke) -and ($GuiSmoke -or $Only -eq "all" -or $Only -eq "gui")
    if ($runGuiSmoke) {
        Invoke-Step "MATLAB GUI smoke" "gui" {
            Invoke-External -Name "matlab-gui-smoke" `
                -FilePath "matlab" `
                -Arguments @("-batch", "addpath('scripts'); gui_smoke_test") `
                -TimeoutSeconds 180
        }
    }

    if ($FullMatlab) {
        Invoke-Step "MATLAB full tests" "matlab" {
            Invoke-External -Name "matlab-full-tests" `
                -FilePath "matlab" `
                -Arguments @("-batch", "run_tests('all')") `
                -TimeoutSeconds $MatlabTimeoutSeconds
        }
    } else {
        Invoke-Step "MATLAB default tests" "matlab" {
            Invoke-External -Name "matlab-default-tests" `
                -FilePath "matlab" `
                -Arguments @("-batch", "run_tests('default')") `
                -TimeoutSeconds $MatlabTimeoutSeconds
        }
    }
}

$healthElapsed = [int]((Get-Date) - $healthStart).TotalSeconds
$outDir = Join-Path $repo "outputs\health_checks"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$payload = [ordered]@{
    checked_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    repo = $repo
    status = "ok"
    elapsed_sec = $healthElapsed
    only = $Only
    fast = [bool]$Fast
    skip_matlab = [bool]$SkipMatlab
    no_word = [bool]$NoWord
    skip_report_build = [bool]$SkipReportBuild
    python_timeout_sec = $PythonTimeoutSeconds
    matlab_timeout_sec = $MatlabTimeoutSeconds
    steps = $stepResults
}
$jsonPath = Join-Path $outDir ("release_health_check_{0}.json" -f $timestamp)
$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
Write-Host "[HEALTH] Summary JSON: $jsonPath" -ForegroundColor DarkGray
Write-Host "[HEALTH] Release health check passed." -ForegroundColor Green
