param(
    [int]$Port = 2222,
    [string[]]$AllowedRemoteAddress = @(
        '10.10.10.0/24',
        '192.168.100.0/24',
        '192.168.234.0/24'
    ),
    [string]$PublicKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMrTCeb+g6lGnLz/2nALiJGlfbL+gNRB6NM3pbR9AO7 eamdfan@126.com',
    [string]$OpenSshZipPath = (Join-Path $PSScriptRoot 'OpenSSH-Win64.zip'),
    [string]$OpenSshInstallRoot = (Join-Path $env:ProgramFiles 'OpenSSH'),
    [switch]$AllowPasswordLogin
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$log = Join-Path $PSScriptRoot ("setup_office_pc_openssh_2222_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Start-Transcript -LiteralPath $log -Force | Out-Null

function Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message =="
}

function Ensure-Line {
    param(
        [string[]]$Lines,
        [string]$Directive,
        [string]$Value
    )

    $matchIndex = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*Match\b') {
            $matchIndex = $i
            break
        }
    }
    if ($matchIndex -gt 0) {
        $globalLines = @($Lines[0..($matchIndex - 1)])
        $matchLines = @($Lines[$matchIndex..($Lines.Count - 1)])
    } elseif ($matchIndex -eq 0) {
        $globalLines = @()
        $matchLines = @($Lines)
    } else {
        $globalLines = @($Lines)
        $matchLines = @()
    }

    $pattern = '^\s*#?\s*' + [regex]::Escape($Directive) + '\b'
    $line = "$Directive $Value"
    $found = $false
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($item in $globalLines) {
        if ($item -match $pattern) {
            if (-not $found) {
                $out.Add($line)
                $found = $true
            }
        } else {
            $out.Add($item)
        }
    }
    if (-not $found) {
        $out.Add($line)
    }
    foreach ($item in $matchLines) {
        $out.Add($item)
    }
    return $out.ToArray()
}

function Add-Key-IfMissing {
    param([string]$Path, [string]$Key)

    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    if (Test-Path -LiteralPath $Path) {
        $content = Get-Content -LiteralPath $Path -Raw
    } else {
        $content = ''
    }
    if ($content -notmatch [regex]::Escape($Key)) {
        Add-Content -LiteralPath $Path -Value $Key -Encoding ASCII
    }
}

