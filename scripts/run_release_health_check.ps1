param(
    [switch]$SkipMatlab,
    [switch]$FullMatlab,
    [int]$PythonTimeoutSeconds = 300,
    [int]$MatlabTimeoutSeconds = 1800
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Body
    )
    $stepStart = Get-Date
    Write-Host ("[HEALTH] {0} start {1}" -f $Name, $stepStart.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Cyan
    & $Body
    $elapsed = [int]((Get-Date) - $stepStart).TotalSeconds
    Write-Host ("[HEALTH] {0} done in {1}s" -f $Name, $elapsed) -ForegroundColor Green
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
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $lastHeartbeat = 0

    while (-not $proc.WaitForExit(1000)) {
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

    [void]$proc.WaitForExit()
    $exitCode = $proc.ExitCode
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    if (-not [string]::IsNullOrEmpty($stdout)) {
        Write-Host $stdout -NoNewline
    }
    if (-not [string]::IsNullOrEmpty($stderr)) {
        Write-Host $stderr -NoNewline -ForegroundColor Yellow
    }

    if ($exitCode -ne 0) {
        throw ("{0} failed with exit code {1}" -f $Name, $exitCode)
    }
}

Invoke-Step "Validate configs" {
    Invoke-External -Name "validate-configs" `
        -FilePath "powershell" `
        -Arguments @("-ExecutionPolicy", "Bypass", "-File", ".\scripts\validate_configs.ps1") `
        -TimeoutSeconds $PythonTimeoutSeconds
}

Invoke-Step "Python report tests" {
    Invoke-External -Name "python-tests" `
        -FilePath "python" `
        -Arguments @("-m", "unittest", "discover", "tests_py") `
        -TimeoutSeconds $PythonTimeoutSeconds
}

Invoke-Step "Python compile reporting scripts" {
    $files = Get-ChildItem -Path .\reporting -Filter *.py -File
    if ($files.Count -gt 0) {
        Invoke-External -Name "python-compile" `
            -FilePath "python" `
            -Arguments (@("-m", "py_compile") + @($files.FullName)) `
            -TimeoutSeconds $PythonTimeoutSeconds
    }
}

if (-not $SkipMatlab) {
    if ($FullMatlab) {
        Invoke-Step "MATLAB full tests" {
            Invoke-External -Name "matlab-full-tests" `
                -FilePath "matlab" `
                -Arguments @("-batch", "run_tests('all')") `
                -TimeoutSeconds $MatlabTimeoutSeconds
        }
    } else {
        Invoke-Step "MATLAB default tests" {
            Invoke-External -Name "matlab-default-tests" `
                -FilePath "matlab" `
                -Arguments @("-batch", "run_tests('default')") `
                -TimeoutSeconds $MatlabTimeoutSeconds
        }
    }
}

Write-Host "[HEALTH] Release health check passed." -ForegroundColor Green
