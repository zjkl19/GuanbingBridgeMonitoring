param(
    [string]$PythonExe = "reporting\.venv\Scripts\python.exe",
    [switch]$SkipAnalysisRunner
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repo

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [Parameter(Mandatory = $true)]
        [string]$StepName
    )

    & $FilePath @ArgumentList | Out-Host
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$StepName failed with exit code $exitCode"
    }
}

if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw "Python executable not found: $PythonExe"
}

Invoke-NativeChecked `
    -FilePath $PythonExe `
    -ArgumentList @("-m", "pip", "install", "pyinstaller", "-r", "reporting\requirements.txt") `
    -StepName "Workbench Python dependency installation"
Invoke-NativeChecked `
    -FilePath $PythonExe `
    -ArgumentList @("-c", "import PySide6, PyInstaller, docx, openpyxl, PIL, lxml, matplotlib, numpy, pypdf, win32com.client") `
    -StepName "Workbench Python dependency import check"

$distParent = Join-Path $repo "dist"
$buildRoot = Join-Path $repo "build\workbench"
# Keep this PowerShell 5.1 script ASCII-safe while constructing the canonical
# Chinese display name from its Unicode code points.
$bundleName = -join (26725, 26753, 20581, 24247, 30417, 27979, 24037, 20316, 21488 | ForEach-Object { [char]$_ })
$operatorGuideName = (-join (20351, 29992, 35828, 26126 | ForEach-Object { [char]$_ })) + ".md"
$generatedRoot = Join-Path $distParent $bundleName
$distRoot = Join-Path $distParent "BridgeMonitoringWorkbench"
if (Test-Path -LiteralPath $generatedRoot) {
    Remove-Item -LiteralPath $generatedRoot -Recurse -Force
}
Invoke-NativeChecked `
    -FilePath $PythonExe `
    -ArgumentList @(
        "-m", "PyInstaller",
        "--noconfirm",
        "--clean",
        "--noconsole",
        "--paths", "reporting",
        "--hidden-import", "report_job",
        "--hidden-import", "report_job_cli",
        "--icon", "workbench\assets\app_icon.ico",
        "--name", $bundleName,
        "--distpath", $distParent,
        "--workpath", $buildRoot,
        "start_workbench.py"
    ) `
    -StepName "PyInstaller workbench build"

if (-not (Test-Path -LiteralPath $generatedRoot -PathType Container)) {
    throw "PyInstaller output directory was not produced: $generatedRoot"
}
if (Test-Path -LiteralPath $distRoot) {
    Remove-Item -LiteralPath $distRoot -Recurse -Force
}
Move-Item -LiteralPath $generatedRoot -Destination $distRoot
$exePath = Join-Path $distRoot "${bundleName}.exe"
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Workbench executable was not produced: $exePath"
}

Copy-Item -LiteralPath (Join-Path $repo "VERSION") -Destination (Join-Path $distRoot "VERSION") -Force
Copy-Item -LiteralPath (Join-Path $repo "docs\OPERATOR_GUIDE.md") -Destination (Join-Path $distRoot $operatorGuideName) -Force

$copyAssets = @'
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

repo = Path.cwd()
if str(repo) not in sys.path:
    sys.path.insert(0, str(repo))

from workbench.config_layers import load_layered_config

dest = repo / "dist" / "BridgeMonitoringWorkbench"
profile_path = repo / "config" / "bridge_profiles.json"
payload = json.loads(profile_path.read_text(encoding="utf-8-sig"))
relative_files = {
    Path("config") / "bridge_profiles.json",
    Path("config") / "path_profiles.json",
    Path("config") / "workbench_update.json",
}
for profile in payload.get("profiles", []):
    for key in ("default_config", "report_template"):
        value = str(profile.get(key) or "").strip()
        if value:
            candidate = Path(value)
            if candidate.is_absolute():
                raise RuntimeError(f"Packaged profile asset must be project-relative: {candidate}")
            relative_files.add(candidate)
            if key == "default_config":
                _config, dependencies = load_layered_config(repo / candidate)
                for dependency in dependencies:
                    try:
                        relative_files.add(dependency.resolve().relative_to(repo.resolve()))
                    except ValueError as exc:
                        raise RuntimeError(
                            f"Packaged config dependency must stay inside the project: {dependency}"
                        ) from exc

for relative in sorted(relative_files, key=lambda item: str(item).casefold()):
    source = repo / relative
    if not source.is_file():
        continue
    target = dest / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)

icon_source = repo / "workbench" / "assets"
icon_target = dest / "workbench" / "assets"
if icon_target.exists():
    shutil.rmtree(icon_target)
shutil.copytree(icon_source, icon_target)

report_asset_source = repo / "reports" / "assets"
report_asset_target = dest / "reports" / "assets"
if report_asset_source.exists():
    if report_asset_target.exists():
        shutil.rmtree(report_asset_target)
    shutil.copytree(report_asset_source, report_asset_target)
'@
$copyScript = Join-Path $buildRoot "copy_workbench_assets.py"
Set-Content -LiteralPath $copyScript -Value $copyAssets -Encoding UTF8
Invoke-NativeChecked `
    -FilePath $PythonExe `
    -ArgumentList @($copyScript) `
    -StepName "Workbench asset copy"

