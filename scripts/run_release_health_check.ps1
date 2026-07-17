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

function Get-LiveProcessByExactName {
    param([string]$Name)
    $live = @()
    foreach ($process in @(Get-Process -Name $Name -ErrorAction SilentlyContinue)) {
        try {
            $hasExited = [bool]$process.HasExited
        } catch {
            $hasExited = $false
        }
        if ($hasExited) {
            Write-Host ("[HEALTH] ignored exited {0} process-table entry PID={1}." -f `
                $Name, $process.Id) -ForegroundColor DarkGray
            continue
        }
        try {
            # Get-Process can retain a ghost entry after the Win32 process has
            # disappeared.  After HasExited, verify only this exact PID through
            # CIM; never scan all Win32_Process command lines.
            $record = Get-CimInstance Win32_Process `
                -Filter ("ProcessId={0}" -f [int]$process.Id) `
                -ErrorAction Stop
        } catch {
            throw ("Unable to verify {0} PID {1} through Win32_Process: {2}" -f `
                $Name, $process.Id, $_.Exception.Message)
        }
        if ($null -ne $record) {
            # Win32 can retain a terminating process-table record after the
            # executable has already lost every thread and handle.  MATLABWindow
            # crash dialogs are particularly prone to leaving this zero-resource
            # record behind.  Treat it as terminated only when CIM explicitly
            # reports both counters and both are zero; missing counters remain
            # fail-closed and are still treated as a live process.
            $hasHandleCount = $null -ne $record.HandleCount
            $hasThreadCount = $null -ne $record.ThreadCount
            if ($hasHandleCount -and $hasThreadCount `
                    -and [uint64]$record.HandleCount -eq 0 `
                    -and [uint32]$record.ThreadCount -eq 0) {
                Write-Host ("[HEALTH] ignored terminated {0} process-table entry PID={1}; exact CIM record has zero threads and handles." -f `
                    $Name, $process.Id) -ForegroundColor DarkGray
                continue
            }
            $live += $process
        } else {
            Write-Host ("[HEALTH] ignored stale {0} process-table entry PID={1}; exact CIM record is absent." -f `
                $Name, $process.Id) -ForegroundColor DarkGray
        }
    }
    return @($live)
}

function Get-MatlabSessionSnapshot {
    # Deliberately inspect exact process names only.  The release check must
    # never enumerate command lines or terminate unrelated MATLAB sessions.
    $matlab = @(Get-LiveProcessByExactName -Name "MATLAB")
    $matlabWindows = @(Get-LiveProcessByExactName -Name "MATLABWindow")
    $interactive = @($matlab | Where-Object {
        $_.MainWindowHandle -ne [IntPtr]::Zero -or -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle)
    })
    $background = @($matlab | Where-Object {
        $_.MainWindowHandle -eq [IntPtr]::Zero -and [string]::IsNullOrWhiteSpace($_.MainWindowTitle)
    })
    return [pscustomobject]@{
        interactive = $interactive
        background = $background
        matlab_windows = $matlabWindows
    }
}

function Format-MatlabProcessList {
    param([object[]]$Processes)
    $items = foreach ($process in @($Processes)) {
        $title = [string]$process.MainWindowTitle
        if ([string]::IsNullOrWhiteSpace($title)) { $title = "<no-window-title>" }
        "PID={0},Session={1},Title={2}" -f $process.Id, $process.SessionId, $title
    }
    return ($items -join "; ")
}

function Assert-MatlabGuiSessionIsClean {
    $snapshot = Get-MatlabSessionSnapshot
    if ($snapshot.interactive.Count -gt 0) {
        $details = Format-MatlabProcessList -Processes $snapshot.interactive
        throw (("MATLAB GUI smoke was not started because an interactive MATLAB session is open ({0}). " +
            "Close it and rerun, or use -SkipGuiSmoke. No MATLAB process or MathWorks service was restarted or terminated.") -f $details)
    }
    $backgroundProcesses = @($snapshot.background) + @($snapshot.matlab_windows)
    if ($backgroundProcesses.Count -gt 0) {
        $details = Format-MatlabProcessList -Processes $backgroundProcesses
        throw (("MATLAB GUI smoke was not started because pre-existing headless MATLAB/MATLABWindow processes were found ({0}). " +
            "They may be an active or stale automated run; inspect them explicitly before retrying. No process was terminated.") -f $details)
    }
}

function New-IsolatedMatlabPrefDir {
    param([string]$Role)
    $base = Join-Path ([System.IO.Path]::GetTempPath()) "GuanbingReleaseHealth"
    $leaf = "matlab_pref_{0}_{1}" -f $Role, [guid]::NewGuid().ToString("N")
    $path = Join-Path $base $leaf
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
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
        [int]$TimeoutSeconds,
        [hashtable]$EnvironmentVariables = @{}
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
    $ownedProcessId = $null
    $cleanupAttempted = $false
    try {
        # Codex and some CI hosts can provide both Path and PATH in the raw
        # environment block.  Windows PowerShell 5.1 then fails while
        # materializing ProcessStartInfo.EnvironmentVariables as a
        # case-insensitive dictionary.  Scope the two release-health values on
        # this PowerShell process only for CreateProcess, then restore them
        # immediately after the child has inherited its environment.
        $environmentSnapshot = @()
        foreach ($entry in $EnvironmentVariables.GetEnumerator()) {
            $key = [string]$entry.Key
            $environmentSnapshot += [pscustomobject]@{
                Key = $key
                Value = [Environment]::GetEnvironmentVariable($key, "Process")
            }
            [Environment]::SetEnvironmentVariable($key, [string]$entry.Value, "Process")
        }
        try {
            [void]$proc.Start()
        } finally {
            foreach ($snapshot in $environmentSnapshot) {
                [Environment]::SetEnvironmentVariable(
                    [string]$snapshot.Key,
                    $snapshot.Value,
                    "Process")
            }
        }
        $ownedProcessId = [int]$proc.Id
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
                Stop-ProcessTree -ProcessId $ownedProcessId
                $cleanupAttempted = $true
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
            Stop-ProcessTree -ProcessId $ownedProcessId
            $cleanupAttempted = $true
            throw ("{0} failed with exit code {1}" -f $Name, $exitCode)
        }
    } catch {
        if ($null -ne $ownedProcessId -and -not $cleanupAttempted) {
            # Clean up only the process tree rooted at the exact PID started by
            # this invocation.  Never use a name-based MATLAB kill here.
            Stop-ProcessTree -ProcessId $ownedProcessId
        }
        throw
    }
}

