param(
    [string]$TemplatePath = (Join-Path $PSScriptRoot '..\..\docs\ops\ssh_config.template'),
    [string]$ConfigPath = (Join-Path $env:USERPROFILE '.ssh\config')
)

$ErrorActionPreference = 'Stop'

$begin = '# BEGIN Guanbing managed hosts'
$end = '# END Guanbing managed hosts'

if (-not (Test-Path -LiteralPath $TemplatePath)) {
    throw "Template not found: $TemplatePath"
}

$template = Get-Content -LiteralPath $TemplatePath -Raw
$start = $template.IndexOf($begin)
$finish = $template.IndexOf($end)
if ($start -lt 0 -or $finish -lt $start) {
    throw "Template is missing managed block markers."
}

$block = $template.Substring($start, $finish - $start + $end.Length).Trim()
$sshDir = Split-Path -Parent $ConfigPath
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

if (Test-Path -LiteralPath $ConfigPath) {
    $existing = Get-Content -LiteralPath $ConfigPath -Raw
} else {
    $existing = ''
}

$pattern = '(?s)' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
if ($existing -match $pattern) {
    $updated = [regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block })
} elseif ([string]::IsNullOrWhiteSpace($existing)) {
    $updated = $block + [Environment]::NewLine
} else {
    $updated = $existing.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine
}

Set-Content -LiteralPath $ConfigPath -Value $updated -Encoding ASCII
Write-Host "SSH config updated: $ConfigPath"
Write-Host "Try: ssh -o BatchMode=yes gb-133 hostname"
