function result = validate_zhishan_cable_accel_auto_knee_display_pick()
%VALIDATE_ZHISHAN_CABLE_ACCEL_AUTO_KNEE_DISPLAY_PICK Acceptance gate.
%   Validates the auto-knee display pick artifacts. Display-only; formal
%   spectrum/force calculation must remain unchanged.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
autoKneeDir = fullfile(stableDir, 'auto_knee_display_pick');
reportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_auto_knee_' ...
    char([25512 33616 23637 31034])];
reportDir = fullfile(dataRoot, reportDirName);
compareDir = fullfile(stableDir, 'balanced_vs_auto_knee_review');

manifestPath = fullfile(autoKneeDir, 'CableAccelAutoKnee_manifest.csv');
htmlPath = fullfile(autoKneeDir, 'index.html');
contactSheetPath = fullfile(autoKneeDir, 'CableAccelAutoKnee_ContactSheet.jpg');
reportHtmlPath = fullfile(reportDir, 'index.html');
reportManifestPath = fullfile(reportDir, 'CableAccelAutoKneeReport_manifest.xlsx');
compareHtmlPath = fullfile(compareDir, 'index.html');

points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
minKeepPct = 90.0;
minAutoKneeImprovementPct = 10.0;

manifest = readtable(manifestPath, 'Encoding', 'UTF-8');
cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));

pointRows = {};
for i = 1:numel(points)
    pointId = points{i};
    idx = find(strcmp(manifest.PointID, pointId), 1);
    if isempty(idx)
        pointRows(end+1, :) = {pointId, '', NaN, NaN, NaN, NaN, false, ...
            false, false, false, false, false, 'missing manifest row'}; %#ok<AGROW>
        continue;
    end

    selectedSource = manifest.SelectedSource{idx};
    imagePath = fullfile(autoKneeDir, sprintf( ...
        'plots/CableAccelAutoKnee_%s.jpg', pointId));
    imageOk = isfile(imagePath) && dirBytes(imagePath) > 10000;
    keepOk = isfinite(manifest.KeepPct(idx)) && manifest.KeepPct(idx) >= minKeepPct;
    sourceOk = any(strcmp(selectedSource, {'balanced_final','auto_knee'}));
    manifestPassOk = logical(manifest.AcceptancePass(idx));
    if strcmp(selectedSource, 'auto_knee')
        improvementOk = manifest.RMS30MaxDeltaVsFinalPct(idx) >= minAutoKneeImprovementPct;
    else
        improvementOk = abs(manifest.RMS30MaxDeltaVsFinalPct(idx)) < 0.5 && ...
            abs(manifest.KeepDeltaVsFinalPct(idx)) < 0.01;
    end
    rowOk = imageOk && keepOk && sourceOk && improvementOk && manifestPassOk;
    reason = 'ok';
    if ~rowOk
        parts = {};
        if ~imageOk, parts{end+1} = 'missing/small image'; end %#ok<AGROW>
        if ~keepOk, parts{end+1} = 'keep below target'; end %#ok<AGROW>
        if ~sourceOk, parts{end+1} = 'invalid selected source'; end %#ok<AGROW>
        if ~improvementOk, parts{end+1} = 'improvement rule mismatch'; end %#ok<AGROW>
        if ~manifestPassOk, parts{end+1} = 'manifest acceptance failed'; end %#ok<AGROW>
        reason = strjoin(parts, '; ');
    end
    pointRows(end+1, :) = {pointId, selectedSource, manifest.KeepPct(idx), ...
        manifest.RMS30Max(idx), manifest.KeepDeltaVsFinalPct(idx), ...
        manifest.RMS30MaxDeltaVsFinalPct(idx), imageOk, keepOk, sourceOk, ...
        improvementOk, manifestPassOk, rowOk, reason}; %#ok<AGROW>
end

pointChecks = cell2table(pointRows, 'VariableNames', { ...
    'PointID','SelectedSource','KeepPct','RMS30Max','KeepDeltaVsFinalPct', ...
    'RMS30MaxDeltaVsFinalPct','ImageOK','KeepOK','SourceOK', ...
    'ImprovementRuleOK','ManifestPassOK','Pass','Reason'});

