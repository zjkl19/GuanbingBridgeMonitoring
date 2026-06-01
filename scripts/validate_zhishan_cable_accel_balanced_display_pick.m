function result = validate_zhishan_cable_accel_balanced_display_pick()
%VALIDATE_ZHISHAN_CABLE_ACCEL_BALANCED_DISPLAY_PICK Acceptance gate.
%   Validates the balanced display pick artifacts. Display-only; formal
%   spectrum/force calculation must remain unchanged.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
balancedDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation', ...
    'balanced_display_pick');
manifestPath = fullfile(balancedDir, 'CableAccelBalancedDisplay_manifest.csv');
policyPath = fullfile(balancedDir, 'CableAccelBalancedDisplay_policy.json');
htmlPath = fullfile(balancedDir, 'index.html');
contactSheetPath = fullfile(balancedDir, 'CableAccelBalancedDisplay_ContactSheet.jpg');
reviewBoardPath = fullfile(balancedDir, 'CableAccelBalancedDisplay_ReviewBoard.jpg');

points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
minKeepPct = 92.0;
minCleanerImprovementPct = 2.0;

manifest = readtable(manifestPath, 'Encoding', 'UTF-8');
policy = readJson(policyPath);
cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));

pointRows = {};
for i = 1:numel(points)
    pointId = points{i};
    idx = find(strcmp(manifest.PointID, pointId), 1);
    if isempty(idx)
        pointRows(end+1, :) = {pointId, '', NaN, NaN, false, false, false, false, false, ...
            'missing manifest row'}; %#ok<AGROW>
        continue;
    end
    selectedSource = manifest.SelectedSource{idx};
    field = matlab.lang.makeValidName(strrep(pointId, '-', '_'));
    hasPolicyPoint = isfield(policy, 'points') && isfield(policy.points, field);
    imagePath = fullfile(balancedDir, sprintf( ...
        'CableAccelBalancedDisplay_%s_20260301_20260331.jpg', pointId));
    imageOk = isfile(imagePath) && dirBytes(imagePath) > 10000;
    keepOk = isfinite(manifest.KeepPct(idx)) && manifest.KeepPct(idx) >= minKeepPct;
    sourceOk = any(strcmp(selectedSource, {'cleaner','current'}));
    if strcmp(selectedSource, 'cleaner')
        selectionOk = manifest.CleanerRMS30MaxImprovementPct(idx) >= minCleanerImprovementPct;
    else
        selectionOk = manifest.CleanerRMS30MaxImprovementPct(idx) < minCleanerImprovementPct + 1e-9;
    end
    rowOk = imageOk && keepOk && sourceOk && selectionOk && hasPolicyPoint;
    reason = 'ok';
    if ~rowOk
        parts = {};
        if ~imageOk, parts{end+1} = 'missing/small image'; end %#ok<AGROW>
        if ~keepOk, parts{end+1} = 'keep below target'; end %#ok<AGROW>
        if ~sourceOk, parts{end+1} = 'invalid selected source'; end %#ok<AGROW>
        if ~selectionOk, parts{end+1} = 'selection rule mismatch'; end %#ok<AGROW>
        if ~hasPolicyPoint, parts{end+1} = 'missing policy point'; end %#ok<AGROW>
        reason = strjoin(parts, '; ');
    end
    pointRows(end+1, :) = {pointId, selectedSource, manifest.KeepPct(idx), ...
        manifest.RMS30Max(idx), manifest.CleanerRMS30MaxImprovementPct(idx), ...
        imageOk, keepOk, sourceOk, selectionOk, hasPolicyPoint, rowOk, reason}; %#ok<AGROW>
end

pointChecks = cell2table(pointRows, 'VariableNames', { ...
    'PointID','SelectedSource','KeepPct','RMS30Max','CleanerRMS30MaxImprovementPct', ...
    'ImageOK','KeepOK','SourceOK','SelectionRuleOK','PolicyPointOK','Pass','Reason'});

formalConfigOk = hasFormalCableAccelPolicy(cfg);
policyScopeOk = isfield(policy, 'scope') && strcmp(policy.scope, 'display_only');
policyRuleOk = isfield(policy, 'selection_rule') && contains(policy.selection_rule, 'cleaner keep >= 92.0%');
manifestOk = isfile(manifestPath) && height(manifest) == 8;
htmlOk = isfile(htmlPath) && dirBytes(htmlPath) > 1000;
contactSheetOk = isfile(contactSheetPath) && dirBytes(contactSheetPath) > 10000;
reviewBoardOk = isfile(reviewBoardPath) && dirBytes(reviewBoardPath) > 10000;
allPointsOk = all(pointChecks.Pass);
overallPass = formalConfigOk && policyScopeOk && policyRuleOk && manifestOk && ...
    htmlOk && contactSheetOk && reviewBoardOk && allPointsOk;

globalChecks = table( ...
    {'formal_config_daily_median_abs100'; 'policy_scope_display_only'; ...
     'selection_rule_recorded'; 'manifest_8_points'; 'html_exists'; ...
     'contact_sheet_exists'; 'review_board_exists'; 'all_point_checks'}, ...
    [formalConfigOk; policyScopeOk; policyRuleOk; manifestOk; htmlOk; ...
     contactSheetOk; reviewBoardOk; allPointsOk], ...
    'VariableNames', {'Check','Pass'});

