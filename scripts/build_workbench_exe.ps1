param(
    [string]$PythonExe = "reporting\.venv\Scripts\python.exe",
    [switch]$SkipAnalysisRunner,
    [switch]$OffscreenScreenshots
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

function Get-GitSourceState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $commitOutput = @(& git -C $RepositoryRoot rev-parse --verify HEAD 2>&1)
    $commitExitCode = $LASTEXITCODE
    if ($commitExitCode -ne 0) {
        throw "Unable to resolve the source Git commit (exit $commitExitCode): $($commitOutput -join '; ')"
    }
    if ($commitOutput.Count -ne 1) {
        throw "Git returned an ambiguous source commit: $($commitOutput -join '; ')"
    }
    $commit = ([string]$commitOutput[0]).Trim().ToLowerInvariant()
    if ($commit -notmatch '^[0-9a-f]{40}$') {
        throw "Git returned an invalid source commit: $commit"
    }

    $statusOutput = @(& git -C $RepositoryRoot status --porcelain=v1 --untracked-files=all 2>&1)
    $statusExitCode = $LASTEXITCODE
    if ($statusExitCode -ne 0) {
        throw "Unable to inspect the source Git working tree (exit $statusExitCode): $($statusOutput -join '; ')"
    }
    return [pscustomobject]@{
        commit = $commit
        clean = ($statusOutput.Count -eq 0)
    }
}

function Assert-OperatorGuideContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Operator guide not found: $Path"
    }

    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    # Keep the build script Windows PowerShell 5.1 / ASCII-safe.  A longer
    # button caption is accepted because the required caption stem is matched
    # as a substring.
    $requiredFragments = @(
        (-join (39044, 29983, 25104, 20998, 26512, 32531, 23384 | ForEach-Object { [char]$_ })),
        (-join (25171, 24320, 26354, 32447, 39044, 35272, 24182, 25302, 32447, 35774, 32622 | ForEach-Object { [char]$_ })),
        (-join (25302, 32447, 35774, 32622, 19978, 19979, 38480 | ForEach-Object { [char]$_ })),
        (-join (19979, 20391, 26694, 36873, 21462, 26694, 20013, 23454, 38469, 26377, 38480, 26679, 26412, 30340, 26368, 39640, 20540 | ForEach-Object { [char]$_ })),
        (-join (19978, 20391, 26694, 36873, 21462, 26694, 20013, 23454, 38469, 26377, 38480, 26679, 26412, 30340, 26368, 20302, 20540 | ForEach-Object { [char]$_ })),
        (-join (21024, 38500, 20005, 26684, 20302, 20110, 35813, 20540, 30340, 25968, 25454 | ForEach-Object { [char]$_ })),
        (-join (21024, 38500, 20005, 26684, 39640, 20110, 35813, 20540, 30340, 25968, 25454 | ForEach-Object { [char]$_ })),
        (-join (31561, 20110, 20505, 36873, 38408, 20540, 30340, 28857, 20445, 30041 | ForEach-Object { [char]$_ })),
        (-join (39640, 39118, 38505, 12289, 40664, 35748, 20851, 38381 | ForEach-Object { [char]$_ })),
        (-join (21482, 20445, 23384, 22312, 24403, 21069, 20219, 21153, 26041, 26696, 20013 | ForEach-Object { [char]$_ })),
        (-join (19981, 20889, 20837, 26725, 26753, 20844, 20849, 37197, 32622 | ForEach-Object { [char]$_ })),
        (-join (26412, 27425, 35745, 31639, 32467, 26524, 22312, 21738, 37324 | ForEach-Object { [char]$_ })),
        (-join (33258, 21160, 21305, 37197, 24403, 21069, 20219, 21153, 26354, 32447, 39044, 35272 | ForEach-Object { [char]$_ })),
        (-join (26222, 36890, 27969, 31243, 26080, 38656, 36873, 25321, 20219, 20309, 25991, 20214 | ForEach-Object { [char]$_ })),
        (-join (30452, 25509, 36873, 25321, 32, 77, 65, 84, 76, 65, 66, 32, 70, 73, 71 | ForEach-Object { [char]$_ })),
        (-join (23548, 20837, 20854, 20182, 20219, 21153, 30340, 24037, 20316, 24179, 21488, 26354, 32447, 35760, 24405 | ForEach-Object { [char]$_ })),
        (-join (29983, 25104, 24403, 21069, 27979, 28857, 26354, 32447 | ForEach-Object { [char]$_ })),
        (-join (19981, 36816, 34892, 33258, 21160, 38408, 20540, 31639, 27861 | ForEach-Object { [char]$_ })),
        (-join (39640, 32423, 65306, 20174, 32, 74, 83, 79, 78, 32, 25991, 20214, 23548, 20837 | ForEach-Object { [char]$_ })),
        (-join (30495, 23454, 36827, 24230 | ForEach-Object { [char]$_ })),
        (-join (35831, 27714, 23433, 20840, 20572, 27490 | ForEach-Object { [char]$_ })),
        (-join (20572, 27490, 26412, 27425, 32, 70, 73, 71, 32, 25805, 20316 | ForEach-Object { [char]$_ })),
        "stats",
        "run_logs",
        "DOCX/PDF",
        "jlj_daily_export",
        "DELETE_VERIFIED_EXTRACTED_CSV"
    )
    foreach ($fragment in $requiredFragments) {
        if (-not $content.Contains($fragment)) {
            throw "Operator guide is missing required user workflow text: $Path"
        }
    }
}

