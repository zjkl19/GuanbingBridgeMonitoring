function result = build_zhishan_cable_accel_hybrid_recommended_parameters()
%BUILD_ZHISHAN_CABLE_ACCEL_HYBRID_RECOMMENDED_PARAMETERS Export parameters.
%   Builds a structured, reproducible parameter proposal for the hybrid
%   cable-acceleration display candidate. This does not modify formal config.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
outputDir = fullfile(stableDir, 'hybrid_recommended_parameters');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

hybridDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28151 21512 25512 33616 23637 31034])]);
hybrid = readtable(fullfile(hybridDir, ...
    'CableAccelHybridRecommendedReport_manifest.csv'), 'Encoding', 'UTF-8');

cleanest60 = readtable(fullfile(stableDir, 'cleanest60_display_export', ...
    'CableAccelCleanest60Display_manifest.csv'), 'Encoding', 'UTF-8');
cleanest50 = readtable(fullfile(stableDir, 'cleanest50_display_export', ...
    'CableAccelCleanest50Display_manifest.csv'), 'Encoding', 'UTF-8');
satisfaction = readtable(fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28385 24847 24230 33258 21160 25512 33616 23637 31034])], ...
    'CableAccelSatisfactionAutoReport_manifest.csv'), 'Encoding', 'UTF-8');
decisive = readtable(fullfile(stableDir, 'decisive_visual_display_export', ...
    'CableAccelDecisiveVisualDisplay_manifest.csv'), 'Encoding', 'UTF-8');
cleanest70 = readtable(fullfile(stableDir, 'cleanest70_display_export', ...
    'CableAccelCleanest70Display_manifest.csv'), 'Encoding', 'UTF-8');

rows = {};
for i = 1:height(hybrid)
    h = hybrid(i, :);
    [sourceTableName, sourceRow] = resolveSourceRow(h, cleanest60, cleanest50, ...
        satisfaction, decisive, cleanest70);
    strategy = sourceRow.Strategy{1};
    absThreshold = parseNumber(strategy, 'abs<=([0-9.]+)');
    dropTopPct = parseNumber(strategy, 'drop top ([0-9.]+)%');
    rows(end+1, :) = {h.PointID{1}, h.SelectedPackage{1}, ...
        h.SelectedTier{1}, sourceTableName, sourceRow.SelectedTier{1}, ...
        strategy, absThreshold, dropTopPct, h.KeepPct(1), h.RMS30Max(1), ...
        h.LowKeepKeepPct(1), h.LowKeepRMS30Max(1), h.ExtremeKeepPct(1), ...
        h.ExtremeRMS30Max(1), h.KeepLossPct(1), h.ExtraRMS30GainPct(1), ...
        h.DecisionRecommendation{1}, h.Reason{1}, h.PlotPath{1}}; %#ok<AGROW>
end

parameters = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedPackage','SelectedTier','SourceManifest', ...
    'SourceTier','Strategy','DisplayAbsThresholdMps2', ...
    'DropTopPctRMS30Segments','KeepPct','RMS30Max', ...
    'LowKeepKeepPct','LowKeepRMS30Max','ExtremeKeepPct', ...
    'ExtremeRMS30Max','KeepLossPct','ExtraRMS30GainPct', ...
    'DecisionRecommendation','Reason','HybridPlotPath'});

xlsxPath = fullfile(outputDir, 'CableAccelHybridRecommended_parameters.xlsx');
csvPath = fullfile(outputDir, 'CableAccelHybridRecommended_parameters.csv');
jsonPath = fullfile(outputDir, 'CableAccelHybridRecommended_parameters.json');
htmlPath = fullfile(outputDir, 'index.html');
readmePath = fullfile(outputDir, 'README.md');
writetable(parameters, xlsxPath, 'Sheet', 'parameters');
writetable(parameters, csvPath, 'Encoding', 'UTF-8');
writeJson(jsonPath, parameters);
writeHtml(htmlPath, parameters, hybridDir);
writeReadme(readmePath, parameters);

result = struct();
result.output_dir = outputDir;
result.xlsx = xlsxPath;
result.csv = csvPath;
result.json = jsonPath;
result.html = htmlPath;
result.readme = readmePath;

fprintf('hybrid recommended parameters %s\n', htmlPath);
disp(parameters(:, {'PointID','SelectedPackage','SourceTier', ...
    'DisplayAbsThresholdMps2','DropTopPctRMS30Segments','KeepPct','RMS30Max'}));
end

function [sourceTableName, row] = resolveSourceRow(h, cleanest60, cleanest50, satisfaction, decisive, cleanest70)
pointId = h.PointID{1};
selectedTier = h.SelectedTier{1};
if strcmp(h.SelectedPackage{1}, 'extreme_fallback')
    sourceTableName = 'cleanest50_display_export';
    row = rowFor(cleanest50, pointId);