acceptanceXlsx = fullfile(balancedDir, 'CableAccelBalancedDisplay_acceptance.xlsx');
acceptanceJson = fullfile(balancedDir, 'CableAccelBalancedDisplay_acceptance.json');
acceptanceHtml = fullfile(balancedDir, 'acceptance.html');
acceptanceMd = fullfile(balancedDir, 'CableAccelBalancedDisplay_acceptance.md');
writetable(globalChecks, acceptanceXlsx, 'Sheet', 'global_checks');
writetable(pointChecks, acceptanceXlsx, 'Sheet', 'point_checks');
writeJson(acceptanceJson, overallPass, globalChecks, pointChecks, minKeepPct, minCleanerImprovementPct);
writeMarkdown(acceptanceMd, overallPass, globalChecks, pointChecks, minKeepPct, minCleanerImprovementPct);
writeHtml(acceptanceHtml, overallPass, globalChecks, pointChecks, minKeepPct, minCleanerImprovementPct, contactSheetPath);

result = struct();
result.pass = overallPass;
result.global_checks = globalChecks;
result.point_checks = pointChecks;
result.workbook = acceptanceXlsx;
result.json = acceptanceJson;
result.markdown = acceptanceMd;
result.html = acceptanceHtml;

fprintf('balanced acceptance pass: %d\n', overallPass);
fprintf('workbook %s\n', acceptanceXlsx);
fprintf('html %s\n', acceptanceHtml);
disp(globalChecks);
disp(pointChecks(:, {'PointID','SelectedSource','KeepPct','CleanerRMS30MaxImprovementPct','Pass','Reason'}));
end

function data = readJson(path)
fid = fopen(path, 'r', 'n', 'UTF-8');
if fid < 0
    error('Cannot open %s.', path);
end
cleaner = onCleanup(@() fclose(fid));
text = fread(fid, '*char')';
data = jsondecode(text);
end

function writeJson(path, overallPass, globalChecks, pointChecks, minKeepPct, minCleanerImprovementPct)
data = struct();
data.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
data.pass = overallPass;
data.min_keep_pct = minKeepPct;
data.min_cleaner_improvement_pct = minCleanerImprovementPct;
data.global_checks = table2struct(globalChecks);
data.point_checks = table2struct(pointChecks);
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(data));
end

function writeMarkdown(path, overallPass, globalChecks, pointChecks, minKeepPct, minCleanerImprovementPct)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Balanced Display Acceptance\n\n');
fprintf(fid, '- Overall pass: `%d`\n', overallPass);
fprintf(fid, '- Minimum keep: `%.1f%%`\n', minKeepPct);
fprintf(fid, '- Minimum cleaner improvement for cleaner rows: `%.1f%%`\n\n', minCleanerImprovementPct);
fprintf(fid, '| Global check | Pass |\n|---|---:|\n');
for i = 1:height(globalChecks)
    fprintf(fid, '| %s | %d |\n', globalChecks.Check{i}, globalChecks.Pass(i));
end
fprintf(fid, '\n| Point | Source | Keep %% | Cleaner RMS max improvement %% | Pass | Reason |\n');
fprintf(fid, '|---|---|---:|---:|---:|---|\n');
for i = 1:height(pointChecks)
    fprintf(fid, '| %s | %s | %.3f | %.1f | %d | %s |\n', ...
        pointChecks.PointID{i}, pointChecks.SelectedSource{i}, pointChecks.KeepPct(i), ...
        pointChecks.CleanerRMS30MaxImprovementPct(i), pointChecks.Pass(i), pointChecks.Reason{i});
end
end

function writeHtml(path, overallPass, globalChecks, pointChecks, minKeepPct, minCleanerImprovementPct, contactSheetPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Balanced Acceptance</title>\n');
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
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230; balanced &#39564;&#25910; / Balanced Acceptance</h1>\n');
fprintf(fid, '<p>Overall pass: <span class="%s">%d</span><br>Minimum keep: %.1f%%<br>Minimum cleaner improvement: %.1f%%</p>\n', ...
    cls, overallPass, minKeepPct, minCleanerImprovementPct);
fprintf(fid, '<h2>&#20840;&#23616;&#26816;&#26597; / Global Checks</h2><table><tr><th>Check</th><th>Pass</th></tr>\n');
for i = 1:height(globalChecks)
    fprintf(fid, '<tr><td>%s</td><td class="num">%d</td></tr>\n', htmlText(globalChecks.Check{i}), globalChecks.Pass(i));
end
fprintf(fid, '</table>\n<h2>&#27979;&#28857;&#26816;&#26597; / Point Checks</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Source</th><th>Keep %%</th><th>Cleaner RMS max improvement %%</th><th>Pass</th><th>Reason</th></tr>\n');
for i = 1:height(pointChecks)
    fprintf(fid, '<tr><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%d</td><td>%s</td></tr>\n', ...
        htmlText(pointChecks.PointID{i}), htmlText(pointChecks.SelectedSource{i}), ...
        pointChecks.KeepPct(i), pointChecks.CleanerRMS30MaxImprovementPct(i), ...
        pointChecks.Pass(i), htmlText(pointChecks.Reason{i}));
end
fprintf(fid, '</table>\n<h2>&#32039;&#20945;&#22797;&#26680;&#22270; / Contact Sheet</h2>\n');
fprintf(fid, '<div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheetPath)));
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
