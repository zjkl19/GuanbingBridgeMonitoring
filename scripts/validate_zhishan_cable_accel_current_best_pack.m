function result = validate_zhishan_cable_accel_current_best_pack()
%VALIDATE_ZHISHAN_CABLE_ACCEL_CURRENT_BEST_PACK Acceptance gate.
%   Validates that current-best rules, report images, and review entries are
%   consistent. Display-only; formal calculation must remain unchanged.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
reportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([24403 21069 26368 20339 25512 33616 23637 31034])];
reportDir = fullfile(dataRoot, reportDirName);

points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
minKeepPct = 90.0;

currentRulesPath = fullfile(stableDir, 'CableAccelCurrentBestDisplay_rules.csv');
finalRulesPath = fullfile(stableDir, 'CableAccelFinalDisplay_rules.csv');
reportManifestPath = fullfile(reportDir, 'CableAccelCurrentBestReport_manifest.csv');
currentSummaryPath = fullfile(stableDir, 'CableAccelCurrentBestDisplay_summary.json');
finalSummaryPath = fullfile(stableDir, 'CableAccelFinalDisplay_summary.json');
autoKneeAcceptancePath = fullfile(stableDir, 'auto_knee_display_pick', ...
    'CableAccelAutoKnee_acceptance.json');

currentRules = readtable(currentRulesPath, 'Encoding', 'UTF-8');
finalRules = readtable(finalRulesPath, 'Encoding', 'UTF-8');
reportManifest = readtable(reportManifestPath, 'Encoding', 'UTF-8');
currentSummary = readJson(currentSummaryPath);
finalSummary = readJson(finalSummaryPath);
autoKneeAcceptance = readJson(autoKneeAcceptancePath);
cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));

pointRows = {};
for i = 1:numel(points)
    pointId = points{i};
    cIdx = find(strcmp(currentRules.PointID, pointId), 1);
    fIdx = find(strcmp(finalRules.PointID, pointId), 1);
    rIdx = find(strcmp(reportManifest.PointID, pointId), 1);
    if isempty(cIdx) || isempty(fIdx) || isempty(rIdx)
        pointRows(end+1, :) = {pointId, '', NaN, NaN, false, false, false, ...
            false, false, false, false, 'missing point row'}; %#ok<AGROW>
        continue;
    end

    selectedSource = currentRules.SelectedSource{cIdx};
    sourceOk = any(strcmp(selectedSource, {'auto_knee','balanced_final'}));
    keepOk = isfinite(currentRules.KeepPct(cIdx)) && currentRules.KeepPct(cIdx) >= minKeepPct;
    passOk = logical(currentRules.AcceptancePass(cIdx)) && ...
        logical(finalRules.AcceptancePass(fIdx)) && logical(reportManifest.AcceptancePass(rIdx));
    finalRulesMatch = sameRuleRow(currentRules, cIdx, finalRules, fIdx);
    reportRulesMatch = sameReportRow(currentRules, cIdx, reportManifest, rIdx);
    imagePath = fullfile(reportDir, sprintf( ...
        'CableAccelCurrentBestReport_%s_20260301_20260331.jpg', pointId));
    imageOk = isfile(imagePath) && dirBytes(imagePath) > 10000;
    rowOk = sourceOk && keepOk && passOk && finalRulesMatch && reportRulesMatch && imageOk;
    reason = 'ok';
    if ~rowOk
        parts = {};
        if ~sourceOk, parts{end+1} = 'invalid selected source'; end %#ok<AGROW>
        if ~keepOk, parts{end+1} = 'keep below target'; end %#ok<AGROW>
        if ~passOk, parts{end+1} = 'acceptance flag failed'; end %#ok<AGROW>
        if ~finalRulesMatch, parts{end+1} = 'final rules mismatch'; end %#ok<AGROW>
        if ~reportRulesMatch, parts{end+1} = 'report manifest mismatch'; end %#ok<AGROW>
        if ~imageOk, parts{end+1} = 'missing/small report image'; end %#ok<AGROW>
        reason = strjoin(parts, '; ');
    end
    pointRows(end+1, :) = {pointId, selectedSource, currentRules.KeepPct(cIdx), ...
        currentRules.RMS30Max(cIdx), currentRules.RMS30MaxImprovementPct(cIdx), ...
        sourceOk, keepOk, passOk, finalRulesMatch, reportRulesMatch, imageOk, ...
        rowOk, reason}; %#ok<AGROW>
end