formalConfigOk = hasFormalCableAccelPolicy(cfg);
manifestOk = isfile(manifestPath) && height(manifest) == 8;
htmlOk = isfile(htmlPath) && dirBytes(htmlPath) > 1000;
contactSheetOk = isfile(contactSheetPath) && dirBytes(contactSheetPath) > 10000;
reportOutputOk = isfile(reportHtmlPath) && isfile(reportManifestPath);
compareOutputOk = isfile(compareHtmlPath);
allPointsOk = all(pointChecks.Pass);
autoKneeCountOk = nnz(strcmp(pointChecks.SelectedSource, 'auto_knee')) == 3;
balancedCountOk = nnz(strcmp(pointChecks.SelectedSource, 'balanced_final')) == 5;
overallPass = formalConfigOk && manifestOk && htmlOk && contactSheetOk && ...
    reportOutputOk && compareOutputOk && allPointsOk && autoKneeCountOk && ...
    balancedCountOk;

globalChecks = table( ...
    {'formal_config_daily_median_abs100'; 'manifest_8_points'; ...
     'html_exists'; 'contact_sheet_exists'; 'report_output_exists'; ...
     'balanced_vs_auto_knee_exists'; 'all_point_checks'; ...
     'three_auto_knee_rows'; 'five_balanced_final_rows'}, ...
    [formalConfigOk; manifestOk; htmlOk; contactSheetOk; reportOutputOk; ...
     compareOutputOk; allPointsOk; autoKneeCountOk; balancedCountOk], ...
    'VariableNames', {'Check','Pass'});

acceptanceXlsx = fullfile(autoKneeDir, 'CableAccelAutoKnee_acceptance.xlsx');
acceptanceJson = fullfile(autoKneeDir, 'CableAccelAutoKnee_acceptance.json');
acceptanceHtml = fullfile(autoKneeDir, 'acceptance.html');
acceptanceMd = fullfile(autoKneeDir, 'CableAccelAutoKnee_acceptance.md');
writetable(globalChecks, acceptanceXlsx, 'Sheet', 'global_checks');
writetable(pointChecks, acceptanceXlsx, 'Sheet', 'point_checks');
writeJson(acceptanceJson, overallPass, globalChecks, pointChecks, ...
    minKeepPct, minAutoKneeImprovementPct);
writeMarkdown(acceptanceMd, overallPass, globalChecks, pointChecks, ...
    minKeepPct, minAutoKneeImprovementPct);
writeHtml(acceptanceHtml, overallPass, globalChecks, pointChecks, ...
    minKeepPct, minAutoKneeImprovementPct, contactSheetPath);

result = struct();
result.pass = overallPass;
result.global_checks = globalChecks;
result.point_checks = pointChecks;
result.workbook = acceptanceXlsx;
result.json = acceptanceJson;
result.markdown = acceptanceMd;
result.html = acceptanceHtml;

fprintf('auto-knee acceptance pass: %d\n', overallPass);
fprintf('workbook %s\n', acceptanceXlsx);
fprintf('html %s\n', acceptanceHtml);
disp(globalChecks);
disp(pointChecks(:, {'PointID','SelectedSource','KeepPct', ...
    'RMS30MaxDeltaVsFinalPct','Pass','Reason'}));
end

function writeJson(path, overallPass, globalChecks, pointChecks, minKeepPct, minAutoKneeImprovementPct)
data = struct();
data.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
data.pass = overallPass;
data.min_keep_pct = minKeepPct;
data.min_auto_knee_improvement_pct = minAutoKneeImprovementPct;
data.global_checks = table2struct(globalChecks);
data.point_checks = table2struct(pointChecks);
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(data));
end

function writeMarkdown(path, overallPass, globalChecks, pointChecks, minKeepPct, minAutoKneeImprovementPct)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Auto-Knee Acceptance\n\n');
fprintf(fid, '- Overall pass: `%d`\n', overallPass);
fprintf(fid, '- Minimum keep: `%.1f%%`\n', minKeepPct);
fprintf(fid, '- Minimum auto-knee improvement: `%.1f%%`\n\n', minAutoKneeImprovementPct);
fprintf(fid, '| Global check | Pass |\n|---|---:|\n');
for i = 1:height(globalChecks)
    fprintf(fid, '| %s | %d |\n', globalChecks.Check{i}, globalChecks.Pass(i));
