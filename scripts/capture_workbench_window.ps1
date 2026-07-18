param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$ProfileId = "guanbing",
    [int]$TabIndex = 0,
    [int]$ConfigTabIndex = 0,
    [int]$WarningTabIndex = 0,
    [int]$CleaningTabIndex = 0,
    [switch]$DemoAutoThresholdPreview,
    [switch]$DemoCacheSourceCleanup,
    [switch]$ShowTaskHistory,
    [switch]$DemoTaskHistory,
    [switch]$Offscreen,
    [string]$EvidencePath = ""
)

$ErrorActionPreference = "Stop"
$resolvedExe = (Resolve-Path -LiteralPath $ExePath).Path
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path $resolvedOutput
New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
$resolvedEvidence = ""
if (-not [string]::IsNullOrWhiteSpace($EvidencePath)) {
    $resolvedEvidence = [System.IO.Path]::GetFullPath($EvidencePath)
    New-Item -ItemType Directory -Path (Split-Path $resolvedEvidence) -Force | Out-Null
}

if (-not ("WorkbenchCaptureWin32" -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WorkbenchCaptureWin32 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO {
    public int cbSize;
    public uint flags;
    public IntPtr hwndActive;
    public IntPtr hwndFocus;
    public IntPtr hwndCapture;
    public IntPtr hwndMenuOwner;
    public IntPtr hwndMoveSize;
    public IntPtr hwndCaret;
    public RECT rcCaret;
  }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO info);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowDpiAwarenessContext(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetAwarenessFromDpiAwarenessContext(IntPtr value);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
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

$processName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedExe)
$before = @(Get-Process -Name $processName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$arguments = @(
    "--profile-id", $ProfileId,
    "--initial-tab", "$TabIndex",
    "--initial-config-tab", "$ConfigTabIndex",
    "--initial-warning-tab", "$WarningTabIndex",
    "--initial-cleaning-tab", "$CleaningTabIndex"
)
if ($DemoAutoThresholdPreview) {
    $arguments += "--demo-auto-threshold-preview"
}
if ($DemoCacheSourceCleanup) {
    $arguments += "--demo-cache-source-cleanup"
}
if ($ShowTaskHistory) {
    $arguments += "--show-task-history"
}
if ($DemoTaskHistory) {
    $arguments += "--demo-task-history"
}

if ($Offscreen) {
    # The normal release capture deliberately brings the native window to the
    # foreground so PrintWindow can validate real Windows rendering. During an
    # operator's work session that is disruptive, so provide an explicit Qt
    # offscreen audit mode. The build manifest keeps this distinct from the
    # final native screenshot release gate.
    $arguments += @(
        "--screenshot-output", $resolvedOutput,
        "--screenshot-tab", "$TabIndex"
    )
    $previousQtPlatform = [Environment]::GetEnvironmentVariable(
        "QT_QPA_PLATFORM",
        [EnvironmentVariableTarget]::Process
    )
    try {
        $env:QT_QPA_PLATFORM = "offscreen"
        $offscreenProcess = Start-Process `
            -FilePath $resolvedExe `
            -ArgumentList $arguments `
            -WindowStyle Hidden `
            -Wait `
            -PassThru
    }
    finally {
        if ($null -eq $previousQtPlatform) {
            Remove-Item Env:QT_QPA_PLATFORM -ErrorAction SilentlyContinue
        }
        else {
            $env:QT_QPA_PLATFORM = $previousQtPlatform
        }
    }
    if ($offscreenProcess.ExitCode -ne 0) {
        throw "Offscreen workbench capture failed with exit code $($offscreenProcess.ExitCode)"
    }
    if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) {
        throw "Offscreen workbench capture did not create: $resolvedOutput"
    }

    $offscreenBitmap = [System.Drawing.Bitmap]::FromFile($resolvedOutput)
    try {
        # Qt's offscreen plugin exposes a fixed 800 x 800 virtual screen on
        # Windows.  The workbench intentionally fits that screen to 800 x 720,
        # so this optional audit must use a virtual-screen-aware width gate.
        # The native release path below keeps the independent >=1000 gate.
        if ($offscreenBitmap.Width -lt 800 -or $offscreenBitmap.Height -lt 700) {
            throw "Unexpected offscreen workbench size: $($offscreenBitmap.Width) x $($offscreenBitmap.Height)"
        }
        $brightSamples = 0
        $darkSamples = 0
        $totalSamples = 0
        for ($x = 8; $x -lt $offscreenBitmap.Width; $x += 24) {
            for ($y = 8; $y -lt $offscreenBitmap.Height; $y += 24) {
                $pixel = $offscreenBitmap.GetPixel($x, $y)
                $sum = $pixel.R + $pixel.G + $pixel.B
                $totalSamples++
                if ($sum -gt 180) { $brightSamples++ }
                if ($sum -lt 30) { $darkSamples++ }
            }
        }
        # Qt's offscreen platform does not load the normal Windows CJK font
        # fallback.  Chinese glyphs are therefore rendered as dense black
        # tofu boxes and legitimate table-heavy pages can exceed the 5%
        # near-black ratio used by the native PrintWindow gate.  Keep the
        # bright-pixel requirement (which rejects blank/black captures) and
        # allow up to 20% near-black samples for offscreen audit evidence.
        # Native release screenshots retain their stricter, independent gate
        # below and offscreen evidence can never satisfy that release gate.
        $maxDarkSamples = [math]::Max(10, [math]::Floor($totalSamples * 0.20))
        if ($brightSamples -lt 300 -or $darkSamples -gt $maxDarkSamples) {
            throw "Offscreen workbench capture is incomplete (bright=$brightSamples, dark=$darkSamples/$totalSamples)"
        }
    }
    finally {
        $offscreenBitmap.Dispose()
    }
    Write-Host "Captured offscreen workbench window: $resolvedOutput"
    return
}

$started = Start-Process -FilePath $resolvedExe -ArgumentList $arguments -PassThru
$process = $null
for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 250
    $candidates = @(Get-Process -Name $processName -ErrorAction SilentlyContinue | Where-Object {
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

$bitmap = $null
$graphics = $null
try {
    $handle = $process.MainWindowHandle
    [void][WorkbenchCaptureWin32]::ShowWindow($handle, 9)
    [void][WorkbenchCaptureWin32]::BringWindowToTop($handle)
    [void][WorkbenchCaptureWin32]::SetForegroundWindow($handle)

# A native screenshot is also the release focus gate: the launched workbench
# must actually own both the foreground window and the keyboard-focus HWND.
# Merely calling SetForegroundWindow is not evidence because Windows is allowed
# to reject that request. Qt child widgets are normally alien widgets, so their
# focus HWND belongs to the same workbench process even when it is the top-level
# HWND rather than a separate native child.
    $foregroundOwned = $false
    $focusOwned = $false
    $foregroundHandle = [IntPtr]::Zero
    $focusHandle = [IntPtr]::Zero
    for ($focusAttempt = 0; $focusAttempt -lt 20; $focusAttempt++) {
        # Windows is allowed to reject SetForegroundWindow when this
        # non-interactive capture process does not currently own the foreground
        # input queue (for example, Codex/ChatGPT is the active window). Attach
        # only for the duration of the focus hand-off, then detach immediately.
        # The gate below still verifies the real foreground and focus owners;
        # this is not a substitute for that evidence.
        $foregroundBefore = [WorkbenchCaptureWin32]::GetForegroundWindow()
        [uint32]$foregroundThread = 0
        [uint32]$foregroundProcess = 0
        if ($foregroundBefore -ne [IntPtr]::Zero) {
            $foregroundThread = [WorkbenchCaptureWin32]::GetWindowThreadProcessId(
                $foregroundBefore,
                [ref]$foregroundProcess
            )
        }
        [uint32]$targetProcess = 0
        $targetThread = [WorkbenchCaptureWin32]::GetWindowThreadProcessId(
            $handle,
            [ref]$targetProcess
        )
        $currentThread = [WorkbenchCaptureWin32]::GetCurrentThreadId()
        $attachedForeground = $false
        $attachedTarget = $false
        try {
            if ($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread) {
                $attachedForeground = [WorkbenchCaptureWin32]::AttachThreadInput(
                    $currentThread,
                    $foregroundThread,
                    $true
                )
            }
            if ($targetThread -ne 0 -and $targetThread -ne $currentThread) {
                $attachedTarget = [WorkbenchCaptureWin32]::AttachThreadInput(
                    $currentThread,
                    $targetThread,
                    $true
                )
            }
            [void][WorkbenchCaptureWin32]::ShowWindow($handle, 9)
            [void][WorkbenchCaptureWin32]::BringWindowToTop($handle)
            [void][WorkbenchCaptureWin32]::SetForegroundWindow($handle)
            [void][WorkbenchCaptureWin32]::SetFocus($handle)
        }
        finally {
            if ($attachedTarget) {
                [void][WorkbenchCaptureWin32]::AttachThreadInput(
                    $currentThread,
                    $targetThread,
                    $false
                )
            }
            if ($attachedForeground) {
                [void][WorkbenchCaptureWin32]::AttachThreadInput(
                    $currentThread,
                    $foregroundThread,
                    $false
                )
            }
        }
        Start-Sleep -Milliseconds 100

        $foregroundHandle = [WorkbenchCaptureWin32]::GetForegroundWindow()
        [uint32]$foregroundPid = 0
        if ($foregroundHandle -ne [IntPtr]::Zero) {
            [void][WorkbenchCaptureWin32]::GetWindowThreadProcessId(
                $foregroundHandle,
                [ref]$foregroundPid
            )
        }
        $foregroundOwned = ($foregroundPid -eq [uint32]$process.Id)

        $guiInfo = New-Object WorkbenchCaptureWin32+GUITHREADINFO
        $guiInfo.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($guiInfo)
        if ([WorkbenchCaptureWin32]::GetGUIThreadInfo(0, [ref]$guiInfo) `
                -and $guiInfo.hwndFocus -ne [IntPtr]::Zero) {
            $focusHandle = $guiInfo.hwndFocus
            [uint32]$focusPid = 0
            [void][WorkbenchCaptureWin32]::GetWindowThreadProcessId(
                $focusHandle,
                [ref]$focusPid
            )
            $focusOwned = ($focusPid -eq [uint32]$process.Id)
        }
        if ($foregroundOwned -and $focusOwned) {
            break
        }
    }
    if (-not $foregroundOwned) {
        throw "Workbench did not become the native foreground window"
    }
    if (-not $focusOwned) {
        throw "Workbench did not receive native keyboard focus"
    }

    $windowDpi = [WorkbenchCaptureWin32]::GetDpiForWindow($handle)
    if ($windowDpi -lt 96 -or $windowDpi -gt 768) {
        throw "Unexpected native workbench DPI: $windowDpi"
    }
    $dpiContext = [WorkbenchCaptureWin32]::GetWindowDpiAwarenessContext($handle)
    $dpiAwareness = [WorkbenchCaptureWin32]::GetAwarenessFromDpiAwarenessContext($dpiContext)
    if ($dpiAwareness -ne 2) {
        throw "Workbench is not per-monitor DPI aware: awareness=$dpiAwareness"
    }

    # WM_GETICON: ICON_SMALL2, ICON_SMALL, then ICON_BIG. A nonzero handle is
    # native evidence that the Windows window/taskbar icon is installed, not
    # merely that a Qt QIcon object exists in memory.
    $windowIconHandle = [WorkbenchCaptureWin32]::SendMessage(
        $handle, 0x007F, [IntPtr]2, [IntPtr]::Zero)
    if ($windowIconHandle -eq [IntPtr]::Zero) {
        $windowIconHandle = [WorkbenchCaptureWin32]::SendMessage(
            $handle, 0x007F, [IntPtr]0, [IntPtr]::Zero)
    }
    if ($windowIconHandle -eq [IntPtr]::Zero) {
        $windowIconHandle = [WorkbenchCaptureWin32]::SendMessage(
            $handle, 0x007F, [IntPtr]1, [IntPtr]::Zero)
    }
    if ($windowIconHandle -eq [IntPtr]::Zero) {
        throw "Workbench native window icon is missing"
    }
    Start-Sleep -Milliseconds 500

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
    $captured = $false
    $brightSamples = 0
    $darkSamples = 0
    $totalSamples = 0
    $denseDarkSamples = 0
    $denseTotalSamples = 0
    for ($captureAttempt = 0; $captureAttempt -lt 15; $captureAttempt++) {
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
        $darkSamples = 0
        $totalSamples = 0
        $denseDarkSamples = 0
        $denseTotalSamples = 0
        if ($printOk) {
            for ($x = 20; $x -lt $width; $x += 80) {
                for ($y = 20; $y -lt $height; $y += 80) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    $sum = $pixel.R + $pixel.G + $pixel.B
                    $totalSamples++
                    if ($sum -gt 180) { $brightSamples++ }
                    if ($sum -lt 30) { $darkSamples++ }
                }
            }
            $maxDarkSamples = [math]::Max(3, [math]::Floor($totalSamples * 0.10))
            # A coarse 80 px grid can miss wide horizontal/vertical stale
            # PrintWindow bands. Sample the whole client frame much more
            # densely as a second gate; normal black text occupies far below
            # 3%, while a partial black repaint is rejected reliably.
            for ($x = 8; $x -lt ($width - 8); $x += 16) {
                for ($y = 8; $y -lt ($height - 8); $y += 16) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    $denseTotalSamples++
                    if (($pixel.R + $pixel.G + $pixel.B) -lt 30) { $denseDarkSamples++ }
                }
            }
            $maxDenseDarkSamples = [math]::Max(10, [math]::Floor($denseTotalSamples * 0.03))
            if ($brightSamples -ge 150 -and $darkSamples -le $maxDarkSamples `
                    -and $denseDarkSamples -le $maxDenseDarkSamples) {
                $captured = $true
                break
            }
        }
        Start-Sleep -Milliseconds 350
    }
    if (-not $captured) {
        throw "PrintWindow did not produce a complete workbench frame after 15 attempts (bright=$brightSamples, dark=$darkSamples/$totalSamples, dense_dark=$denseDarkSamples/$denseTotalSamples)"
    }
    $bitmap.Save($resolvedOutput, [System.Drawing.Imaging.ImageFormat]::Png)

    if ($resolvedEvidence) {
        $evidence = [ordered]@{
            schema_version = 1
            captured_at = (Get-Date).ToString("o")
            executable = [System.IO.Path]::GetFileName($resolvedExe)
            process_id = [int]$process.Id
            foreground_window_matches = [bool]$foregroundOwned
            focus_owned_by_process = [bool]$focusOwned
            foreground_hwnd = [long]$foregroundHandle.ToInt64()
            focus_hwnd = [long]$focusHandle.ToInt64()
            window_dpi = [int]$windowDpi
            dpi_awareness = "per_monitor"
            dpi_awareness_code = [int]$dpiAwareness
            native_window_icon = ($windowIconHandle -ne [IntPtr]::Zero)
            physical_width = [int]$width
            physical_height = [int]$height
            screenshot = [System.IO.Path]::GetFileName($resolvedOutput)
        }
        $evidence | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resolvedEvidence -Encoding UTF8
    }
} finally {
    if ($null -ne $graphics) { $graphics.Dispose() }
    if ($null -ne $bitmap) { $bitmap.Dispose() }
    try {
        if (-not $process.HasExited) {
            [void]$process.CloseMainWindow()
            if (-not $process.WaitForExit(3000)) { $process.Kill() }
        }
    } catch {
        try { $process.Kill() } catch {}
    }
}

Write-Host "Captured workbench window: $resolvedOutput"