function Find-SshdPath {
    $cmd = Get-Command sshd.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $candidates = @(
        (Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'),
        (Join-Path $env:ProgramFiles 'OpenSSH\sshd.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'OpenSSH\sshd.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return $null
}

function Try-WindowsCapabilityInstall {
    Step "Try Windows OpenSSH capability"
    try {
        $cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop
        if (-not $cap) {
            Write-Warning "OpenSSH.Server capability was not returned by Windows."
            return $false
        }
        if ($cap.State -ne 'Installed') {
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Host
        } else {
            Write-Host "OpenSSH.Server capability already installed."
        }
        return $true
    } catch {
        Write-Warning "Windows Capability path failed: $($_.Exception.Message)"
        Write-Warning "This usually means the Windows component store/capability source is unavailable. Falling back to existing/offline OpenSSH."
        return $false
    }
}

function Try-OfflineOpenSshInstall {
    param([string]$ZipPath, [string]$InstallRoot)

    Step "Try offline OpenSSH package"
    if (-not (Test-Path -LiteralPath $ZipPath)) {
        Write-Warning "Offline package not found: $ZipPath"
        return $false
    }

    $tempRoot = Join-Path $env:TEMP ("openssh_extract_{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $tempRoot -Force

    $sshdInZip = Get-ChildItem -LiteralPath $tempRoot -Recurse -Filter sshd.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sshdInZip) {
        throw "The offline package does not contain sshd.exe: $ZipPath"
    }

    $sourceRoot = $sshdInZip.Directory.FullName
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceRoot '*') -Destination $InstallRoot -Recurse -Force

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($machinePath -notlike "*$InstallRoot*") {
        [Environment]::SetEnvironmentVariable('Path', "$machinePath;$InstallRoot", 'Machine')
    }

    $installedSshd = Join-Path $InstallRoot 'sshd.exe'
    if (-not (Test-Path -LiteralPath $installedSshd)) {
        throw "Offline OpenSSH copy finished but sshd.exe is missing: $installedSshd"
    }

    $svc = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $svc) {
        Push-Location $InstallRoot
        try {
            if (Test-Path -LiteralPath (Join-Path $InstallRoot 'install-sshd.ps1')) {
                powershell -ExecutionPolicy Bypass -File (Join-Path $InstallRoot 'install-sshd.ps1') | Out-Host
            } else {
                & $installedSshd install | Out-Host
            }
        } finally {
            Pop-Location
        }
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Offline OpenSSH installed at: $InstallRoot"
    return $true
}

function Ensure-HostKeys {
    param(
        [string]$SshdPath,
        [string]$ConfigDir
    )

    Step "Ensure server host keys"
    $sshdDir = Split-Path -Parent $SshdPath
    $sshKeygen = Join-Path $sshdDir 'ssh-keygen.exe'
    if (-not (Test-Path -LiteralPath $sshKeygen)) {
        $cmd = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
        if ($cmd) {
            $sshKeygen = $cmd.Source
        }
    }
    if (-not (Test-Path -LiteralPath $sshKeygen)) {
        throw "ssh-keygen.exe was not found next to sshd.exe or in PATH."
    }

    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $needed = @(
        (Join-Path $ConfigDir 'ssh_host_rsa_key'),
        (Join-Path $ConfigDir 'ssh_host_ecdsa_key'),
        (Join-Path $ConfigDir 'ssh_host_ed25519_key')
    )
    $missing = @($needed | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missing.Count -gt 0) {
        & $sshKeygen -A | Out-Host
    }

    $specs = @(
        @{ Path = (Join-Path $ConfigDir 'ssh_host_rsa_key'); Type = 'rsa' },
        @{ Path = (Join-Path $ConfigDir 'ssh_host_ecdsa_key'); Type = 'ecdsa' },
        @{ Path = (Join-Path $ConfigDir 'ssh_host_ed25519_key'); Type = 'ed25519' }
    )
    foreach ($spec in $specs) {
        if (-not (Test-Path -LiteralPath $spec.Path)) {
            & $sshKeygen -t $spec.Type -f $spec.Path -N '' | Out-Host
        }
    }

    $systemSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-18'
    Get-ChildItem -LiteralPath $ConfigDir -Filter 'ssh_host_*_key' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.pub' } |
        ForEach-Object {
            $acl = Get-Acl -LiteralPath $_.FullName
            $acl.SetOwner($systemSid)
            Set-Acl -LiteralPath $_.FullName -AclObject $acl
            icacls $_.FullName /inheritance:r | Out-Host
            icacls $_.FullName /grant:r '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Host
            icacls $_.FullName /remove:g "$env:COMPUTERNAME\Administrator" "$env:USERDOMAIN\Administrator" 'Authenticated Users' 'Users' 'Everyone' | Out-Host
        }

    Get-ChildItem -LiteralPath $ConfigDir -Filter 'ssh_host_*_key.pub' -ErrorAction SilentlyContinue |
        ForEach-Object {
            icacls $_.FullName /inheritance:r | Out-Host
            icacls $_.FullName /grant '*S-1-5-32-544:F' '*S-1-5-18:F' '*S-1-5-11:R' | Out-Host
        }

    Get-ChildItem -LiteralPath $ConfigDir -Filter 'ssh_host_*_key*' |
        Select-Object Name,Length,LastWriteTime |
        Format-Table -AutoSize |
        Out-Host
}

function Ensure-SshdServiceBinaryPath {
    param([string]$SshdPath)

    Step "Ensure sshd service path"
    $svcReg = 'HKLM:\SYSTEM\CurrentControlSet\Services\sshd'
    if (-not (Test-Path -LiteralPath $svcReg)) {
        Write-Warning "sshd service registry key is missing; service installation may have failed."
        return
    }

    $desired = '"' + $SshdPath + '" -D'
    $current = (Get-ItemProperty -LiteralPath $svcReg -Name ImagePath -ErrorAction SilentlyContinue).ImagePath
    Write-Host "Current ImagePath: $current"
    Write-Host "Desired ImagePath: $desired"
    if ($current -ne $desired) {
        & sc.exe config sshd binPath= $desired | Out-Host
    }
}

function Write-SshdFailureDiagnostics {
    param(
        [string]$SshdPath,
        [string]$ConfigPath,
        [int]$Port
    )

    Step "sshd start failure diagnostics"
    Get-Service sshd -ErrorAction SilentlyContinue | Format-List * | Out-Host
    Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\sshd' -ErrorAction SilentlyContinue |
        Select-Object ImagePath,ObjectName,Start,Type |
        Format-List |
        Out-Host

    Write-Host "sshd.exe -t:"
    & $SshdPath -t -f $ConfigPath 2>&1 | Out-Host

    $debugStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $debugOut = Join-Path $PSScriptRoot "sshd_debug_${debugStamp}.stdout.log"
    $debugErr = Join-Path $PSScriptRoot "sshd_debug_${debugStamp}.stderr.log"
    Write-Host "Run foreground sshd debug probe for 8 seconds:"
    Write-Host "  stdout: $debugOut"
    Write-Host "  stderr: $debugErr"
    try {
        $args = @('-ddd', '-e', '-f', $ConfigPath)
        $debugProc = Start-Process -FilePath $SshdPath `
            -ArgumentList $args `
            -RedirectStandardOutput $debugOut `
            -RedirectStandardError $debugErr `
            -WindowStyle Hidden `
            -PassThru
        Start-Sleep -Seconds 8
        if ($debugProc.HasExited) {
            Write-Host "debug sshd exited with code $($debugProc.ExitCode)"
        } else {
            Write-Host "debug sshd stayed running for 8 seconds; stopping debug probe."
            Stop-Process -Id $debugProc.Id -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $debugOut) {
            Write-Host "debug stdout tail:"
            Get-Content -LiteralPath $debugOut -Tail 80 | Out-Host
        }
        if (Test-Path -LiteralPath $debugErr) {
            Write-Host "debug stderr tail:"
            Get-Content -LiteralPath $debugErr -Tail 120 | Out-Host
        }
    } catch {
        Write-Warning "Unable to run foreground sshd debug probe: $($_.Exception.Message)"
    }

    Write-Host "TCP listeners on target port:"
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object LocalAddress,LocalPort,State,OwningProcess |
        Format-Table -AutoSize |
        Out-Host

    Write-Host "Recent OpenSSH/Operational events:"
    try {
        Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 20 -ErrorAction Stop |
            Select-Object TimeCreated,Id,LevelDisplayName,Message |
            Format-List |
            Out-Host
    } catch {
        Write-Warning "OpenSSH/Operational log is unavailable or empty: $($_.Exception.Message)"
    }

    Write-Host "Recent Service Control Manager events:"
    try {
        Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = 'Service Control Manager'
            StartTime = (Get-Date).AddMinutes(-15)
        } -MaxEvents 20 -ErrorAction Stop |
            Select-Object TimeCreated,Id,LevelDisplayName,Message |
            Format-List |
            Out-Host
    } catch {
        Write-Warning "Unable to read recent service control events: $($_.Exception.Message)"
    }
}

function Start-SshdScheduledTaskFallback {
    param(
        [string]$SshdPath,
        [string]$ConfigPath,
        [int]$Port,
        [string]$Account
    )

    Step "Fallback: run sshd from a scheduled task"
    Write-Warning "Windows sshd service failed, but foreground sshd debug probe can listen. Installing an interactive scheduled-task fallback."
    $taskName = 'Guanbing-OpenSSH-2222-OfficePC-Fallback'
    $workingDir = Split-Path -Parent $SshdPath
    $argument = '-D -f "' + $ConfigPath + '"'

    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute $SshdPath -Argument $argument -WorkingDirectory $workingDir
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $Account
    $principal = New-ScheduledTaskPrincipal -UserId $Account -LogonType Interactive -RunLevel Highest
    try {
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Days 30) `
            -MultipleInstances IgnoreNew `
            -RestartCount 3 `
            -RestartInterval (New-TimeSpan -Minutes 1)
    } catch {
        Write-Warning "Full scheduled-task settings are not supported on this Windows version: $($_.Exception.Message)"
        $settings = New-ScheduledTaskSettingsSet `
            -ExecutionTimeLimit (New-TimeSpan -Days 30) `
            -MultipleInstances IgnoreNew
    }
    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Host

        Get-Process -Name sshd -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $SshdPath } |
            Stop-Process -Force -ErrorAction SilentlyContinue

        Start-ScheduledTask -TaskName $taskName
        Start-Sleep -Seconds 5
        $tcp = Test-NetConnection -ComputerName 127.0.0.1 -Port $Port
        $tcp | Out-Host
        if (-not $tcp.TcpTestSucceeded) {
            throw "Scheduled-task fallback started, but TCP $Port is still not listening."
        }

        Write-Host ""
        Write-Host "OpenSSH is available through scheduled-task fallback."
        Write-Host "Task: $taskName"
        Write-Host "Note: this fallback runs when $Account logs on. It is enough for office-PC remote access, but not as clean as a healthy Windows service."
        return
    } catch {
        Write-Warning "Scheduled-task fallback failed: $($_.Exception.Message)"
        Write-Warning "Starting a hidden sshd.exe process as a last-resort fallback. It will stop after logout or reboot."

        Get-Process -Name sshd -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $SshdPath } |
            Stop-Process -Force -ErrorAction SilentlyContinue

        Start-Process -FilePath $SshdPath `
            -ArgumentList @('-D', '-f', $ConfigPath) `
            -WorkingDirectory $workingDir `
            -WindowStyle Hidden | Out-Null
        Start-Sleep -Seconds 5
        $tcp = Test-NetConnection -ComputerName 127.0.0.1 -Port $Port
        $tcp | Out-Host
        if (-not $tcp.TcpTestSucceeded) {
            throw "Both scheduled-task and hidden-process fallback failed; TCP $Port is still not listening."
        }

        Write-Host ""
        Write-Host "OpenSSH is available through a hidden-process fallback."
        Write-Host "Note: this is temporary and will stop after logout or reboot."
        return
    }
}

try {
    Step "Environment"
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "Run this script from an elevated Administrator PowerShell."
    }
    $computer = $env:COMPUTERNAME
    $user = "{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME
    $currentAccount = $user
    Write-Host "Computer: $computer"
    Write-Host "User: $user"
    Write-Host "Port: $Port"
    Write-Host "Allowed remote: $($AllowedRemoteAddress -join ', ')"

    Step "Install or verify OpenSSH Server"
    $sshdPath = Find-SshdPath
    if (-not $sshdPath) {
        [void](Try-WindowsCapabilityInstall)
        $sshdPath = Find-SshdPath
    }
    if (-not $sshdPath) {
        [void](Try-OfflineOpenSshInstall -ZipPath $OpenSshZipPath -InstallRoot $OpenSshInstallRoot)
        $sshdPath = Find-SshdPath
    }
    if (-not $sshdPath) {
        throw @"
sshd.exe was not found.
Fix options:
1. Put OpenSSH-Win64.zip next to this script and rerun it.
2. Or rerun with -OpenSshZipPath <path-to-OpenSSH-Win64.zip>.
3. Or repair Windows optional features and install OpenSSH.Server manually.
"@
    }
    Write-Host "sshd.exe: $sshdPath"

    Step "Configure sshd_config"
    $configDir = Join-Path $env:ProgramData 'ssh'
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $config = Join-Path $configDir 'sshd_config'
    if (-not (Test-Path -LiteralPath $config)) {
        New-Item -ItemType File -Force -Path $config | Out-Null
    }

    $backup = "$config.before_guangbing_office_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -LiteralPath $config -Destination $backup -Force
    Write-Host "Backup: $backup"

    $lines = Get-Content -LiteralPath $config
    $lines = Ensure-Line -Lines $lines -Directive 'Port' -Value ([string]$Port)
    $lines = Ensure-Line -Lines $lines -Directive 'PubkeyAuthentication' -Value 'yes'
    if ($AllowPasswordLogin) {
        $lines = Ensure-Line -Lines $lines -Directive 'PasswordAuthentication' -Value 'yes'
    } else {
        $lines = Ensure-Line -Lines $lines -Directive 'PasswordAuthentication' -Value 'no'
    }
    $lines = Ensure-Line -Lines $lines -Directive 'Subsystem' -Value 'sftp sftp-server.exe'
    Set-Content -LiteralPath $config -Value $lines -Encoding ASCII

    Step "Install public key"
    $userSshDir = Join-Path $env:USERPROFILE '.ssh'
    $userAuthorized = Join-Path $userSshDir 'authorized_keys'
    Add-Key-IfMissing -Path $userAuthorized -Key $PublicKey
    icacls $userSshDir /inheritance:r | Out-Host
    icacls $userSshDir /grant "${currentAccount}:F" '*S-1-5-18:F' | Out-Host
    icacls $userAuthorized /inheritance:r | Out-Host
    icacls $userAuthorized /grant "${currentAccount}:F" '*S-1-5-18:F' | Out-Host

    $adminAuthorized = Join-Path $configDir 'administrators_authorized_keys'
    Add-Key-IfMissing -Path $adminAuthorized -Key $PublicKey
    icacls $adminAuthorized /inheritance:r | Out-Host
    icacls $adminAuthorized /grant '*S-1-5-32-544:F' '*S-1-5-18:F' | Out-Host

    Step "Set default SSH shell"
    New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null

    Step "Configure service and firewall"
    $svc = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $svc) {
        $sshdDir = Split-Path -Parent $sshdPath
        Push-Location $sshdDir
        try {
            if (Test-Path -LiteralPath (Join-Path $sshdDir 'install-sshd.ps1')) {
                powershell -ExecutionPolicy Bypass -File (Join-Path $sshdDir 'install-sshd.ps1') | Out-Host
            } else {
                & $sshdPath install | Out-Host
            }
        } finally {
            Pop-Location
        }
        $svc = Get-Service sshd -ErrorAction SilentlyContinue
    }
    if (-not $svc) {
        throw "sshd service does not exist after installation attempt."
    }
    Set-Service -Name sshd -StartupType Automatic
    Ensure-SshdServiceBinaryPath -SshdPath $sshdPath

    $ruleName = 'Guanbing-SSH-2222-OfficePC'
    Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule `
        -Name $ruleName `
        -DisplayName 'Guanbing SSH 2222 Office PC' `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $Port `
        -RemoteAddress $AllowedRemoteAddress `
        -Profile Any | Out-Host

    Ensure-HostKeys -SshdPath $sshdPath -ConfigDir $configDir

    Step "Validate and restart sshd"
    & $sshdPath -t
    if ($LASTEXITCODE -ne 0) {
        throw "sshd_config validation failed."
    }

    Stop-Service sshd -Force -ErrorAction SilentlyContinue
    try {
        Start-Service sshd -ErrorAction Stop
    } catch {
        Write-Warning "Start-Service sshd failed: $($_.Exception.Message)"
        Write-SshdFailureDiagnostics -SshdPath $sshdPath -ConfigPath $config -Port $Port
        Start-SshdScheduledTaskFallback -SshdPath $sshdPath -ConfigPath $config -Port $Port -Account $currentAccount
    }
    Start-Sleep -Seconds 2

    Step "Status"
    Get-Service sshd | Format-Table -AutoSize | Out-Host
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object LocalAddress,LocalPort,State,OwningProcess |
        Format-Table -AutoSize | Out-Host
    Get-NetFirewallRule -Name $ruleName | Get-NetFirewallAddressFilter | Format-List | Out-Host
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '169.254*' } |
        Select-Object InterfaceAlias,IPAddress,PrefixLength,AddressState |
        Format-Table -AutoSize | Out-Host
    Test-NetConnection -ComputerName 127.0.0.1 -Port $Port | Out-Host

    Write-Host ""
    Write-Host "OpenSSH configured."
    Write-Host "Try from Codex/local:"
    Write-Host "  ssh -p $Port $env:USERNAME@<this-pc-ip> hostname"
    Write-Host "If user is an administrator and key auth fails, also try:"
    Write-Host "  ssh -p $Port Administrator@<this-pc-ip> hostname"
    Write-Host "Log: $log"
}
finally {
    Stop-Transcript | Out-Null
}
