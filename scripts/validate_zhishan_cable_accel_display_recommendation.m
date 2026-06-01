function result = validate_zhishan_cable_accel_display_recommendation()
%VALIDATE_ZHISHAN_CABLE_ACCEL_DISPLAY_RECOMMENDATION Final acceptance gate.
%   Validates the display-only recommendation artifacts and formal config.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
runLogs = fullfile(dataRoot, 'run_logs');
exportDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' char([25512 33616 23637 31034])]);
policyPath = fullfile(dataRoot, 'report_cable_accel_display_recommendation', ...
    'CableAccelDisplayRecommendation_policy.json');
reviewPtr = readJson(fullfile(runLogs, 'cable_accel_recommendation_vs_formal_latest.json'));
reviewWorkbook = fullfile(dataRoot, reviewPtr.workbook);
reviewSummary = readtable(reviewWorkbook, 'Sheet', 'summary');

points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
minKeepPct = 93;
minRmsReductionPct = 25;
maxKeepLossPct = 7;

pointRows = {};
for i = 1:numel(points)
    pointId = points{i};
    idx = find(strcmp(reviewSummary.PointID, pointId), 1);
    if isempty(idx)
        pointRows(end+1, :) = {pointId, NaN, NaN, NaN, false, false, false, false, ...
            'missing review row'}; %#ok<AGROW>
        continue;
    end
    plotPath = fullfile(exportDir, sprintf('CableAccelRecommendationDisplay_%s_20260301_20260331.jpg', pointId));
    fileOk = isfile(plotPath) && dirBytes(plotPath) > 10000;
    keepOk = reviewSummary.RecommendationKeepPct(idx) >= minKeepPct;
    reductionOk = reviewSummary.RMS30MaxReductionPct(idx) >= minRmsReductionPct;
    keepLossOk = reviewSummary.KeepDeltaPct(idx) >= -maxKeepLossPct;
    rowOk = fileOk && keepOk && reductionOk && keepLossOk;
    reason = 'ok';
    if ~rowOk
        reason = strjoin([ ...
            reasonIf(~fileOk, "missing/small export image"), ...
            reasonIf(~keepOk, "keep below target"), ...
            reasonIf(~reductionOk, "RMS reduction below target"), ...
            reasonIf(~keepLossOk, "keep loss above target")], '; ');
    end
    pointRows(end+1, :) = {pointId, reviewSummary.RecommendationKeepPct(idx), ...
        reviewSummary.KeepDeltaPct(idx), reviewSummary.RMS30MaxReductionPct(idx), ...
        fileOk, keepOk, reductionOk, keepLossOk, rowOk, reason}; %#ok<AGROW>
end

pointChecks = cell2table(pointRows, 'VariableNames', { ...
    'PointID','KeepPct','KeepDeltaPct','RMS30MaxReductionPct', ...
    'ExportImageOK','KeepOK','RMSReductionOK','KeepLossOK','Pass','Reason'});

policy = readJson(policyPath);
cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
formalConfigOk = hasFormalCableAccelPolicy(cfg);
policyOk = isfield(policy, 'scope') && strcmp(policy.scope, 'display_only');
boardPath = fullfile(exportDir, 'CableAccelRecommendationDisplay_ReviewBoard.jpg');
boardOk = isfile(boardPath) && dirBytes(boardPath) > 10000;
manifestOk = isfile(fullfile(exportDir, 'CableAccelRecommendationDisplay_manifest.xlsx'));
pointCountOk = height(pointChecks) == 8;
allPointsOk = all(pointChecks.Pass);
overallPass = formalConfigOk && policyOk && boardOk && manifestOk && pointCountOk && allPointsOk;

globalChecks = table( ...
    {'formal_config_daily_median_abs100'; 'policy_scope_display_only'; 'review_board_exists'; ...
     'manifest_exists'; 'point_count'; 'all_point_thresholds'}, ...
    [formalConfigOk; policyOk; boardOk; manifestOk; pointCountOk; allPointsOk], ...
    'VariableNames', {'Check','Pass'});

