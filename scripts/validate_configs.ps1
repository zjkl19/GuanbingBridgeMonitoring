param(
    [string[]]$ConfigPaths = @(
        "config\default_config.json",
        "config\hongtang_config.json",
        "config\jiulongjiang_config.json",
        "config\shuixianhua_config.json"
    )
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo
try {
    $escaped = $ConfigPaths | ForEach-Object { $_ -replace "'", "''" }
    $matlabList = "{'" + ($escaped -join "','") + "'}"
    $code = "addpath(pwd, fullfile(pwd,'config')); paths=$matlabList; for i=1:numel(paths), fprintf('Linting %s\n', paths{i}); r=bms.config.ConfigLinter.lintPath(paths{i}); fprintf('  status=%s warnings=%d errors=%d\n', r.status, numel(r.warnings), numel(r.errors)); if strcmp(r.status,'failed'), error('Config validation failed: %s', paths{i}); end, end"
    matlab -batch $code
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
