function result = compare_zhishan_cable_accel_auto_visual_review()
%COMPARE_ZHISHAN_CABLE_ACCEL_AUTO_VISUAL_REVIEW Compare current auto pick.
%   Builds a display-only review page comparing the dense auto-visual pick
%   with refined55 and the latest +/-20 m/s^2 single-threshold preview.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
outputDir = fullfile(stableDir, 'auto_visual_review');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

autoVisualDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([33258 21160 35270 35273 25512 33616 23637 31034])]);
refined55Dir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28151 21512]) '55' char([25512 33616 23637 31034])]);
scoreMatrixPath = fullfile(stableDir, 'auto_visual_search', ...
    'CableAccelAutoVisualSearch_score_matrix.csv');
[previewDir, previewCsv] = findLatestThresholdPreview(dataRoot, 20);

autoVisual = readtable(fullfile(autoVisualDir, ...
    'CableAccelAutoVisualReport_manifest.csv'), 'Encoding', 'UTF-8');
refined55 = readtable(fullfile(refined55Dir, ...
    'CableAccelRefined55Report_manifest.csv'), 'Encoding', 'UTF-8');
threshold20 = readtable(previewCsv, 'Encoding', 'UTF-8');
scoreMatrix = readtable(scoreMatrixPath, 'Encoding', 'UTF-8');

points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
rows = {};
autoPaths = cell(numel(points), 1);
refinedPaths = cell(numel(points), 1);
threshold20Paths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    autoRow = rowFor(autoVisual, 'PointID', pointId);
    refinedRow = rowFor(refined55, 'PointID', pointId);
    threshold20Row = rowFor(threshold20, 'PointID', pointId);
    pointScores = scoreMatrix(strcmp(string(scoreMatrix.PointID), pointId), :);

    autoDst = fullfile(outputDir, sprintf( ...
        'AutoVisual_%s_20260301_20260331.jpg', pointId));
    refinedDst = fullfile(outputDir, sprintf( ...
        'Refined55_%s_20260301_20260331.jpg', pointId));
    threshold20Dst = fullfile(outputDir, sprintf( ...
        'ThresholdAbs20_%s_20260301_20260331.jpg', pointId));
    copyfile(asText(autoRow.PlotPath), autoDst, 'f');
    copyfile(asText(refinedRow.PlotPath), refinedDst, 'f');
    copyfile(asText(threshold20Row.PlotPath), threshold20Dst, 'f');
    autoPaths{i} = autoDst;
    refinedPaths{i} = refinedDst;
    threshold20Paths{i} = threshold20Dst;

    [bestEligible, bestAny] = findBestRows(pointScores, autoRow.AutoMinKeepPct(1));
    autoKeep = autoRow.KeepPct(1);
    autoRms = autoRow.RMS30Max(1);
    refinedKeep = refinedRow.KeepPct(1);
    refinedRms = refinedRow.RMS30Max(1);
    threshold20Keep = threshold20Row.KeepPct(1);
    threshold20Rms = threshold20Row.RMS30Max(1);

    autoGainVsRefined = pctReduction(refinedRms, autoRms);
    autoKeepDeltaVsRefined = autoKeep - refinedKeep;
    autoGainVsThreshold20 = pctReduction(threshold20Rms, autoRms);
    autoKeepDeltaVsThreshold20 = autoKeep - threshold20Keep;
    extraEligibleGain = pctReduction(autoRms, bestEligible.RMS30Max(1));
    extraEligibleKeepLoss = autoKeep - bestEligible.KeepPct(1);
    extraAnyGain = pctReduction(autoRms, bestAny.RMS30Max(1));
    extraAnyKeepLoss = autoKeep - bestAny.KeepPct(1);

    [diagnosis, reason] = diagnosePoint(autoRow.AutoClass{1}, ...
        autoRow.AutoMinKeepPct(1), autoKeep, extraEligibleGain, ...
        extraEligibleKeepLoss, extraAnyGain, extraAnyKeepLoss);

    rows(end+1, :) = {pointId, autoRow.AutoClass{1}, ...
        autoRow.AutoMinKeepPct(1), autoRow.ThresholdAbsMps2(1), ...
        autoRow.SegmentFilterTopPctRMS30(1), autoKeep, autoRms, ...
        refinedKeep, refinedRms, autoKeepDeltaVsRefined, ...
        autoGainVsRefined, threshold20Keep, threshold20Rms, ...
        autoKeepDeltaVsThreshold20, autoGainVsThreshold20, ...
        bestEligible.ThresholdAbsMps2(1), ...
        bestEligible.SegmentFilterTopPctRMS30(1), ...
        bestEligible.KeepPct(1), bestEligible.RMS30Max(1), ...
        extraEligibleKeepLoss, extraEligibleGain, ...
        bestAny.ThresholdAbsMps2(1), bestAny.SegmentFilterTopPctRMS30(1), ...
        bestAny.KeepPct(1), bestAny.RMS30Max(1), ...
        extraAnyKeepLoss, extraAnyGain, diagnosis, reason, ...
        autoDst, refinedDst, threshold20Dst}; %#ok<AGROW>