stamp = datestr(now, 'yyyymmdd_HHMMSS');
runName = ['cable_accel_display_acceptance_' stamp];
outRoot = fullfile(runLogs, runName);
if ~exist(outRoot, 'dir'), mkdir(outRoot); end
xlsxPath = fullfile(outRoot, 'cable_accel_display_acceptance.xlsx');
markdownPath = fullfile(outRoot, 'cable_accel_display_acceptance.md');
writetable(globalChecks, xlsxPath, 'Sheet', 'global_checks');
writetable(pointChecks, xlsxPath, 'Sheet', 'point_checks');
writeMarkdown(markdownPath, runName, overallPass, globalChecks, pointChecks, ...
    minKeepPct, minRmsReductionPct, maxKeepLossPct, boardPath, policyPath);
latestPaths = writeLatest(dataRoot, runName, overallPass, xlsxPath, markdownPath, ...
    globalChecks, pointChecks, boardPath, policyPath);

result = struct();
result.run_name = runName;
result.output_folder = outRoot;
result.pass = overallPass;
result.global_checks = globalChecks;
result.point_checks = pointChecks;
result.workbook = xlsxPath;
result.markdown = markdownPath;
result.latest = latestPaths;

fprintf('acceptance pass: %d\n', overallPass);
fprintf('workbook %s\n', xlsxPath);
fprintf('latest html %s\n', latestPaths.html);
disp(globalChecks);
disp(pointChecks(:, {'PointID','KeepPct','KeepDeltaPct','RMS30MaxReductionPct','Pass','Reason'}));
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

function value = reasonIf(condition, text)
if condition
    value = string(text);
else
    value = strings(0, 1);
end
end

