param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$ProfileId = "guanbing",
    [int]$TabIndex = 0,
    [int]$ConfigTabIndex = 0
)

$ErrorActionPreference = "Stop"
$resolvedExe = (Resolve-Path -LiteralPath $ExePath).Path
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path $resolvedOutput
New-Item -ItemType Directory -Path $outputParent -Force | Out-Null

if (-not ("WorkbenchCaptureWin32" -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WorkbenchCaptureWin32 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
  [DllImport("user32.dll")] public static extern bool UpdateWindow(IntPtr hWnd);
}
'@
}
Add-Type -AssemblyName System.Drawing
# PowerShell is otherwise DPI-virtualized on a 125% desktop and allocates a
# bitmap smaller than the pixels PrintWindow renders. Per-monitor awareness
# makes GetWindowRect return the real physical size of the Qt window.
[void][WorkbenchCaptureWin32]::SetProcessDpiAwarenessContext([IntPtr](-4))

$before = @(Get-Process -Name "BridgeMonitoringWorkbench" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$started = Start-Process -FilePath $resolvedExe -ArgumentList @(
    "--profile-id", $ProfileId,
    "--initial-tab", "$TabIndex",
    "--initial-config-tab", "$ConfigTabIndex"
) -PassThru
$process = $null
for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 250
    $candidates = @(Get-Process -Name "BridgeMonitoringWorkbench" -ErrorAction SilentlyContinue | Where-Object {
        $before -notcontains $_.Id -and $_.MainWindowHandle -ne 0
    })
    if ($candidates.Count -gt 0) {
        $process = $candidates[0]
        break
    }
    $started.Refresh()
    if ($started.MainWindowHandle -ne 0) {
        $process = $started
        break
    }
}
if ($null -eq $process) {
    try { $started.Kill() } catch {}
    throw "Workbench window was not found for capture"
}

$handle = $process.MainWindowHandle
[void][WorkbenchCaptureWin32]::ShowWindow($handle, 9)
[void][WorkbenchCaptureWin32]::BringWindowToTop($handle)
[void][WorkbenchCaptureWin32]::SetForegroundWindow($handle)
Start-Sleep -Milliseconds 750

$rect = New-Object WorkbenchCaptureWin32+RECT
if (-not [WorkbenchCaptureWin32]::GetWindowRect($handle, [ref]$rect)) {
    throw "GetWindowRect failed"
}
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -lt 1000 -or $height -lt 700) {
    throw "Unexpected workbench size: $width x $height"
}
$bitmap = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
    $captured = $false
    $brightSamples = 0
    for ($captureAttempt = 0; $captureAttempt -lt 10; $captureAttempt++) {
        [void][WorkbenchCaptureWin32]::UpdateWindow($handle)
        $graphics.Clear([System.Drawing.Color]::Black)
        $hdc = $graphics.GetHdc()
        try {
            # PW_RENDERFULLCONTENT renders the target window itself, even when
            # it is partly covered by another application. This prevents
            # unrelated screen pixels from leaking into release screenshots.
            $printOk = [WorkbenchCaptureWin32]::PrintWindow($handle, $hdc, 2)
            if (-not $printOk) {
                $printOk = [WorkbenchCaptureWin32]::PrintWindow($handle, $hdc, 0)
            }
        } finally {
            $graphics.ReleaseHdc($hdc)
        }
        $brightSamples = 0
        if ($printOk) {
            for ($x = 20; $x -lt $width; $x += 80) {
                for ($y = 20; $y -lt $height; $y += 80) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    if (($pixel.R + $pixel.G + $pixel.B) -gt 180) { $brightSamples++ }
                }
            }
            if ($brightSamples -ge 150) {
                $captured = $true
                break
            }
        }
        Start-Sleep -Milliseconds 350
    }
    if (-not $captured) {
        throw "PrintWindow did not produce a complete bright workbench frame after 10 attempts (bright samples: $brightSamples)"
    }
    $bitmap.Save($resolvedOutput, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    [void]$process.CloseMainWindow()
    if (-not $process.WaitForExit(3000)) { $process.Kill() }
}

Write-Host "Captured workbench window: $resolvedOutput"