elseif strcmp(selectedTier, 'cleanest60')
    sourceTableName = 'cleanest60_display_export';
    row = rowFor(cleanest60, pointId);
elseif strcmp(selectedTier, 'satisfaction_auto')
    s = rowFor(satisfaction, pointId);
    sourceTier = s.SourceTier{1};
    if strcmp(sourceTier, 'target70')
        sourceTableName = 'cleanest70_display_export';
        row = rowFor(cleanest70, pointId);
    elseif strcmp(sourceTier, 'target75') || strcmp(sourceTier, 'visual_best')
        sourceTableName = 'decisive_visual_display_export';
        row = rowFor(decisive, pointId);
    elseif strcmp(sourceTier, 'target60')
        sourceTableName = 'cleanest60_display_export';
        row = rowFor(cleanest60, pointId);
    elseif strcmp(sourceTier, 'target50')
        sourceTableName = 'cleanest50_display_export';
        row = rowFor(cleanest50, pointId);
    else
        error('Unsupported satisfaction source tier %s for %s.', sourceTier, pointId);
    end
else
    error('Unsupported hybrid selected tier %s for %s.', selectedTier, pointId);
end
end

function r = rowFor(T, pointId)
idx = find(strcmp(T.PointID, pointId), 1);
if isempty(idx)
    error('Missing row for %s.', pointId);
end
r = T(idx, :);
end

function value = parseNumber(text, pattern)
token = regexp(text, pattern, 'tokens', 'once');
if isempty(token)
    value = NaN;
else
    value = str2double(token{1});
end
end

function writeJson(path, parameters)
payload = struct();
payload.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
payload.scope = 'display_report_review_only';
payload.formal_policy = 'Formal cable acceleration remains daily_median + [-100,100] m/s^2.';
payload.selection_rule = 'Use low-keep auto by default; switch only review_extreme_tradeoff points to extreme fallback.';
payload.parameters = table2struct(parameters);
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(payload, 'PrettyPrint', true));
end

function writeHtml(path, parameters, hybridDir)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
[~, hybridDirName] = fileparts(hybridDir);
hybridRel = ['../../' hybridDirName '/index.html'];
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Hybrid Recommended Parameters</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} .note{background:white;border-left:4px solid #2563eb;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.low_keep_auto{background:#dbeafe}.extreme_fallback{background:#fee2e2} a{color:#075da8;text-decoration:none;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Hybrid Recommended Parameters</h1>\n');
fprintf(fid, '<div class="note">Display/report-review parameter proposal only. Formal cable acceleration remains <code>daily_median + [-100,100] m/s^2</code>. Hybrid image set: <a href="%s">open images</a>.</div>\n', htmlText(hybridRel));
fprintf(fid, '<table><tr><th>Point</th><th>Package</th><th>Source tier</th><th>Strategy</th><th>|x| threshold</th><th>Drop top RMS30 %%</th><th>Keep %%</th><th>RMS30 max</th><th>Reason</th></tr>\n');
for i = 1:height(parameters)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td>%s</td></tr>\n', ...
        htmlText(parameters.SelectedPackage{i}), htmlText(parameters.PointID{i}), ...
        htmlText(parameters.SelectedPackage{i}), htmlText(parameters.SourceTier{i}), ...
        htmlText(parameters.Strategy{i}), parameters.DisplayAbsThresholdMps2(i), ...
        parameters.DropTopPctRMS30Segments(i), parameters.KeepPct(i), ...
        parameters.RMS30Max(i), htmlText(parameters.Reason{i}));
end
fprintf(fid, '</table>\n</body>\n</html>\n');
end

function writeReadme(path, parameters)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Hybrid Recommended Parameters\n\n');
fprintf(fid, '- Table: `CableAccelHybridRecommended_parameters.xlsx`\n');
fprintf(fid, '- JSON: `CableAccelHybridRecommended_parameters.json`\n');
fprintf(fid, '- Scope: display/report review only.\n');
fprintf(fid, '- Formal policy remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Package | Source tier | |x| threshold | Drop top RMS30 %% | Keep %% | RMS30 max |\n');
fprintf(fid, '|---|---|---|---:|---:|---:|---:|\n');
for i = 1:height(parameters)
    fprintf(fid, '| %s | %s | %s | %.3f | %.3f | %.3f | %.3f |\n', ...
        parameters.PointID{i}, parameters.SelectedPackage{i}, ...
        parameters.SourceTier{i}, parameters.DisplayAbsThresholdMps2(i), ...
        parameters.DropTopPctRMS30Segments(i), parameters.KeepPct(i), ...
        parameters.RMS30Max(i));
end
end

function out = htmlText(value)
out = char(string(value));
out = strrep(out, '&', '&amp;');
out = strrep(out, '<', '&lt;');
out = strrep(out, '>', '&gt;');
out = strrep(out, '"', '&quot;');
end