if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw "Python executable not found: $PythonExe"
}

$sourceGitStateBeforeBuild = Get-GitSourceState -RepositoryRoot $repo

Invoke-NativeChecked `
    -FilePath $PythonExe `
    -ArgumentList @("-m", "pip", "install", "-r", "reporting\requirements-build.txt") `
    -StepName "Workbench Python dependency installation"
Invoke-NativeChecked `
    -FilePath $PythonExe `
    -ArgumentList @("-c", "import PySide6, PyInstaller, docx, openpyxl, PIL, lxml, matplotlib, numpy, pypdf, win32com.client") `
    -StepName "Workbench Python dependency import check"

$distParent = Join-Path $repo "dist"
$buildRoot = Join-Path $repo "build\workbench"
# Keep this PowerShell 5.1 script ASCII-safe while constructing the canonical
# Chinese display name from its Unicode code points.
$bundleName = -join (26725, 26753, 20581, 24247, 30417, 27979, 24037, 20316, 24179, 21488 | ForEach-Object { [char]$_ })
$legacyChineseExecutableName = (-join (26725, 26753, 20581, 24247, 30417, 27979, 24037, 20316, 21488 | ForEach-Object { [char]$_ })) + ".exe"
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
$operatorGuideSource = Join-Path $repo "docs\OPERATOR_GUIDE.md"
$packagedOperatorGuide = Join-Path $distRoot $operatorGuideName
Assert-OperatorGuideContract -Path $operatorGuideSource
Copy-Item -LiteralPath $operatorGuideSource -Destination $packagedOperatorGuide -Force
Assert-OperatorGuideContract -Path $packagedOperatorGuide

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

