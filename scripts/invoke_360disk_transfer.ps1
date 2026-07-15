[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('upload', 'download')]
    [string]$Action,

    [string]$LocalPath,
    [string]$RemoteDirectory,
    [string]$Nid,
    [string]$DownloadDirectory,

    [ValidateSet('auto', 'direct', 'proxy')]
    [string]$NetworkMode = 'auto',

    [ValidateRange(1, 10)]
    [int]$Attempts = 3,

    [ValidateRange(1000, 7200000)]
    [int]$TimeoutMs = 3600000,

    [ValidateRange(0, 300)]
    [int]$RetryDelaySeconds = 5,

    [string]$NodePath,
    [string]$CliPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FirstExistingFile {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Resolve-360DiskRuntime {
    param([string]$RequestedNode, [string]$RequestedCli)

    $nodeCandidates = @(
        $RequestedNode,
        $env:GUANBING_360DISK_NODE,
        'F:\Guanbing_v1.8.1-rc1\tools\360disk-portable\node-v24.14.0-win-x64\node.exe',
        (Join-Path $HOME '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe')
    )
    $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($nodeCommand) {
        $nodeCandidates += $nodeCommand.Source
    }

    $cliCandidates = @(
        $RequestedCli,
        $env:GUANBING_360DISK_CLI,
        'F:\Guanbing_v1.8.1-rc1\tools\360disk-portable\app\node_modules\@aicloud360\360-ai-cloud-disk-cli\build\cli.js'
    )
    $tempPortable = Get-ChildItem -LiteralPath $env:TEMP -Directory `
        -Filter 'guanbing_360portable_*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($tempPortable) {
        $cliCandidates += (Join-Path $tempPortable.FullName 'node_modules\@aicloud360\360-ai-cloud-disk-cli\build\cli.js')
    }

    $node = Resolve-FirstExistingFile -Candidates $nodeCandidates
    $cli = Resolve-FirstExistingFile -Candidates $cliCandidates
    if (-not $node -or -not $cli) {
        throw ('360 CLI runtime not found. Specify -NodePath/-CliPath or ' +
            'GUANBING_360DISK_NODE/GUANBING_360DISK_CLI.')
    }
    return [pscustomobject]@{ Node = $node; Cli = $cli }
}

function Get-ModeSequence {
    param([string]$RequestedMode, [string]$RequestedAction)

    if ($RequestedMode -ne 'auto') {
        return @($RequestedMode)
    }
    if ($RequestedAction -eq 'download' -and
        (-not [string]::IsNullOrWhiteSpace($env:HTTPS_PROXY) -or
         -not [string]::IsNullOrWhiteSpace($env:HTTP_PROXY))) {
        # This host's direct 360 download route is intermittent. Try the
        # already configured local proxy first, then fall back to direct.
        return @('proxy', 'direct')
    }
    return @('direct')
}

function Set-TransferNetworkMode {
    param([string]$Mode)

    if ($Mode -eq 'proxy') {
        if ([string]::IsNullOrWhiteSpace($env:HTTPS_PROXY) -and
            [string]::IsNullOrWhiteSpace($env:HTTP_PROXY)) {
            throw 'Proxy mode requires HTTP_PROXY or HTTPS_PROXY.'
        }
        $env:NODE_USE_ENV_PROXY = '1'
        return
    }

    Remove-Item Env:NODE_USE_ENV_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:HTTP_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:ALL_PROXY -ErrorAction SilentlyContinue
    $existing = [string]$env:NO_PROXY
    $required = '.yunpan.360.cn,.eyun.360.cn'
    $env:NO_PROXY = if ([string]::IsNullOrWhiteSpace($existing)) {
        $required
    } else {
        "$existing,$required"
    }
}

function Restore-EnvironmentValue {
    param([string]$Name, [AllowNull()][string]$Value)

    if ($null -eq $Value) {
        Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
    } else {
        Set-Item "Env:$Name" $Value
    }
}

$apiKey = [string]$env:API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw 'API_KEY is not set in the current process environment.'
}

if ($Action -eq 'upload') {
    if ([string]::IsNullOrWhiteSpace($LocalPath) -or
        -not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
        throw 'upload requires a valid -LocalPath file.'
    }
    if ([string]::IsNullOrWhiteSpace($RemoteDirectory)) {
        throw 'upload requires -RemoteDirectory.'
    }
} else {
    if ([string]::IsNullOrWhiteSpace($Nid)) {
        throw 'download requires -Nid.'
    }
    if ([string]::IsNullOrWhiteSpace($DownloadDirectory)) {
        throw 'download requires -DownloadDirectory.'
    }
    New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null
}

$runtime = Resolve-360DiskRuntime -RequestedNode $NodePath -RequestedCli $CliPath
$version = (& $runtime.Node $runtime.Cli --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw '360 CLI failed to start.'
}

$savedEnvironment = @{}
foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'NODE_USE_ENV_PROXY')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$modes = @(Get-ModeSequence -RequestedMode $NetworkMode -RequestedAction $Action)
$success = $false
$exitCode = 1
$usedMode = ''
$elapsed = [TimeSpan]::Zero
$attemptUsed = 0
$failureReason = 'CLI command failed'

try {
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $attemptUsed = $attempt
        $usedMode = $modes[($attempt - 1) % $modes.Count]
        Set-TransferNetworkMode -Mode $usedMode

        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        if ($Action -eq 'upload') {
            $cliArguments = @(
                '--quiet', '--format', 'json', '--timeout', $TimeoutMs,
                '--retries', '2', 'file', 'upload',
                (Resolve-Path -LiteralPath $LocalPath).Path,
                '--dest', $RemoteDirectory
            )
        } else {
            $cliArguments = @(
                '--quiet', '--format', 'json', '--timeout', $TimeoutMs,
                '--retries', '2', 'file', 'download', $Nid,
                '--dir', (Resolve-Path -LiteralPath $DownloadDirectory).Path
            )
        }
        $raw = & $runtime.Node $runtime.Cli @cliArguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $stopwatch.Stop()
        $elapsed = $stopwatch.Elapsed
        if ($exitCode -eq 0) {
            $success = $true
            break
        }

        # Never emit raw CLI output: version 0.8.37 can include credentials
        # and access tokens in debug lines even when --quiet is present.
        $failureReason = if ($raw -match '"error"\s*:\s*"([^"]+)"') {
            [string]$Matches[1]
        } else {
            "CLI exit code $exitCode"
        }
        $failureReason = ($failureReason -replace 'yunpan_[A-Za-z0-9_-]+', '<redacted>') `
            -replace '(?i)Access-Token[^\s,}]*', 'Access-Token:<redacted>'
        if ($attempt -lt $Attempts -and $RetryDelaySeconds -gt 0) {
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        Restore-EnvironmentValue -Name $name -Value $savedEnvironment[$name]
    }
    $apiKey = $null
}

$artifact = $null
if ($success -and $Action -eq 'upload') {
    $artifact = Get-Item -LiteralPath $LocalPath
} elseif ($success) {
    $artifact = Get-ChildItem -LiteralPath $DownloadDirectory -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $artifact) {
        $success = $false
        $failureReason = 'CLI returned success but no downloaded file was found.'
        $exitCode = 1
    }
}

$bytes = if ($artifact) { [int64]$artifact.Length } else { [int64]0 }
$seconds = [math]::Max($elapsed.TotalSeconds, 0.001)
$result = [ordered]@{
    success = $success
    action = $Action
    network_mode = $usedMode
    attempts = $attemptUsed
    cli_version = $version
    exit_code = $exitCode
    path = if ($artifact) { $artifact.FullName } else { '' }
    bytes = $bytes
    seconds = [math]::Round($elapsed.TotalSeconds, 3)
    mib_per_second = if ($success) { [math]::Round(($bytes / 1MB) / $seconds, 3) } else { $null }
    mbit_per_second = if ($success) { [math]::Round(($bytes * 8 / 1e6) / $seconds, 3) } else { $null }
    sha256 = if ($artifact) { (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash } else { '' }
    error = if ($success) { '' } else { $failureReason }
}

$result | ConvertTo-Json -Compress
if (-not $success) {
    exit 2
}