function writeMarkdown(path, runName, overallPass, globalChecks, pointChecks, ...
        minKeepPct, minRmsReductionPct, maxKeepLossPct, boardPath, policyPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Display Acceptance\n\n');
fprintf(fid, '- Run: `%s`\n', runName);
fprintf(fid, '- Overall pass: `%d`\n', overallPass);
fprintf(fid, '- Minimum keep: `%.1f%%`\n', minKeepPct);
fprintf(fid, '- Minimum RMS30 max reduction: `%.1f%%`\n', minRmsReductionPct);
fprintf(fid, '- Maximum keep loss: `%.1f%%`\n', maxKeepLossPct);
fprintf(fid, '- Review board: `%s`\n', localFileName(boardPath));
fprintf(fid, '- Policy JSON: `%s`\n\n', localFileName(policyPath));
fprintf(fid, '| Global check | Pass |\n|---|---:|\n');
for i = 1:height(globalChecks)
    fprintf(fid, '| %s | %d |\n', globalChecks.Check{i}, globalChecks.Pass(i));
end
fprintf(fid, '\n| Point | Keep %% | Keep delta %% | RMS30 max reduction %% | Pass | Reason |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---|\n');
for i = 1:height(pointChecks)
    fprintf(fid, '| %s | %.3f | %.3f | %.1f | %d | %s |\n', ...
        pointChecks.PointID{i}, pointChecks.KeepPct(i), pointChecks.KeepDeltaPct(i), ...
        pointChecks.RMS30MaxReductionPct(i), pointChecks.Pass(i), pointChecks.Reason{i});
end
end

function latestPaths = writeLatest(dataRoot, runName, overallPass, xlsxPath, markdownPath, ...
        globalChecks, pointChecks, boardPath, policyPath)
runLogs = fullfile(dataRoot, 'run_logs');
latestPaths = struct( ...
    'json', fullfile(runLogs, 'cable_accel_display_acceptance_latest.json'), ...
    'markdown', fullfile(runLogs, 'cable_accel_display_acceptance_latest.md'), ...
    'html', fullfile(runLogs, 'cable_accel_display_acceptance_latest.html'));
pointer = struct();
pointer.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
pointer.run_name = runName;
pointer.pass = overallPass;
pointer.workbook = relPath(xlsxPath, dataRoot);
pointer.summary = relPath(markdownPath, dataRoot);
pointer.review_board = relPath(boardPath, dataRoot);
pointer.policy_json = relPath(policyPath, dataRoot);
pointer.review_html = relPath(latestPaths.html, dataRoot);

fid = fopen(latestPaths.json, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(pointer));
clear cleaner;

fid = fopen(latestPaths.markdown, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Latest Zhishan Cable Acceleration Display Acceptance\n\n');
fprintf(fid, '- Generated: %s\n', pointer.generated_at);
fprintf(fid, '- Overall pass: `%d`\n', overallPass);
fprintf(fid, '- Workbook: `%s`\n', pointer.workbook);
fprintf(fid, '- Review HTML: `%s`\n', pointer.review_html);
fprintf(fid, '- Review board: `%s`\n\n', localFileName(pointer.review_board));
fprintf(fid, '| Point | Keep %% | Keep delta %% | RMS30 max reduction %% | Pass |\n');
fprintf(fid, '|---|---:|---:|---:|---:|\n');
for i = 1:height(pointChecks)
    fprintf(fid, '| %s | %.3f | %.3f | %.1f | %d |\n', ...
        pointChecks.PointID{i}, pointChecks.KeepPct(i), pointChecks.KeepDeltaPct(i), ...
        pointChecks.RMS30MaxReductionPct(i), pointChecks.Pass(i));
end
clear cleaner;

writeLatestHtml(latestPaths.html, pointer, globalChecks, pointChecks);
end

function writeLatestHtml(path, pointer, globalChecks, pointChecks)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Display Acceptance</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;} .pass{color:#067a46;font-weight:700;} .fail{color:#b42318;font-weight:700;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
cls = 'fail';
if pointer.pass
    cls = 'pass';
end
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#25512;&#33616;&#26041;&#26696;&#39564;&#25910; / Display Acceptance</h1>\n');
fprintf(fid, '<p>Generated: %s<br>Overall pass: <span class="%s">%d</span><br>Workbook: <a href="%s">%s</a></p>\n', ...
    htmlText(pointer.generated_at), cls, pointer.pass, htmlPath(pointer.workbook), htmlText(pointer.workbook));
fprintf(fid, '<h2>&#20840;&#23616;&#26816;&#26597; / Global Checks</h2><table><tr><th>Check</th><th>Pass</th></tr>\n');
for i = 1:height(globalChecks)
    fprintf(fid, '<tr><td>%s</td><td class="num">%d</td></tr>\n', htmlText(globalChecks.Check{i}), globalChecks.Pass(i));
end
fprintf(fid, '</table>\n<h2>&#27979;&#28857;&#26816;&#26597; / Point Checks</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Keep %%</th><th>Keep delta %%</th><th>RMS30 reduction %%</th><th>Pass</th><th>Reason</th></tr>\n');
for i = 1:height(pointChecks)
    fprintf(fid, '<tr><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%d</td><td>%s</td></tr>\n', ...
        htmlText(pointChecks.PointID{i}), pointChecks.KeepPct(i), pointChecks.KeepDeltaPct(i), ...
        pointChecks.RMS30MaxReductionPct(i), pointChecks.Pass(i), htmlText(pointChecks.Reason{i}));
end
fprintf(fid, '</table>\n<h2>&#25512;&#33616;&#23637;&#31034;&#24635;&#35272; / Recommended Display Board</h2>\n');
fprintf(fid, '<div class="figure"><img src="%s" alt="review board"></div>\n', htmlPath(pointer.review_board));
fprintf(fid, '</body>\n</html>\n');
end

function out = htmlPath(pathText)
out = char(pathText);
prefix = ['run_logs' filesep];
if startsWith(out, prefix)
    out = out(numel(prefix)+1:end);
elseif startsWith(out, ['report_' filesep]) || startsWith(out, 'report_') || startsWith(out, [char([26102 31243 26354 32447]) '_'])
    out = fullfile('..', out);
end
out = strrep(out, '\', '/');
out = htmlText(out);
end

function out = htmlText(value)
out = char(string(value));
out = strrep(out, '&', '&amp;');
out = strrep(out, '<', '&lt;');
out = strrep(out, '>', '&gt;');
out = strrep(out, '"', '&quot;');
end

function rel = relPath(pathText, rootText)
pathText = char(pathText);
rootText = char(rootText);
prefix = [rootText filesep];
if startsWith(pathText, prefix)
    rel = pathText(numel(prefix)+1:end);
else
    rel = pathText;
end
end

function name = localFileName(pathText)
[~, base, ext] = fileparts(char(pathText));
name = [base ext];
end
