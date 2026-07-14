param(
    [string[]]$ConfigPaths = @()
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo
try {
    if (@($ConfigPaths).Count -eq 0) {
        $catalogPath = Join-Path $repo "config\bridge_profiles.json"
        $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $ConfigPaths = @($catalog.profiles | ForEach-Object { [string]$_.default_config })
        $layeredPilot = "config\shuixianhua_layered_config.json"
        if (Test-Path -LiteralPath (Join-Path $repo $layeredPilot) -PathType Leaf) {
            $ConfigPaths += $layeredPilot
        }
        $ConfigPaths = @($ConfigPaths | Where-Object { $_ } | Select-Object -Unique)
    }
    $escaped = $ConfigPaths | ForEach-Object { $_ -replace "'", "''" }
    $matlabList = "{'" + ($escaped -join "','") + "'}"
    $code = "addpath(pwd, fullfile(pwd,'config')); paths=$matlabList; for i=1:numel(paths), fprintf('Linting %s\n', paths{i}); r=bms.config.ConfigLinter.lintPath(paths{i}); fprintf('  status=%s warnings=%d errors=%d\n', r.status, numel(r.warnings), numel(r.errors)); if strcmp(r.status,'failed'), error('Config validation failed: %s', paths{i}); end, end"
    matlab -batch $code
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