$analysisRunnerFailureExitSmoke = $false
$analysisRunnerManifestResilienceSmoke = $false
$analysisRunnerManifestResilience = $null
$analysisRunnerCacheCleanupPolicySmoke = $false
$analysisRunnerCacheCleanupPolicy = $null
$analysisRunnerFigThresholdSmoke = $false
$analysisRunnerFigThreshold = $null
$thresholdCurveRunnerSmoke = $false
$thresholdCurveRunner = $null
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
    $failureExitSmokeRoot = Join-Path $buildRoot "analysis_runner_failure_exit_smoke"
    Invoke-NativeChecked `
        -FilePath $PythonExe `
        -ArgumentList @(
            (Join-Path $repo "scripts\validate_analysis_runner_failure_exit.py"),
            "--project-root", $repo,
            "--runner", $runnerExe,
            "--output-root", $failureExitSmokeRoot,
            "--replace"
        ) `
        -StepName "Compiled analysis failure-exit contract smoke"
    $analysisRunnerFailureExitSmoke = $true
    $manifestResilienceSmokeRoot = Join-Path $buildRoot "analysis_runner_manifest_resilience_smoke"
    Invoke-NativeChecked `
        -FilePath $PythonExe `
        -ArgumentList @(
            (Join-Path $repo "scripts\validate_analysis_runner_manifest_resilience.py"),
            "--project-root", $repo,
            "--runner", $runnerExe,
            "--output-root", $manifestResilienceSmokeRoot,
            "--replace"
        ) `
        -StepName "Compiled analysis manifest-resilience smoke"
    $manifestResilienceSummaryPath = Join-Path $manifestResilienceSmokeRoot "manifest_resilience_contract_summary.json"
    $analysisRunnerManifestResilience = Get-Content -LiteralPath $manifestResilienceSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $analysisRunnerManifestResilience.ok `
            -or -not $analysisRunnerManifestResilience.large_manifest.ok `
            -or $analysisRunnerManifestResilience.large_manifest.runner_exit_code -ne 0 `
            -or $analysisRunnerManifestResilience.large_manifest.analysis_status -ne "completed" `
            -or $analysisRunnerManifestResilience.large_manifest.manifest_status -ne "ok" `
            -or $analysisRunnerManifestResilience.large_manifest.manifest_type -ne "analysis_run" `
            -or $analysisRunnerManifestResilience.large_manifest.request_bytes -ge 1048576 `
            -or $analysisRunnerManifestResilience.large_manifest.manifest_bytes -le 1048576 `
            -or $analysisRunnerManifestResilience.large_manifest.module_result_warning_count -ne $analysisRunnerManifestResilience.large_manifest.warning_count `
            -or $analysisRunnerManifestResilience.large_manifest.module_log_warning_count -ne $analysisRunnerManifestResilience.large_manifest.warning_count `
            -or $analysisRunnerManifestResilience.large_manifest.temporary_json_file_count -ne 0 `
            -or -not $analysisRunnerManifestResilience.write_failure_fallback.ok `
            -or $analysisRunnerManifestResilience.write_failure_fallback.runner_exit_code -eq 0 `
            -or $analysisRunnerManifestResilience.write_failure_fallback.analysis_status -ne "failed" `
            -or $analysisRunnerManifestResilience.write_failure_fallback.manifest_status -ne "failed" `
            -or $analysisRunnerManifestResilience.write_failure_fallback.manifest_type -ne "analysis_run_write_failure" `
            -or $analysisRunnerManifestResilience.write_failure_fallback.requested_status -ne "ok" `
            -or $analysisRunnerManifestResilience.write_failure_fallback.write_error_identifier -ne "bms:Logger:JsonPublishFailed" `
            -or $analysisRunnerManifestResilience.write_failure_fallback.temporary_json_file_count -ne 0) {
        throw "Compiled analysis manifest-resilience evidence is incomplete"
    }
    $analysisRunnerManifestResilienceSmoke = $true
    $cleanupPolicySmokeRoot = Join-Path $buildRoot "analysis_runner_cache_cleanup_policy_smoke"
    Invoke-NativeChecked `
        -FilePath $PythonExe `
        -ArgumentList @(
            (Join-Path $repo "scripts\validate_analysis_runner_cache_cleanup_policy.py"),
            "--project-root", $repo,
            "--runner", $runnerExe,
            "--output-root", $cleanupPolicySmokeRoot,
            "--replace"
        ) `
        -StepName "Compiled analysis cache-cleanup policy smoke"
    $cleanupPolicySummaryPath = Join-Path $cleanupPolicySmokeRoot "cleanup_policy_contract_summary.json"
    $analysisRunnerCacheCleanupPolicy = Get-Content -LiteralPath $cleanupPolicySummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $analysisRunnerCacheCleanupPolicy.ok `
            -or -not $analysisRunnerCacheCleanupPolicy.default_off.ok `
            -or -not $analysisRunnerCacheCleanupPolicy.unsafe_policy.ok `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup.ok `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup.configured_csv_deleted `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup.unconfigured_csv_preserved `
            -or $analysisRunnerCacheCleanupPolicy.enabled_cleanup.receipt_status -ne "committed" `
            -or $analysisRunnerCacheCleanupPolicy.enabled_cleanup.deleted_count -ne 1 `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup_dated_folders.ok `
            -or $analysisRunnerCacheCleanupPolicy.enabled_cleanup_dated_folders.layout -ne "dated_folders" `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup_dated_folders.configured_csv_deleted `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup_dated_folders.unconfigured_csv_preserved `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup_dated_folders.source_archives_preserved `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup_dated_folders.workbook_and_wim_preserved `
            -or $analysisRunnerCacheCleanupPolicy.enabled_cleanup_dated_folders.receipt_status -ne "committed" `
            -or $analysisRunnerCacheCleanupPolicy.enabled_cleanup_dated_folders.deleted_count -ne 1 `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup_hongtang_period.ok `
            -or $analysisRunnerCacheCleanupPolicy.enabled_cleanup_hongtang_period.layout -ne "hongtang_period" `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup_hongtang_period.configured_csv_deleted `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup_hongtang_period.unconfigured_csv_preserved `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup_hongtang_period.source_archives_preserved `
            -or -not $analysisRunnerCacheCleanupPolicy.enabled_cleanup_hongtang_period.workbook_and_wim_preserved `
            -or $analysisRunnerCacheCleanupPolicy.enabled_cleanup_hongtang_period.receipt_status -ne "committed" `
            -or $analysisRunnerCacheCleanupPolicy.enabled_cleanup_hongtang_period.deleted_count -ne 1) {
        throw "Compiled analysis cache-cleanup policy evidence is incomplete"
    }
    $analysisRunnerCacheCleanupPolicySmoke = $true
    $figThresholdSmokeRoot = Join-Path $buildRoot "analysis_runner_fig_threshold_smoke"
    Invoke-NativeChecked `
        -FilePath $PythonExe `
        -ArgumentList @(
            (Join-Path $repo "scripts\validate_analysis_runner_fig_threshold.py"),
            "--project-root", $repo,
            "--runner", $runnerExe,
            "--output-root", $figThresholdSmokeRoot,
            "--replace"
        ) `
        -StepName "Compiled analysis FIG-threshold contract smoke"
    $figThresholdSummaryPath = Join-Path $figThresholdSmokeRoot "fig_threshold_contract_summary.json"
    $analysisRunnerFigThreshold = Get-Content -LiteralPath $figThresholdSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $analysisRunnerFigThreshold.ok `
            -or -not $analysisRunnerFigThreshold.source_fig_unchanged `
            -or -not $analysisRunnerFigThreshold.scripted_no_manual_ui `
            -or $analysisRunnerFigThreshold.compiled_operation_count -ne 3 `
            -or -not $analysisRunnerFigThreshold.visibility_dispatch.ok `
            -or -not $analysisRunnerFigThreshold.visibility_dispatch.default_figure_visible_forced_on `
            -or -not $analysisRunnerFigThreshold.visibility_dispatch.default_figure_visible_restore_guard `
            -or -not $analysisRunnerFigThreshold.visibility_dispatch.compiled_dispatch_present `
            -or -not $analysisRunnerFigThreshold.operations.band.ok `
            -or -not $analysisRunnerFigThreshold.operations.band.candidate_matches `
            -or -not $analysisRunnerFigThreshold.operations.band.source_hash_matches `
            -or -not $analysisRunnerFigThreshold.operations.box_lower.ok `
            -or -not $analysisRunnerFigThreshold.operations.box_lower.candidate_matches `
            -or -not $analysisRunnerFigThreshold.operations.box_lower.source_hash_matches `
            -or -not $analysisRunnerFigThreshold.operations.box_upper.ok `
            -or -not $analysisRunnerFigThreshold.operations.box_upper.candidate_matches `
            -or -not $analysisRunnerFigThreshold.operations.box_upper.source_hash_matches) {
        throw "Compiled analysis FIG-threshold evidence is incomplete"
    }
    $analysisRunnerFigThresholdSmoke = $true
    $thresholdCurveSmokeRoot = Join-Path $buildRoot "threshold_curve_runner_smoke"
    Invoke-NativeChecked `
        -FilePath $PythonExe `
        -ArgumentList @(
            (Join-Path $repo "scripts\validate_threshold_curve_runner.py"),
            "--project-root", $repo,
            "--output-root", $thresholdCurveSmokeRoot,
            "--replace"
        ) `
        -StepName "Compiled independent threshold-curve contract smoke"
    $thresholdCurveSummaryPath = Join-Path $thresholdCurveSmokeRoot "threshold_curve_contract_summary.json"
    $thresholdCurveRunner = Get-Content -LiteralPath $thresholdCurveSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $thresholdCurveRunner.ok `
            -or $thresholdCurveRunner.runner_exit_code -ne 0 `
            -or $thresholdCurveRunner.curve_record_count -ne 1 `
            -or $thresholdCurveRunner.source_sample_count -ne 101 `
            -or $thresholdCurveRunner.finite_sample_count -ne 101 `
            -or $thresholdCurveRunner.preview_max -ne 100 `
            -or $thresholdCurveRunner.progress_percent -ne 100 `
            -or $thresholdCurveRunner.preview_sha256 -notmatch '^[0-9A-Fa-f]{64}$' `
            -or $thresholdCurveRunner.record_sha256 -notmatch '^[0-9A-Fa-f]{64}$' `
            -or $thresholdCurveRunner.unexpected_auto_preview_count -ne 0) {
        throw "Compiled independent threshold-curve evidence is incomplete"
    }
    $thresholdCurveRunnerSmoke = $true
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
$cacheCleanupSmokeOutput = Join-Path $buildRoot "cache_source_cleanup_contract_smoke.json"
$cacheCleanupSmokeProcess = Start-Process `
    -FilePath $exePath `
    -ArgumentList @(
        "--profile-id", "jiulongjiang",
        "--demo-cache-source-cleanup",
        "--smoke-test",
        "--smoke-output", $cacheCleanupSmokeOutput
    ) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($cacheCleanupSmokeProcess.ExitCode -ne 0) {
    throw "Workbench cache-source cleanup contract smoke failed with exit code $($cacheCleanupSmokeProcess.ExitCode)"
}
$cacheCleanupSmoke = Get-Content -LiteralPath $cacheCleanupSmokeOutput -Raw -Encoding UTF8 | ConvertFrom-Json
$cacheCleanupContract = $cacheCleanupSmoke.cache_source_cleanup_contract
$cacheSourceCleanupContractSmoke = (
    $smoke.cache_source_cleanup_control_available `
        -and $smoke.cache_source_cleanup_default_off `
        -and $smoke.cache_source_cleanup_confirmation_empty `
        -and $smoke.cache_source_cleanup_confirmation_required `
        -and -not $smoke.cache_source_cleanup_task_option_present `
        -and $smoke.cache_source_cleanup_supported_data_layout -eq "jlj_daily_export" `
        -and ((@($smoke.cache_source_cleanup_supported_data_layouts) -join "|") -eq `
            "dated_folders|hongtang_period|jlj_daily_export") `
        -and $smoke.cache_source_cleanup_current_layout_supported `
        -and $cacheCleanupSmoke.cache_source_cleanup_current_layout_supported `
        -and $cacheCleanupSmoke.cache_source_cleanup_checked `
        -and $cacheCleanupSmoke.cache_source_cleanup_confirmation_matches `
        -and $cacheCleanupSmoke.cache_source_cleanup_task_option_present `
        -and $cacheCleanupContract.default_off `
        -and $cacheCleanupContract.default_confirmation_empty `
        -and $cacheCleanupContract.default_task_option_absent `
        -and $cacheCleanupContract.layout_supported `
        -and $cacheCleanupContract.control_enabled_after_cache_selection `
        -and $cacheCleanupContract.confirmation_required `
        -and $cacheCleanupContract.confirmation_matches `
        -and $cacheCleanupContract.policy_complete `
        -and $cacheCleanupContract.saved_context_policy_complete `
        -and $cacheCleanupContract.saved_context_roundtrip `
        -and $cacheCleanupContract.restored_enabled `
        -and $cacheCleanupContract.restored_confirmation_matches `
        -and $cacheCleanupContract.task_option.enabled `
        -and $cacheCleanupContract.task_option.mode -eq "verified_extracted_csv" `
        -and $cacheCleanupContract.task_option.commit_scope -eq "day" `
        -and $cacheCleanupContract.task_option.recovery_policy -eq "verified_archive" `
        -and $cacheCleanupContract.task_option.confirmation -eq "DELETE_VERIFIED_EXTRACTED_CSV"
)
if (-not $cacheSourceCleanupContractSmoke) {
    throw "Workbench cache-source cleanup contract failed: $($cacheCleanupSmoke | ConvertTo-Json -Compress -Depth 8)"
}
$profileCatalog = Get-Content -LiteralPath (Join-Path $distRoot "config\bridge_profiles.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedProfileCount = @($profileCatalog.profiles).Count
if ($expectedProfileCount -lt 1) {
    throw "Packaged bridge profile catalog is empty"
}
$operatorFeatureContractSmoke = (
    $smoke.config_tab_count -eq 9 `
        -and $smoke.manual_threshold_controls_available `
        -and $smoke.threshold_band_control_available `
        -and $smoke.lower_box_threshold_control_available `
        -and $smoke.upper_box_threshold_control_available `
        -and $smoke.offset_effective_range_seconds_available `
        -and $smoke.gap_override_column_count -eq 6 `
        -and $smoke.unzip_settings_available `
        -and $smoke.analysis_result_location_visible `
        -and $smoke.analysis_result_open_control_available `
        -and $smoke.threshold_preview_auto_locator_available `
        -and $cacheSourceCleanupContractSmoke
)
if (-not $smoke.ok -or $smoke.profile_count -ne $expectedProfileCount -or $smoke.tab_count -ne 4 `
        -or -not $operatorFeatureContractSmoke -or $smoke.module_count -lt 20 `
        -or $smoke.auto_threshold_module_count -lt 10 `
        -or -not $smoke.auto_threshold_preview_enabled `
        -or -not $smoke.update_backup_management_enabled `
        -or -not $smoke.auto_update_option_available `
        -or -not $smoke.profile_matrix_review_enabled `
        -or $smoke.app_display_name -ne $bundleName `
        -or $smoke.executable_filename -ne "${bundleName}.exe" `
        -or $smoke.ui_font_point_size -lt 10 `
        -or $smoke.ui_font_family -ne "Microsoft YaHei UI" `
        -or $smoke.screen_logical_dpi -lt 96 `
        -or $smoke.device_pixel_ratio -lt 1 `
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
        -or $smoke.provenance_column_count -ne 8 `
        -or $smoke.report_qc_column_count -ne 6) {
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

$captureScript = Join-Path $repo "scripts\capture_workbench_window.ps1"
$captureMode = @{}
if ($OffscreenScreenshots) {
    $captureMode.Offscreen = $true
}
$screenshotOutput = Join-Path $distRoot "workbench_startup.png"
$nativeGuiEvidenceOutput = Join-Path $distRoot "workbench_native_gui_acceptance.json"
if ($OffscreenScreenshots) {
    & $captureScript -ExePath $exePath -OutputPath $screenshotOutput -ProfileId "guanbing" -TabIndex 0 @captureMode
    $nativeGuiAcceptance = $null
}
else {
    & $captureScript -ExePath $exePath -OutputPath $screenshotOutput -ProfileId "guanbing" -TabIndex 0 -EvidencePath $nativeGuiEvidenceOutput
    if (-not (Test-Path -LiteralPath $nativeGuiEvidenceOutput -PathType Leaf)) {
        throw "Native GUI acceptance evidence was not produced"
    }
    $nativeGuiAcceptance = Get-Content -LiteralPath $nativeGuiEvidenceOutput -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $nativeGuiAcceptance.foreground_window_matches `
            -or -not $nativeGuiAcceptance.focus_owned_by_process `
            -or -not $nativeGuiAcceptance.native_window_icon `
            -or $nativeGuiAcceptance.dpi_awareness_code -ne 2 `
            -or $nativeGuiAcceptance.window_dpi -lt 96 `
            -or $nativeGuiAcceptance.physical_width -lt 1000 `
            -or $nativeGuiAcceptance.physical_height -lt 700) {
        throw "Native GUI acceptance evidence failed: $($nativeGuiAcceptance | ConvertTo-Json -Compress)"
    }
}
$configScreenshotOutput = Join-Path $distRoot "workbench_alarm_editor.png"
& $captureScript -ExePath $exePath -OutputPath $configScreenshotOutput -ProfileId "hongtang" -TabIndex 1 -WarningTabIndex 1 @captureMode
$warningOverviewScreenshotOutput = Join-Path $distRoot "workbench_warning_overview.png"
& $captureScript -ExePath $exePath -OutputPath $warningOverviewScreenshotOutput -ProfileId "guanbing" -TabIndex 1 -WarningTabIndex 0 @captureMode
$warningEmptyBoundsScreenshotOutput = Join-Path $distRoot "workbench_warning_empty_bounds.png"
& $captureScript -ExePath $exePath -OutputPath $warningEmptyBoundsScreenshotOutput -ProfileId "guanbing" -TabIndex 1 -WarningTabIndex 1 @captureMode
$cleaningScreenshotOutput = Join-Path $distRoot "workbench_cleaning_editor.png"
& $captureScript -ExePath $exePath -OutputPath $cleaningScreenshotOutput -ProfileId "guanbing" -TabIndex 1 -ConfigTabIndex 1 @captureMode
$cleaningExclusionScreenshotOutput = Join-Path $distRoot "workbench_cleaning_exclusion_editor.png"
& $captureScript -ExePath $exePath -OutputPath $cleaningExclusionScreenshotOutput -ProfileId "hongtang" -TabIndex 1 -ConfigTabIndex 1 -CleaningTabIndex 1 @captureMode
$postFilterScreenshotOutput = Join-Path $distRoot "workbench_post_filter_editor.png"
& $captureScript -ExePath $exePath -OutputPath $postFilterScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 2 @captureMode
$autoThresholdScreenshotOutput = Join-Path $distRoot "workbench_auto_threshold.png"
& $captureScript -ExePath $exePath -OutputPath $autoThresholdScreenshotOutput -ProfileId "guanbing" -TabIndex 1 -ConfigTabIndex 3 -DemoAutoThresholdPreview @captureMode
$offsetScreenshotOutput = Join-Path $distRoot "workbench_offset_editor.png"
& $captureScript -ExePath $exePath -OutputPath $offsetScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 4 @captureMode
$groupScreenshotOutput = Join-Path $distRoot "workbench_group_plot_editor.png"
& $captureScript -ExePath $exePath -OutputPath $groupScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 5 @captureMode
$plotCommonScreenshotOutput = Join-Path $distRoot "workbench_plot_common_editor.png"
& $captureScript -ExePath $exePath -OutputPath $plotCommonScreenshotOutput -ProfileId "hongtang" -TabIndex 1 -ConfigTabIndex 6 @captureMode
$spectrumScreenshotOutput = Join-Path $distRoot "workbench_spectrum_editor.png"
& $captureScript -ExePath $exePath -OutputPath $spectrumScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 7 @captureMode
$unzipScreenshotOutput = Join-Path $distRoot "workbench_unzip_settings.png"
& $captureScript -ExePath $exePath -OutputPath $unzipScreenshotOutput -ProfileId "jiulongjiang" -TabIndex 1 -ConfigTabIndex 8 @captureMode
$cacheCleanupScreenshotOutput = Join-Path $distRoot "workbench_cache_source_cleanup.png"
& $captureScript -ExePath $exePath -OutputPath $cacheCleanupScreenshotOutput -ProfileId "jiulongjiang" -TabIndex 0 -DemoCacheSourceCleanup @captureMode
$reviewTermsScreenshotOutput = Join-Path $distRoot "workbench_review_terms.png"
& $captureScript -ExePath $exePath -OutputPath $reviewTermsScreenshotOutput -ProfileId "guanbing" -TabIndex 2 @captureMode
$reportTaskScreenshotOutput = Join-Path $distRoot "workbench_report_task.png"
& $captureScript -ExePath $exePath -OutputPath $reportTaskScreenshotOutput -ProfileId "hongtang" -TabIndex 3 @captureMode
$taskHistoryScreenshotOutput = Join-Path $distRoot "workbench_task_history.png"
& $captureScript -ExePath $exePath -OutputPath $taskHistoryScreenshotOutput -ProfileId "guanbing" -TabIndex 0 -DemoTaskHistory @captureMode

$allDistItems = @(Get-ChildItem -LiteralPath $distRoot -Recurse -Force)
$reparseItems = @($allDistItems | Where-Object {
    ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
})
if ($reparseItems.Count -gt 0) {
    $paths = ($reparseItems | ForEach-Object FullName) -join "; "
    throw "Workbench distribution contains reparse points: $paths"
}
$files = @($allDistItems | Where-Object {
    -not $_.PSIsContainer `
        -and $_.FullName -ne (Join-Path $distRoot "release_manifest.json")
} | Sort-Object FullName)
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
$sourceGitStateAfterBuild = Get-GitSourceState -RepositoryRoot $repo
if ($sourceGitStateAfterBuild.commit -cne $sourceGitStateBeforeBuild.commit) {
    throw "The source Git commit changed during the workbench build: $($sourceGitStateBeforeBuild.commit) -> $($sourceGitStateAfterBuild.commit)"
}
$sourceTreeCleanForBuild = [bool](
    $sourceGitStateBeforeBuild.clean -and $sourceGitStateAfterBuild.clean
)
$updatePolicy = Get-Content -LiteralPath (Join-Path $distRoot "config\workbench_update.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$releaseManifest = [ordered]@{
    schema_version = 3
    built_at = (Get-Date).ToString("o")
    source_git_commit = $sourceGitStateBeforeBuild.commit
    source_tree_clean = $sourceTreeCleanForBuild
    version = (Get-Content -LiteralPath (Join-Path $distRoot "VERSION") -Raw -Encoding UTF8).Trim()
    display_name = $bundleName
    executable = "${bundleName}.exe"
    supported_executable_filenames = @(
        "${bundleName}.exe",
        $legacyChineseExecutableName,
        "BridgeMonitoringWorkbench.exe"
    )
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
    threshold_curve_runner_smoke = $thresholdCurveRunnerSmoke
    threshold_curve_runner = $thresholdCurveRunner
    analysis_runner_failure_exit_smoke = $analysisRunnerFailureExitSmoke
    analysis_runner_manifest_resilience_smoke = $analysisRunnerManifestResilienceSmoke
    analysis_runner_manifest_resilience = $analysisRunnerManifestResilience
    analysis_runner_cache_cleanup_policy_smoke = $analysisRunnerCacheCleanupPolicySmoke
    analysis_runner_cache_cleanup_policy = $analysisRunnerCacheCleanupPolicy
    analysis_runner_fig_threshold_smoke = $analysisRunnerFigThresholdSmoke
    analysis_runner_fig_threshold = $analysisRunnerFigThreshold
    installed_profile_matrix_smoke = $true
    invalid_cli_smoke = $true
    task_history_smoke = $true
    screenshot_mode = if ($OffscreenScreenshots) { "qt_offscreen" } else { "native_windows" }
    native_screenshot_smoke = -not $OffscreenScreenshots
    native_focus_smoke = -not $OffscreenScreenshots
    native_dpi_smoke = -not $OffscreenScreenshots
    native_font_smoke = (-not $OffscreenScreenshots) -and ($smoke.ui_font_point_size -ge 10)
    native_icon_smoke = (-not $OffscreenScreenshots) -and [bool]$smoke.window_icon_available
    native_gui_acceptance = $nativeGuiAcceptance
    operator_feature_contract_version = 4
    operator_feature_contract_smoke = [bool]$operatorFeatureContractSmoke
    cache_source_cleanup_contract_smoke = [bool]$cacheSourceCleanupContractSmoke
    cache_source_cleanup_contract = $cacheCleanupContract
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
        "workbench_unzip_settings.png",
        "workbench_cache_source_cleanup.png",
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