pointChecks = cell2table(pointRows, 'VariableNames', { ...
    'PointID','SelectedSource','KeepPct','RMS30Max','RMS30MaxImprovementPct', ...
    'SourceOK','KeepOK','AcceptanceFlagOK','FinalRulesMatch', ...
    'ReportManifestMatch','ReportImageOK','Pass','Reason'});

formalConfigOk = hasFormalCableAccelPolicy(cfg);
summaryOk = isfield(currentSummary, 'acceptance_pass') && logical(currentSummary.acceptance_pass) && ...
    isfield(currentSummary, 'current_best_policy') && ...
    strcmp(currentSummary.current_best_policy, 'Accepted auto-knee candidate') && ...
    isfield(finalSummary, 'current_best_entry') && ...
    strcmp(finalSummary.current_best_entry, 'current_best_index.html') && ...
    isfield(finalSummary, 'acceptance_pass') && logical(finalSummary.acceptance_pass);
autoKneeAcceptanceOk = isfield(autoKneeAcceptance, 'pass') && logical(autoKneeAcceptance.pass);
pointCountOk = height(currentRules) == 8 && height(finalRules) == 8 && height(reportManifest) == 8;
compositionOk = nnz(strcmp(pointChecks.SelectedSource, 'auto_knee')) == 3 && ...
    nnz(strcmp(pointChecks.SelectedSource, 'balanced_final')) == 5;
allPointsOk = all(pointChecks.Pass);
filesOk = requiredFilesExist(stableDir, reportDir);
[linkRows, linksOk] = checkLinkedPages(stableDir, reportDir);
overallPass = formalConfigOk && summaryOk && autoKneeAcceptanceOk && pointCountOk && ...
    compositionOk && allPointsOk && filesOk && linksOk;

globalChecks = table( ...
    {'formal_config_daily_median_abs100'; 'summary_current_best_ok'; ...
     'auto_knee_acceptance_ok'; 'all_manifests_8_points'; ...
     'three_auto_knee_five_balanced'; 'all_point_checks'; ...
     'required_files_exist'; 'html_links_and_images_ok'}, ...
    [formalConfigOk; summaryOk; autoKneeAcceptanceOk; pointCountOk; ...
     compositionOk; allPointsOk; filesOk; linksOk], ...
    'VariableNames', {'Check','Pass'});

acceptanceXlsx = fullfile(stableDir, 'CableAccelCurrentBestDisplay_acceptance.xlsx');
acceptanceJson = fullfile(stableDir, 'CableAccelCurrentBestDisplay_acceptance.json');
acceptanceHtml = fullfile(stableDir, 'current_best_acceptance.html');
acceptanceMd = fullfile(stableDir, 'CableAccelCurrentBestDisplay_acceptance.md');
writetable(globalChecks, acceptanceXlsx, 'Sheet', 'global_checks');
writetable(pointChecks, acceptanceXlsx, 'Sheet', 'point_checks');
writetable(linkRows, acceptanceXlsx, 'Sheet', 'page_checks');
writeJson(acceptanceJson, overallPass, globalChecks, pointChecks, linkRows, minKeepPct);
writeMarkdown(acceptanceMd, overallPass, globalChecks, pointChecks, linkRows, minKeepPct);
writeHtml(acceptanceHtml, overallPass, globalChecks, pointChecks, linkRows, minKeepPct, ...
    fullfile(reportDir, 'CableAccelCurrentBestReport_ContactSheet.jpg'));

result = struct();
result.pass = overallPass;
result.global_checks = globalChecks;
result.point_checks = pointChecks;
result.page_checks = linkRows;
result.workbook = acceptanceXlsx;
result.json = acceptanceJson;
result.markdown = acceptanceMd;
result.html = acceptanceHtml;

fprintf('current-best acceptance pass: %d\n', overallPass);
fprintf('workbook %s\n', acceptanceXlsx);
fprintf('html %s\n', acceptanceHtml);
disp(globalChecks);
disp(pointChecks(:, {'PointID','SelectedSource','KeepPct','RMS30MaxImprovementPct','Pass','Reason'}));
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

function ok = sameRuleRow(a, ai, b, bi)
ok = strcmp(a.SelectedSource{ai}, b.SelectedSource{bi}) && ...
    numericClose(a.ThresholdAbsMps2(ai), b.ThresholdAbsMps2(bi)) && ...
    numericClose(a.SegmentFilterTopPctRMS30(ai), b.SegmentFilterTopPctRMS30(bi)) && ...
    numericClose(a.KeepPct(ai), b.KeepPct(bi)) && ...
    numericClose(a.RMS30Max(ai), b.RMS30Max(bi));