if (-not $SkipAnalysisRunner) {
    $runnerSource = Join-Path $repo "bin\BridgeAnalysisRunner"
    $runnerExe = Join-Path $runnerSource "BridgeAnalysisRunner.exe"
    $runnerInputs = @(
        Get-Item -LiteralPath (Join-Path $repo "run_request_cli.m")
        Get-ChildItem -LiteralPath (Join-Path $repo "+bms") -Recurse -File -Filter "*.m"
        Get-ChildItem -LiteralPath (Join-Path $repo "analysis") -Recurse -File -Filter "*.m"
        Get-ChildItem -LiteralPath (Join-Path $repo "pipeline") -Recurse -File -Filter "*.m"
        Get-ChildItem -LiteralPath (Join-Path $repo "scripts") -Recurse -File -Filter "*.m"
        Get-ChildItem -LiteralPath (Join-Path $repo "ui") -Recurse -File -Filter "*.m"
    )
    $latestRunnerInput = ($runnerInputs | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
    if (-not (Test-Path -LiteralPath $runnerExe -PathType Leaf) `
            -or (Get-Item -LiteralPath $runnerExe).LastWriteTimeUtc -lt $latestRunnerInput) {
        Write-Host "Analysis runner is stale; rebuilding before workbench packaging."
        & (Join-Path $repo "scripts\build_analysis_runner.ps1")
    }
    if (-not (Test-Path -LiteralPath (Join-Path $runnerSource "BridgeAnalysisRunner.exe") -PathType Leaf)) {
        throw "Analysis runner is missing: $runnerSource"
    }
    $previewSmokeRoot = Join-Path $buildRoot "auto_threshold_preview_smoke"
    Invoke-NativeChecked `
        -FilePath $PythonExe `
        -ArgumentList @(
            (Join-Path $repo "scripts\validate_auto_threshold_preview_runner.py"),
            "--project-root", $repo,
            "--output-root", $previewSmokeRoot,
            "--replace"
        ) `
        -StepName "Compiled automatic-cleaning preview contract smoke"
    $runnerTarget = Join-Path $distRoot "bin\BridgeAnalysisRunner"
    if (Test-Path -LiteralPath $runnerTarget) {
        Remove-Item -LiteralPath $runnerTarget -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path $runnerTarget) -Force | Out-Null
    Copy-Item -LiteralPath $runnerSource -Destination $runnerTarget -Recurse -Force
}

$reportRuntimeSmokeOutput = Join-Path $buildRoot "embedded_report_runtime_smoke.json"
$reportRuntimeSmokeProcess = Start-Process `
    -FilePath $exePath `
    -ArgumentList @("--report-runtime-smoke-test", "--smoke-output", $reportRuntimeSmokeOutput) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($reportRuntimeSmokeProcess.ExitCode -ne 0) {
    throw "Embedded report runtime smoke failed with exit code $($reportRuntimeSmokeProcess.ExitCode)"
}
$reportRuntimeSmoke = Get-Content -LiteralPath $reportRuntimeSmokeOutput -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $reportRuntimeSmoke.ok -or $reportRuntimeSmoke.runtime -ne "embedded_headless_worker" `
        -or $reportRuntimeSmoke.standalone_report_window `
        -or -not $reportRuntimeSmoke.report_gate_contract `
        -or -not $reportRuntimeSmoke.embedded_report_job `
        -or -not $reportRuntimeSmoke.visual_qc_contract) {
    throw "Embedded report runtime contract failed: $($reportRuntimeSmoke | ConvertTo-Json -Compress)"
}

$smokeOutput = Join-Path $distRoot "workbench_smoke.json"
$smokeProcess = Start-Process `
    -FilePath $exePath `
    -ArgumentList @("--smoke-test", "--smoke-output", $smokeOutput) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($smokeProcess.ExitCode -ne 0) {
    throw "Workbench EXE smoke test failed with exit code $($smokeProcess.ExitCode)"
}
$invalidCliProcess = Start-Process `
    -FilePath $exePath `
    -ArgumentList @("--definitely-invalid-workbench-option") `
    -WindowStyle Hidden `
    -PassThru
if (-not $invalidCliProcess.WaitForExit(10000)) {
    Stop-Process -Id $invalidCliProcess.Id -Force -ErrorAction SilentlyContinue
    throw "Workbench invalid-CLI smoke timed out; a noconsole error dialog may have blocked exit"
}
if ($invalidCliProcess.ExitCode -ne 2) {
    throw "Workbench invalid-CLI smoke expected exit code 2, got $($invalidCliProcess.ExitCode)"
}
$smoke = Get-Content -LiteralPath $smokeOutput -Raw -Encoding UTF8 | ConvertFrom-Json
$profileCatalog = Get-Content -LiteralPath (Join-Path $distRoot "config\bridge_profiles.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedProfileCount = @($profileCatalog.profiles).Count
if ($expectedProfileCount -lt 1) {
    throw "Packaged bridge profile catalog is empty"
}
if (-not $smoke.ok -or $smoke.profile_count -ne $expectedProfileCount -or $smoke.tab_count -ne 4 `
        -or $smoke.config_tab_count -lt 8 -or $smoke.module_count -lt 20 `
        -or $smoke.auto_threshold_module_count -lt 10 `
        -or -not $smoke.auto_threshold_preview_enabled `
        -or -not $smoke.update_backup_management_enabled `
        -or -not $smoke.auto_update_option_available `
        -or -not $smoke.profile_matrix_review_enabled `
        -or $smoke.executable_filename -ne "${bundleName}.exe" `
        -or $smoke.ui_font_point_size -lt 10 `
        -or -not $smoke.task_history_enabled `
        -or $smoke.task_history_column_count -ne 8 `
        -or $smoke.effective_warning_row_count -lt 1 `
        -or $smoke.warning_subtab_count -ne 2 `
        -or $smoke.invalid_warning_row_count -ne 0 `
        -or $smoke.group_plot_module_count -lt 1 `
        -or $smoke.cleaning_threshold_row_count -lt 1 `
        -or -not $smoke.cleaning_exclude_editor_available `
        -or -not $smoke.window_icon_available `
        -or -not $smoke.organization_logo_available `
        -or $smoke.plot_common_field_count -ne 14 `
        -or $smoke.spectrum_module_count -ne 2 `
        -or $smoke.provenance_column_count -ne 7 `
        -or $smoke.report_qc_column_count -ne 5) {
    throw "Workbench EXE smoke contract failed: $($smoke | ConvertTo-Json -Compress)"
}

$profileMatrixOutput = Join-Path $distRoot "workbench_profile_matrix.json"
Invoke-NativeChecked `
    -FilePath $PythonExe `
    -ArgumentList @(
        (Join-Path $repo "scripts\validate_workbench_installed_profiles.py"),
        "--package-root", $distRoot,
        "--output", $profileMatrixOutput,
        "--evidence-root", (Join-Path $buildRoot "profile_matrix_evidence")
    ) `
    -StepName "Frozen all-profile matrix"
$profileMatrix = Get-Content -LiteralPath $profileMatrixOutput -Raw -Encoding UTF8 | ConvertFrom-Json
if ($profileMatrix.status -ne "passed" -or $profileMatrix.profile_count -ne $expectedProfileCount `
        -or ($profileMatrix.report_capable_count + $profileMatrix.analysis_only_count) -ne $expectedProfileCount `
        -or -not $profileMatrix.assets_unchanged) {
    throw "Frozen all-profile matrix contract failed: $($profileMatrix | ConvertTo-Json -Compress -Depth 4)"
}

$screenshotOutput = Join-Path $distRoot "workbench_startup.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $screenshotOutput -ProfileId "guanbing" -TabIndex 0
$configScreenshotOutput = Join-Path $distRoot "workbench_alarm_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $configScreenshotOutput -ProfileId "hongtang" -TabIndex 1 -WarningTabIndex 1
$warningOverviewScreenshotOutput = Join-Path $distRoot "workbench_warning_overview.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $warningOverviewScreenshotOutput -ProfileId "guanbing" -TabIndex 1 -WarningTabIndex 0
$warningEmptyBoundsScreenshotOutput = Join-Path $distRoot "workbench_warning_empty_bounds.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $warningEmptyBoundsScreenshotOutput -ProfileId "guanbing" -TabIndex 1 -WarningTabIndex 1
$cleaningScreenshotOutput = Join-Path $distRoot "workbench_cleaning_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $cleaningScreenshotOutput -ProfileId "guanbing" -TabIndex 1 -ConfigTabIndex 1
$cleaningExclusionScreenshotOutput = Join-Path $distRoot "workbench_cleaning_exclusion_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $cleaningExclusionScreenshotOutput -ProfileId "hongtang" -TabIndex 1 -ConfigTabIndex 1 -CleaningTabIndex 1
$postFilterScreenshotOutput = Join-Path $distRoot "workbench_post_filter_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $postFilterScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 2
$autoThresholdScreenshotOutput = Join-Path $distRoot "workbench_auto_threshold.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $autoThresholdScreenshotOutput -ProfileId "guanbing" -TabIndex 1 -ConfigTabIndex 3 -DemoAutoThresholdPreview
$offsetScreenshotOutput = Join-Path $distRoot "workbench_offset_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $offsetScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 4
$groupScreenshotOutput = Join-Path $distRoot "workbench_group_plot_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $groupScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 5
$plotCommonScreenshotOutput = Join-Path $distRoot "workbench_plot_common_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $plotCommonScreenshotOutput -ProfileId "hongtang" -TabIndex 1 -ConfigTabIndex 6
$spectrumScreenshotOutput = Join-Path $distRoot "workbench_spectrum_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $spectrumScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 7
$reviewTermsScreenshotOutput = Join-Path $distRoot "workbench_review_terms.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $reviewTermsScreenshotOutput -ProfileId "guanbing" -TabIndex 2
$reportTaskScreenshotOutput = Join-Path $distRoot "workbench_report_task.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $reportTaskScreenshotOutput -ProfileId "hongtang" -TabIndex 3
$taskHistoryScreenshotOutput = Join-Path $distRoot "workbench_task_history.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $taskHistoryScreenshotOutput -ProfileId "guanbing" -TabIndex 0 -DemoTaskHistory

$files = Get-ChildItem -LiteralPath $distRoot -Recurse -File | Where-Object {
    $_.FullName -ne (Join-Path $distRoot "release_manifest.json")
}
$forbiddenStandaloneReportFiles = @($files | Where-Object {
    $_.Name -ieq "BridgeReportBuilder.exe" -or
    $_.Name -ieq "MonthlyReportBuilder.exe" -or
    $_.FullName.Replace('\', '/') -match '/reporting/report_gui\.py$'
})
if ($forbiddenStandaloneReportFiles.Count -gt 0) {
    $paths = ($forbiddenStandaloneReportFiles | ForEach-Object FullName) -join "; "
    throw "Workbench distribution contains retired standalone report entrypoints: $paths"
}
$fileInventory = @($files | ForEach-Object {
    $relative = $_.FullName.Substring($distRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
    [ordered]@{
        path = $relative
        bytes = [long]$_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})
$updatePolicy = Get-Content -LiteralPath (Join-Path $distRoot "config\workbench_update.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$releaseManifest = [ordered]@{
    schema_version = 3
    built_at = (Get-Date).ToString("o")
    version = (Get-Content -LiteralPath (Join-Path $distRoot "VERSION") -Raw -Encoding UTF8).Trim()
    executable = "${bundleName}.exe"
    executable_sha256 = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
    update_repository = $updatePolicy.repository
    update_channel = $updatePolicy.channel
    includes_analysis_runner = -not $SkipAnalysisRunner
    report_runtime = "embedded_headless_worker"
    standalone_report_builder_included = $false
    # Compatibility gates retained for the v1.8.0-rc2 updater.  They now mean
    # that report-building capability and context checks are included in the
    # workbench, not that a second executable is packaged.
    includes_report_builder = $true
    report_builder_context_smoke = [bool]$reportRuntimeSmoke.report_gate_contract
    embedded_report_runtime_smoke = $true
    embedded_report_job_smoke = [bool]$reportRuntimeSmoke.embedded_report_job
    report_gate_contract_smoke = [bool]$reportRuntimeSmoke.report_gate_contract
    report_visual_qc_smoke = [bool]$reportRuntimeSmoke.visual_qc_contract
    auto_threshold_preview_runner_smoke = -not $SkipAnalysisRunner
    installed_profile_matrix_smoke = $true
    invalid_cli_smoke = $true
    task_history_smoke = $true
    embedded_report_runtime = $reportRuntimeSmoke
    installed_profile_matrix = [ordered]@{
        profile_count = $profileMatrix.profile_count
        report_capable_count = $profileMatrix.report_capable_count
        analysis_only_count = $profileMatrix.analysis_only_count
        asset_count = $profileMatrix.asset_count
        assets_unchanged = $profileMatrix.assets_unchanged
    }
    file_count_excluding_manifest = $files.Count
    total_bytes_excluding_manifest = [long](($files | Measure-Object Length -Sum).Sum)
    file_inventory_count = $fileInventory.Count
    file_inventory = $fileInventory
    screenshots = @(
        "workbench_startup.png",
        "workbench_alarm_editor.png",
        "workbench_warning_overview.png",
        "workbench_warning_empty_bounds.png",
        "workbench_cleaning_editor.png",
        "workbench_cleaning_exclusion_editor.png",
        "workbench_post_filter_editor.png",
        "workbench_auto_threshold.png",
        "workbench_offset_editor.png",
        "workbench_group_plot_editor.png",
        "workbench_plot_common_editor.png",
        "workbench_spectrum_editor.png",
        "workbench_review_terms.png",
        "workbench_report_task.png"
        "workbench_task_history.png"
    )
    smoke = $smoke
}
$manifestPath = Join-Path $distRoot "release_manifest.json"
$releaseManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Workbench EXE built and verified: $exePath"
Write-Host "Release manifest: $manifestPath"