end
fprintf(fid, '\n| Point | Source | Keep %% | RMS30 max delta %% | Pass | Reason |\n');
fprintf(fid, '|---|---|---:|---:|---:|---|\n');
for i = 1:height(pointChecks)
    fprintf(fid, '| %s | %s | %.3f | %.1f | %d | %s |\n', ...
        pointChecks.PointID{i}, pointChecks.SelectedSource{i}, ...
        pointChecks.KeepPct(i), pointChecks.RMS30MaxDeltaVsFinalPct(i), ...
        pointChecks.Pass(i), pointChecks.Reason{i});
end
end

function writeHtml(path, overallPass, globalChecks, pointChecks, minKeepPct, minAutoKneeImprovementPct, contactSheetPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Auto-Knee Acceptance</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;} .pass{color:#067a46;font-weight:700;} .fail{color:#b42318;font-weight:700;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
cls = 'fail';
if overallPass
    cls = 'pass';
end
fprintf(fid, '<h1>Zhishan Cable Acceleration Auto-Knee Acceptance</h1>\n');
fprintf(fid, '<p>Overall pass: <span class="%s">%d</span><br>Minimum keep: %.1f%%<br>Minimum auto-knee improvement: %.1f%%</p>\n', ...
    cls, overallPass, minKeepPct, minAutoKneeImprovementPct);
fprintf(fid, '<h2>Global Checks</h2><table><tr><th>Check</th><th>Pass</th></tr>\n');
for i = 1:height(globalChecks)
    fprintf(fid, '<tr><td>%s</td><td class="num">%d</td></tr>\n', ...
        htmlText(globalChecks.Check{i}), globalChecks.Pass(i));
end
fprintf(fid, '</table>\n<h2>Point Checks</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Source</th><th>Keep %%</th><th>RMS30 max delta %%</th><th>Pass</th><th>Reason</th></tr>\n');
for i = 1:height(pointChecks)
    fprintf(fid, '<tr><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%d</td><td>%s</td></tr>\n', ...
        htmlText(pointChecks.PointID{i}), htmlText(pointChecks.SelectedSource{i}), ...
        pointChecks.KeepPct(i), pointChecks.RMS30MaxDeltaVsFinalPct(i), ...
        pointChecks.Pass(i), htmlText(pointChecks.Reason{i}));
end
fprintf(fid, '</table>\n<h2>Contact Sheet</h2>\n');
fprintf(fid, '<div class="figure"><img src="%s" alt="contact sheet"></div>\n', ...
    htmlText(localFileName(contactSheetPath)));
fprintf(fid, '</body>\n</html>\n');
end

function ok = hasFormalCableAccelPolicy(cfg)
ok = false;
try
    thresholds = cfg.defaults.cable_accel.thresholds;
    if isempty(thresholds)
        return;
    end
    first = thresholds(1);
    hasBounds = isfield(first, 'min') && isfield(first, 'max') && ...
        abs(first.min + 100) < 1e-9 && abs(first.max - 100) < 1e-9;
    hasOffset = isfield(cfg.defaults.cable_accel, 'offset_correction') && ...
        isfield(cfg.defaults.cable_accel.offset_correction, 'mode') && ...
        strcmp(cfg.defaults.cable_accel.offset_correction.mode, 'daily_median');
    ok = hasBounds && hasOffset;
catch
    ok = false;
end
end

function bytes = dirBytes(path)
d = dir(path);
if isempty(d)
    bytes = 0;
else
    bytes = d(1).bytes;
end
end

function out = htmlText(value)
out = char(string(value));
out = strrep(out, '&', '&amp;');
out = strrep(out, '<', '&lt;');
out = strrep(out, '>', '&gt;');
out = strrep(out, '"', '&quot;');
end

function name = localFileName(pathText)
[~, base, ext] = fileparts(char(pathText));
name = [base ext];
end