end

function ok = sameReportRow(rules, ri, report, mi)
ok = strcmp(rules.SelectedSource{ri}, report.SelectedSource{mi}) && ...
    numericClose(rules.ThresholdAbsMps2(ri), report.ThresholdAbsMps2(mi)) && ...
    numericClose(rules.SegmentFilterTopPctRMS30(ri), report.SegmentFilterTopPctRMS30(mi)) && ...
    numericClose(rules.KeepPct(ri), report.KeepPct(mi)) && ...
    numericClose(rules.RMS30Max(ri), report.RMS30Max(mi));
end

function ok = numericClose(a, b)
ok = isfinite(a) && isfinite(b) && abs(a - b) <= max(1e-6, 1e-9 * max(abs(a), abs(b)));
end

function ok = requiredFilesExist(stableDir, reportDir)
paths = { ...
    fullfile(stableDir, 'current_best_index.html'), ...
    fullfile(stableDir, 'final_index.html'), ...
    fullfile(stableDir, 'index.html'), ...
    fullfile(stableDir, 'CableAccelCurrentBestDisplay_rules.xlsx'), ...
    fullfile(stableDir, 'CableAccelCurrentBestDisplay_rules.csv'), ...
    fullfile(stableDir, 'CableAccelFinalDisplay_rules.xlsx'), ...
    fullfile(stableDir, 'CableAccelFinalDisplay_rules.csv'), ...
    fullfile(stableDir, 'CableAccelCurrentBestDisplay_summary.json'), ...
    fullfile(stableDir, 'CableAccelFinalDisplay_summary.json'), ...
    fullfile(reportDir, 'index.html'), ...
    fullfile(reportDir, 'CableAccelCurrentBestReport_manifest.xlsx'), ...
    fullfile(reportDir, 'CableAccelCurrentBestReport_manifest.csv'), ...
    fullfile(reportDir, 'CableAccelCurrentBestReport_ContactSheet.jpg')};
ok = all(cellfun(@(p) isfile(p) && dirBytes(p) > 0, paths));
end

function [rows, ok] = checkLinkedPages(stableDir, reportDir)
pages = { ...
    fullfile(stableDir, 'current_best_index.html'), ...
    fullfile(stableDir, 'final_index.html'), ...
    fullfile(stableDir, 'index.html'), ...
    fullfile(reportDir, 'index.html')};
rowData = {};
ok = true;
for i = 1:numel(pages)
    page = pages{i};
    [imageRefs, missingImages, hrefs, missingHrefs] = checkPage(page);
    pass = missingImages == 0 && missingHrefs == 0;
    ok = ok && pass;
    rowData(end+1, :) = {page, imageRefs, missingImages, hrefs, missingHrefs, pass}; %#ok<AGROW>
end
rows = cell2table(rowData, 'VariableNames', { ...
    'Page','ImageRefs','MissingImages','HrefRefs','MissingHrefs','Pass'});
end

function [imageRefs, missingImages, hrefRefs, missingHrefs] = checkPage(page)
text = fileread(page);
baseDir = fileparts(page);
imgTokens = regexp(text, '<img[^>]+src="([^"]+)"', 'tokens');
hrefTokens = regexp(text, 'href="([^"]+)"', 'tokens');
imageRefs = numel(imgTokens);
hrefRefs = 0;
missingImages = 0;
missingHrefs = 0;
for i = 1:numel(imgTokens)
    if ~localTargetExists(baseDir, imgTokens{i}{1})
        missingImages = missingImages + 1;
    end
end
for i = 1:numel(hrefTokens)
    href = hrefTokens{i}{1};
    if startsWith(href, 'http:') || startsWith(href, 'https:') || ...
            startsWith(href, 'mailto:') || startsWith(href, '#')
        continue;
    end
    hrefRefs = hrefRefs + 1;
    if ~localTargetExists(baseDir, href)
        missingHrefs = missingHrefs + 1;
    end
end
end

function ok = localTargetExists(baseDir, rel)
rel = strrep(rel, '/', filesep);
target = char(java.io.File(baseDir, rel).getCanonicalPath());
ok = exist(target, 'file') == 2 || exist(target, 'dir') == 7;
end