end

decision = cell2table(rows, 'VariableNames', { ...
    'PointID','AutoClass','AutoMinKeepPct','AutoThresholdAbsMps2', ...
    'AutoSegmentTopPctRMS30','AutoKeepPct','AutoRMS30Max', ...
    'Refined55KeepPct','Refined55RMS30Max','AutoKeepDeltaVsRefined55Pct', ...
    'AutoRMS30GainVsRefined55Pct','Threshold20KeepPct', ...
    'Threshold20RMS30Max','AutoKeepDeltaVsThreshold20Pct', ...
    'AutoRMS30GainVsThreshold20Pct','BestEligibleThresholdAbsMps2', ...
    'BestEligibleSegmentTopPctRMS30','BestEligibleKeepPct', ...
    'BestEligibleRMS30Max','ExtraEligibleKeepLossPct', ...
    'ExtraEligibleRMS30GainPct','BestAnyThresholdAbsMps2', ...
    'BestAnySegmentTopPctRMS30','BestAnyKeepPct','BestAnyRMS30Max', ...
    'ExtraAnyKeepLossPct','ExtraAnyRMS30GainPct','Diagnosis','Reason', ...
    'AutoVisualPlotPath','Refined55PlotPath','Threshold20PlotPath'});

boardPath = buildBoard(autoPaths, refinedPaths, threshold20Paths, decision, outputDir);
decisionXlsx = fullfile(outputDir, 'CableAccelAutoVisualReview_decision.xlsx');
decisionCsv = fullfile(outputDir, 'CableAccelAutoVisualReview_decision.csv');
summaryJson = fullfile(outputDir, 'CableAccelAutoVisualReview_summary.json');
htmlPath = fullfile(outputDir, 'index.html');
readmePath = fullfile(outputDir, 'README.md');
writetable(decision, decisionXlsx, 'Sheet', 'decision');
writetable(decision, decisionCsv, 'Encoding', 'UTF-8');
writeJson(summaryJson, decision, previewDir);
writeHtml(htmlPath, decision, boardPath, previewDir);
writeReadme(readmePath, decision, boardPath, previewDir);

result = struct();
result.output_dir = outputDir;
result.html = htmlPath;
result.board = boardPath;
result.decision = decisionXlsx;
result.decision_csv = decisionCsv;
result.summary_json = summaryJson;
result.preview_dir = previewDir;

fprintf('auto visual review %s\n', htmlPath);
disp(decision(:, {'PointID','AutoClass','AutoKeepPct','AutoRMS30Max', ...
    'AutoRMS30GainVsRefined55Pct','AutoRMS30GainVsThreshold20Pct', ...
    'ExtraEligibleRMS30GainPct','Diagnosis'}));
end

function [previewDir, previewCsv] = findLatestThresholdPreview(dataRoot, thresholdAbs)
runLogs = fullfile(dataRoot, 'run_logs');
safeThreshold = regexprep(sprintf('%.6g', thresholdAbs), '[^\w.-]', '_');
items = dir(fullfile(runLogs, sprintf( ...
    'cable_accel_threshold_preview_*_abs%s', safeThreshold)));
items = items([items.isdir]);
if isempty(items)
    error('No threshold preview folder found for abs%s under %s.', ...
        safeThreshold, runLogs);
end
[~, idx] = max([items.datenum]);
previewDir = fullfile(items(idx).folder, items(idx).name);
previewCsv = fullfile(previewDir, 'cable_accel_threshold_preview.csv');
if ~isfile(previewCsv)
    error('Missing threshold preview CSV: %s.', previewCsv);
end
end

function r = rowFor(T, key, value)
idx = find(strcmp(string(T.(key)), value), 1);
if isempty(idx)
    error('Missing row where %s=%s.', key, value);