function Invoke-IsolatedExternal {
    param(
        [string]$Name,
        [string]$Role,
        [string]$FilePath,
        [string[]]$Arguments,
        [int]$TimeoutSeconds,
        [bool]$NonGui
    )
    $prefDir = New-IsolatedMatlabPrefDir -Role $Role
    $completed = $false
    Write-Host ("[HEALTH] isolated MATLAB_PREFDIR: {0}" -f $prefDir) -ForegroundColor DarkGray
    try {
        Invoke-External -Name $Name `
            -FilePath $FilePath `
            -Arguments $Arguments `
            -TimeoutSeconds $TimeoutSeconds `
            -EnvironmentVariables @{
                MATLAB_PREFDIR = $prefDir
                BMS_RELEASE_HEALTH_NON_GUI = $(if ($NonGui) { "1" } else { "0" })
            }
        $completed = $true
    } finally {
        if ($completed) {
            Remove-Item -LiteralPath $prefDir -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Warning ("Isolated MATLAB preferences were preserved for diagnosis: {0}" -f $prefDir)
        }
    }
}

function Invoke-IsolatedMatlab {
    param(
        [string]$Name,
        [string]$Role,
        [string]$BatchCommand,
        [int]$TimeoutSeconds,
        [bool]$NonGui
    )
    Invoke-IsolatedExternal -Name $Name `
        -Role $Role `
        -FilePath "matlab" `
        -Arguments @("-batch", $BatchCommand) `
        -TimeoutSeconds $TimeoutSeconds `
        -NonGui $NonGui
}

Invoke-Step "Validate configs" "configs" {
    # validate_configs.ps1 launches MATLAB as a child process.  Give that
    # child the same isolated preference boundary as every other release
    # health MATLAB invocation; otherwise a damaged user preference or
    # Service Host state can hang the very first gate before the isolated
    # full-suite process is reached.
    Invoke-IsolatedExternal -Name "validate-configs" `
        -Role "config_lint_nongui" `
        -FilePath "powershell" `
        -Arguments @("-ExecutionPolicy", "Bypass", "-File", ".\scripts\validate_configs.ps1") `
        -TimeoutSeconds $PythonTimeoutSeconds `
        -NonGui $true
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
        $pyCache = Join-Path ([System.IO.Path]::GetTempPath()) `
            ("GuanbingReleaseHealth\pycache_{0}" -f [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $pyCache -Force | Out-Null
        try {
            Invoke-External -Name "python-compile" `
                -FilePath $projectPython `
                -Arguments (@("-m", "py_compile") + @($files.FullName)) `
                -TimeoutSeconds $PythonTimeoutSeconds `
                -EnvironmentVariables @{ PYTHONPYCACHEPREFIX = $pyCache }
        } finally {
            Remove-Item -LiteralPath $pyCache -Recurse -Force -ErrorAction SilentlyContinue
        }
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
        Invoke-Step "MATLAB GUI session preflight" "gui" {
            Assert-MatlabGuiSessionIsClean
        }
    }

    if ($FullMatlab) {
        Invoke-Step "MATLAB full core tests" "matlab" {
            Invoke-IsolatedMatlab -Name "matlab-full-core-tests" `
                -Role "full_core_nongui" `
                -BatchCommand "run_tests('all-core')" `
                -TimeoutSeconds $MatlabTimeoutSeconds `
                -NonGui $true
        }
        Invoke-Step "MATLAB cleanup contract tests" "matlab" {
            Invoke-IsolatedMatlab -Name "matlab-cleanup-contract-tests" `
                -Role "cleanup_contracts_nongui" `
                -BatchCommand "run_tests('cleanup-contracts')" `
                -TimeoutSeconds $MatlabTimeoutSeconds `
                -NonGui $true
        }
    } else {
        Invoke-Step "MATLAB default tests" "matlab" {
            Invoke-IsolatedMatlab -Name "matlab-default-tests" `
                -Role "default_nongui" `
                -BatchCommand "run_tests('default')" `
                -TimeoutSeconds $MatlabTimeoutSeconds `
                -NonGui $true
        }
    }

    if ($runGuiSmoke) {
        Invoke-Step "MATLAB GUI smoke" "gui" {
            # Recheck after the non-GUI process.  A leaked automated process is
            # evidence of a failed isolation boundary and must not be killed or
            # hidden by restarting MathWorksServiceHost.
            Assert-MatlabGuiSessionIsClean
            Invoke-IsolatedMatlab -Name "matlab-gui-smoke" `
                -Role "gui_smoke" `
                -BatchCommand "run_tests({'tests/test_main_gui_smoke.m'}); addpath('scripts'); gui_smoke_test" `
                -TimeoutSeconds 180 `
                -NonGui $false
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