function writeJson(path, overallPass, globalChecks, pointChecks, pageChecks, minKeepPct)
data = struct();
data.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
data.pass = overallPass;
data.min_keep_pct = minKeepPct;
data.global_checks = table2struct(globalChecks);
data.point_checks = table2struct(pointChecks);
data.page_checks = table2struct(pageChecks);
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(data));
end

function writeMarkdown(path, overallPass, globalChecks, pointChecks, pageChecks, minKeepPct)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Current-Best Acceptance\n\n');
fprintf(fid, '- Overall pass: `%d`\n', overallPass);
fprintf(fid, '- Minimum keep: `%.1f%%`\n\n', minKeepPct);
fprintf(fid, '| Global check | Pass |\n|---|---:|\n');
for i = 1:height(globalChecks)
    fprintf(fid, '| %s | %d |\n', globalChecks.Check{i}, globalChecks.Pass(i));
end
fprintf(fid, '\n| Point | Source | Keep %% | RMS30 improvement %% | Pass | Reason |\n');
fprintf(fid, '|---|---|---:|---:|---:|---|\n');
for i = 1:height(pointChecks)
    fprintf(fid, '| %s | %s | %.3f | %.1f | %d | %s |\n', ...
        pointChecks.PointID{i}, pointChecks.SelectedSource{i}, ...
        pointChecks.KeepPct(i), pointChecks.RMS30MaxImprovementPct(i), ...
        pointChecks.Pass(i), pointChecks.Reason{i});
end
fprintf(fid, '\n| Page | Image refs | Missing images | Hrefs | Missing hrefs | Pass |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|\n');
for i = 1:height(pageChecks)
    fprintf(fid, '| %s | %d | %d | %d | %d | %d |\n', pageChecks.Page{i}, ...
        pageChecks.ImageRefs(i), pageChecks.MissingImages(i), ...
        pageChecks.HrefRefs(i), pageChecks.MissingHrefs(i), pageChecks.Pass(i));
end
end

function writeHtml(path, overallPass, globalChecks, pointChecks, pageChecks, minKeepPct, contactSheetPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Current-Best Acceptance</title>\n');
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
fprintf(fid, '<h1>Zhishan Cable Acceleration Current-Best Acceptance</h1>\n');
fprintf(fid, '<p>Overall pass: <span class="%s">%d</span><br>Minimum keep: %.1f%%</p>\n', ...
    cls, overallPass, minKeepPct);
fprintf(fid, '<h2>Global Checks</h2><table><tr><th>Check</th><th>Pass</th></tr>\n');
for i = 1:height(globalChecks)
    fprintf(fid, '<tr><td>%s</td><td class="num">%d</td></tr>\n', htmlText(globalChecks.Check{i}), globalChecks.Pass(i));
end
fprintf(fid, '</table>\n<h2>Point Checks</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Source</th><th>Keep %%</th><th>RMS30 improvement %%</th><th>Pass</th><th>Reason</th></tr>\n');
for i = 1:height(pointChecks)
    fprintf(fid, '<tr><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%d</td><td>%s</td></tr>\n', ...
        htmlText(pointChecks.PointID{i}), htmlText(pointChecks.SelectedSource{i}), ...
        pointChecks.KeepPct(i), pointChecks.RMS30MaxImprovementPct(i), ...
        pointChecks.Pass(i), htmlText(pointChecks.Reason{i}));
end
fprintf(fid, '</table>\n<h2>Page Checks</h2><table>\n');
fprintf(fid, '<tr><th>Page</th><th>Image refs</th><th>Missing images</th><th>Hrefs</th><th>Missing hrefs</th><th>Pass</th></tr>\n');
for i = 1:height(pageChecks)
    fprintf(fid, '<tr><td>%s</td><td class="num">%d</td><td class="num">%d</td><td class="num">%d</td><td class="num">%d</td><td class="num">%d</td></tr>\n', ...
        htmlText(pageChecks.Page{i}), pageChecks.ImageRefs(i), ...
        pageChecks.MissingImages(i), pageChecks.HrefRefs(i), ...
        pageChecks.MissingHrefs(i), pageChecks.Pass(i));
end
fprintf(fid, '</table>\n<h2>Contact Sheet</h2>\n');
fprintf(fid, '<div class="figure"><img src="../%s/%s" alt="contact sheet"></div>\n', ...
    htmlText(localFolderName(fileparts(contactSheetPath))), htmlText(localFileName(contactSheetPath)));
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

function name = localFolderName(pathText)
[~, name] = fileparts(char(pathText));
end