end
r = T(idx, :);
end

function [bestEligible, bestAny] = findBestRows(pointScores, minKeepPct)
finiteRows = pointScores(isfinite(pointScores.RMS30Max) & ...
    isfinite(pointScores.KeepPct), :);
if isempty(finiteRows)
    error('No finite score rows for point.');
end
eligible = finiteRows(finiteRows.KeepPct >= minKeepPct, :);
if isempty(eligible)
    eligible = finiteRows;
end
[~, iEligible] = min(eligible.RMS30Max);
bestEligible = eligible(iEligible, :);
[~, iAny] = min(finiteRows.RMS30Max);
bestAny = finiteRows(iAny, :);
end

function [diagnosis, reason] = diagnosePoint(autoClass, minKeepPct, autoKeep, ...
        extraEligibleGain, extraEligibleKeepLoss, extraAnyGain, extraAnyKeepLoss)
if minKeepPct <= 50.5 && autoKeep <= minKeepPct + 0.25
    diagnosis = 'data_limited_at_floor';
    reason = 'selected point is already at the adaptive 50% keep floor; further cleaning mainly means deleting more data';
elseif extraEligibleGain < 3
    diagnosis = 'near_knee';
    reason = sprintf('best eligible alternative gains only %.1f%% RMS30, so the current pick is near the tradeoff knee', ...
        extraEligibleGain);
elseif extraEligibleGain >= 8 && extraEligibleKeepLoss <= 3
    diagnosis = 'can_tighten_low_cost';
    reason = sprintf('another eligible row gains %.1f%% RMS30 for only %.1f%% keep loss', ...
        extraEligibleGain, extraEligibleKeepLoss);
elseif extraAnyGain >= 15 && extraAnyKeepLoss >= 8
    diagnosis = 'destructive_only';
    reason = sprintf('cleaner rows exist, but they need %.1f%% keep loss for %.1f%% RMS30 gain', ...
        extraAnyKeepLoss, extraAnyGain);
else
    diagnosis = 'tradeoff_only';
    reason = sprintf('%s candidate has no obvious low-cost improvement; additional cleaning is a manual tradeoff', ...
        autoClass);
end
end

function value = pctReduction(baseValue, newValue)
if ~isfinite(baseValue) || ~isfinite(newValue) || abs(baseValue) < eps
    value = 0;
else
    value = 100 * (baseValue - newValue) / baseValue;
end
end

function text = asText(value)
if iscell(value)
    text = char(value{1});
elseif isstring(value)
    text = char(value(1));
else
    text = char(string(value));
end
end

function outPath = buildBoard(autoPaths, refinedPaths, threshold20Paths, decision, outputDir)
fig = figure('Visible', 'off', 'Position', [100 100 3600 3600], 'Color', 'w');
tiledlayout(fig, height(decision), 3, 'TileSpacing', 'compact', 'Padding', 'compact');
for i = 1:height(decision)
    ax1 = nexttile;
    image(ax1, imread(autoPaths{i}));
    axis(ax1, 'image');
    axis(ax1, 'off');
    title(ax1, sprintf('%s auto | keep %.1f%% | RMS30 %.2f', ...
        decision.PointID{i}, decision.AutoKeepPct(i), decision.AutoRMS30Max(i)), ...
        'Interpreter', 'none');

    ax2 = nexttile;
    image(ax2, imread(refinedPaths{i}));
    axis(ax2, 'image');
    axis(ax2, 'off');
    title(ax2, sprintf('refined55 | keep %.1f%% | auto gain %.1f%%', ...
        decision.Refined55KeepPct(i), ...
        decision.AutoRMS30GainVsRefined55Pct(i)), 'Interpreter', 'none');

    ax3 = nexttile;
    image(ax3, imread(threshold20Paths{i}));
    axis(ax3, 'image');
    axis(ax3, 'off');
    title(ax3, sprintf('+/-20 preview | keep %.1f%% | auto gain %.1f%%', ...
        decision.Threshold20KeepPct(i), ...
        decision.AutoRMS30GainVsThreshold20Pct(i)), 'Interpreter', 'none');
end
outPath = fullfile(outputDir, 'CableAccelAutoVisualReview_Board.jpg');
exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function writeJson(path, decision, previewDir)
data = struct();
data.scope = 'display_review_only';
data.formal_policy = 'daily_median + [-100,100] m/s^2';
data.threshold20_preview_dir = previewDir;
data.points = table2struct(decision);
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(data, 'PrettyPrint', true));
end

