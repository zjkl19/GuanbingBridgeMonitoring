param(
    [string]$HostAlias = 'gb-133',
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

$remoteScript = @'
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"
$InformationPreference = "SilentlyContinue"
Write-Output "== Host =="
hostname
Write-Output ""

Write-Output "== Disk =="
Get-PSDrive -PSProvider FileSystem |
    Select-Object Name,
        @{Name="FreeGB";Expression={[math]::Round($_.Free/1GB,1)}},
        @{Name="UsedGB";Expression={[math]::Round($_.Used/1GB,1)}} |
    Format-Table -AutoSize

Write-Output "== Guanbing tasks =="
Get-ScheduledTask |
    Where-Object { $_.TaskName -like "Guanbing_*" } |
    ForEach-Object {
        $info = $_ | Get-ScheduledTaskInfo
        [pscustomobject]@{
            Task = $_.TaskName
            State = $_.State
            LastResult = $info.LastTaskResult
            LastRun = $info.LastRunTime
            NextRun = $info.NextRunTime
        }
    } |
    Sort-Object Task |
    Format-Table -AutoSize

Write-Output "== Heavy processes =="
Get-Process MATLAB,matlab,robocopy,rar,WinRAR -ErrorAction SilentlyContinue |
    Select-Object Id,ProcessName,
        @{Name="CPU";Expression={[math]::Round($_.CPU,1)}},
        @{Name="MemMB";Expression={[math]::Round($_.WorkingSet64/1MB,1)}},
        StartTime |
    Format-Table -AutoSize
'@

$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remoteScript))
$args = @(
    '-o', 'BatchMode=yes',
    '-o', "ConnectTimeout=$TimeoutSeconds",
    $HostAlias,
    'powershell', '-NoProfile', '-EncodedCommand', $encoded
)

& ssh @args