function writeHtml(path, decision, boardPath, previewDir)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Auto Visual Review</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #2563eb;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.near_knee{background:#e0f2fe}.data_limited_at_floor{background:#fef3c7}.destructive_only{background:#fee2e2}.tradeoff_only{background:#f3f4f6}.can_tighten_low_cost{background:#dcfce7}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Auto Visual Review</h1>\n');
fprintf(fid, '<div class="note">This page compares the current dense auto-visual candidate with refined55 and the latest +/-20 m/s^2 preview. It does not change formal calculation. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>.</div>\n');
fprintf(fid, '<div class="note">Latest +/-20 preview folder: <code>%s</code>.</div>\n', htmlText(previewDir));
fprintf(fid, '<h2>Decision Table</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Class</th><th>Auto rule</th><th>Auto keep %%</th><th>Auto RMS30</th><th>Auto gain vs refined55 %%</th><th>Auto gain vs +/-20 %%</th><th>Best eligible keep %%</th><th>Best eligible RMS30</th><th>Extra eligible gain %%</th><th>Diagnosis</th><th>Reason</th></tr>\n');
for i = 1:height(decision)
    rule = sprintf('abs&lt;=%.3g, drop %.3g%%', ...
        decision.AutoThresholdAbsMps2(i), decision.AutoSegmentTopPctRMS30(i));
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%.1f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td><td>%s</td></tr>\n', ...
        htmlText(decision.Diagnosis{i}), htmlText(decision.PointID{i}), ...
        htmlText(decision.AutoClass{i}), rule, decision.AutoKeepPct(i), ...
        decision.AutoRMS30Max(i), decision.AutoRMS30GainVsRefined55Pct(i), ...
        decision.AutoRMS30GainVsThreshold20Pct(i), ...
        decision.BestEligibleKeepPct(i), decision.BestEligibleRMS30Max(i), ...
        decision.ExtraEligibleRMS30GainPct(i), htmlText(decision.Diagnosis{i}), ...
        htmlText(decision.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Three-Way Board</h2><div class="figure"><img src="%s" alt="auto visual review board"></div>\n', ...
    htmlText(localFileName(boardPath)));
fprintf(fid, '<h2>Per-Point Images</h2><div class="grid">\n');
for i = 1:height(decision)
    fprintf(fid, '<div class="figure"><h2>%s auto visual</h2><img src="%s" alt="%s auto visual"></div>\n', ...
        htmlText(decision.PointID{i}), htmlText(localFileName(decision.AutoVisualPlotPath{i})), htmlText(decision.PointID{i}));
    fprintf(fid, '<div class="figure"><h2>%s refined55</h2><img src="%s" alt="%s refined55"></div>\n', ...
        htmlText(decision.PointID{i}), htmlText(localFileName(decision.Refined55PlotPath{i})), htmlText(decision.PointID{i}));
    fprintf(fid, '<div class="figure"><h2>%s +/-20 preview</h2><img src="%s" alt="%s threshold20"></div>\n', ...
        htmlText(decision.PointID{i}), htmlText(localFileName(decision.Threshold20PlotPath{i})), htmlText(decision.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function writeReadme(path, decision, boardPath, previewDir)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Auto Visual Review\n\n');
fprintf(fid, '- Open `index.html` for the review page.\n');
fprintf(fid, '- Decision table: `CableAccelAutoVisualReview_decision.xlsx`\n');
fprintf(fid, '- Side-by-side board: `%s`\n', localFileName(boardPath));
fprintf(fid, '- Latest `+/-20` preview folder: `%s`\n\n', previewDir);
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Auto keep %% | Auto RMS30 | Gain vs refined55 %% | Gain vs +/-20 %% | Extra eligible gain %% | Diagnosis |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---|\n');
for i = 1:height(decision)
    fprintf(fid, '| %s | %.3f | %.3f | %.1f | %.1f | %.1f | %s |\n', ...
        decision.PointID{i}, decision.AutoKeepPct(i), ...
        decision.AutoRMS30Max(i), decision.AutoRMS30GainVsRefined55Pct(i), ...
        decision.AutoRMS30GainVsThreshold20Pct(i), ...
        decision.ExtraEligibleRMS30GainPct(i), decision.Diagnosis{i});
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
