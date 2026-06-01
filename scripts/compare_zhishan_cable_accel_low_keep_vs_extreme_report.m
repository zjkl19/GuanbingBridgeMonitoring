function result = compare_zhishan_cable_accel_low_keep_vs_extreme_report()
%COMPARE_ZHISHAN_CABLE_ACCEL_LOW_KEEP_VS_EXTREME_REPORT Compare final candidates.
%   Builds a self-contained review page comparing the low-keep auto report
%   images with the extreme fallback images. Display/review only.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
outputDir = fullfile(stableDir, 'low_keep_vs_extreme_report');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

lowKeepDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([20302 20445 30041 29575 33258 21160 25512 33616 23637 31034])]);
extremeDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26497 38480 24178 20928 22791 36873 23637 31034])]);

lowKeep = readtable(fullfile(lowKeepDir, ...
    'CableAccelLowKeepAutoReport_manifest.csv'), 'Encoding', 'UTF-8');
extreme = readtable(fullfile(extremeDir, ...
    'CableAccelExtremeFallbackReport_manifest.csv'), 'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

rows = {};
lowPaths = cell(numel(points), 1);
extremePaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    lowRow = rowFor(lowKeep, 'PointID', pointId);
    extremeRow = rowFor(extreme, 'PointID', pointId);

    lowDst = fullfile(outputDir, sprintf( ...
        'LowKeepAuto_%s_20260301_20260331.jpg', pointId));
    extremeDst = fullfile(outputDir, sprintf( ...
        'ExtremeFallback_%s_20260301_20260331.jpg', pointId));
    copyfile(lowRow.PlotPath{1}, lowDst, 'f');
    copyfile(extremeRow.PlotPath{1}, extremeDst, 'f');
    lowPaths{i} = lowDst;
    extremePaths{i} = extremeDst;

    keepLoss = lowRow.KeepPct(1) - extremeRow.KeepPct(1);
    rmsGain = pctReduction(lowRow.RMS30Max(1), extremeRow.RMS30Max(1));
    if abs(keepLoss) < 1e-9 && abs(rmsGain) < 1e-9
        recommendation = 'same_as_low_keep';
        reason = 'extreme fallback is identical to low-keep auto for this point';
    elseif rmsGain >= 25 && keepLoss <= 12
        recommendation = 'extreme_if_cleanliness_priority';
        reason = sprintf('extra RMS gain %.1f%% for %.1f%% keep loss', ...
            rmsGain, keepLoss);
    elseif rmsGain >= 30
        recommendation = 'review_extreme_tradeoff';
        reason = sprintf('large extra RMS gain %.1f%% but keep loss %.1f%% is also large', ...
            rmsGain, keepLoss);
    else
        recommendation = 'keep_low_keep_auto';
        reason = sprintf('extra RMS gain %.1f%% does not justify %.1f%% keep loss by default', ...
            rmsGain, keepLoss);
    end

    rows(end+1, :) = {pointId, ...
        lowRow.SelectedReviewTier{1}, lowRow.KeepPct(1), lowRow.RMS30Max(1), ...
        extremeRow.SelectedReviewTier{1}, extremeRow.KeepPct(1), ...
        extremeRow.RMS30Max(1), keepLoss, rmsGain, recommendation, reason, ...
        lowDst, extremeDst}; %#ok<AGROW>
end

decision = cell2table(rows, 'VariableNames', { ...
    'PointID','LowKeepTier','LowKeepKeepPct','LowKeepRMS30Max', ...
    'ExtremeTier','ExtremeKeepPct','ExtremeRMS30Max', ...
    'KeepLossPct','ExtraRMS30GainPct','Recommendation','Reason', ...
    'LowKeepPlotPath','ExtremePlotPath'});

boardPath = buildBoard(lowPaths, extremePaths, decision, outputDir);
decisionPath = fullfile(outputDir, 'CableAccelLowKeepVsExtreme_decision.xlsx');
decisionCsvPath = fullfile(outputDir, 'CableAccelLowKeepVsExtreme_decision.csv');
htmlPath = fullfile(outputDir, 'index.html');
readmePath = fullfile(outputDir, 'README.md');
writetable(decision, decisionPath, 'Sheet', 'decision');
writetable(decision, decisionCsvPath, 'Encoding', 'UTF-8');
writeHtml(htmlPath, decision, boardPath);
writeReadme(readmePath, decision, boardPath);

result = struct();
result.output_dir = outputDir;
result.decision = decisionPath;
result.decision_csv = decisionCsvPath;
result.html = htmlPath;
result.board = boardPath;
result.readme = readmePath;

fprintf('low-keep vs extreme review %s\n', htmlPath);
disp(decision(:, {'PointID','LowKeepTier','LowKeepKeepPct', ...
    'ExtremeTier','ExtremeKeepPct','KeepLossPct', ...
    'ExtraRMS30GainPct','Recommendation'}));
end

function r = rowFor(T, key, value)
idx = find(strcmp(T.(key), value), 1);
if isempty(idx)
    error('Missing row where %s=%s.', key, value);
end
r = T(idx, :);
end

function value = pctReduction(baseValue, newValue)
if abs(baseValue) < eps
    value = 0;
else
    value = 100 * (baseValue - newValue) / baseValue;
end
end

function outPath = buildBoard(lowPaths, extremePaths, decision, outputDir)
fig = figure('Visible', 'off', 'Position', [100 100 2400 3000], 'Color', 'w');
tiledlayout(fig, height(decision), 2, 'TileSpacing', 'compact', 'Padding', 'compact');
for i = 1:height(decision)
    ax1 = nexttile;
    image(ax1, imread(lowPaths{i}));
    axis(ax1, 'image');
    axis(ax1, 'off');
    title(ax1, sprintf('%s low-keep | keep %.1f%% | RMS30 %.2f', ...
        decision.PointID{i}, decision.LowKeepKeepPct(i), ...
        decision.LowKeepRMS30Max(i)), 'Interpreter', 'none');

    ax2 = nexttile;
    image(ax2, imread(extremePaths{i}));
    axis(ax2, 'image');
    axis(ax2, 'off');
    title(ax2, sprintf('%s extreme | keep %.1f%% | RMS gain %.1f%%', ...
        decision.PointID{i}, decision.ExtremeKeepPct(i), ...
        decision.ExtraRMS30GainPct(i)), 'Interpreter', 'none');
end
outPath = fullfile(outputDir, 'CableAccelLowKeepVsExtreme_Board.jpg');
exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function writeHtml(path, decision, boardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Low-Keep vs Extreme</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #7c2d12;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.same_as_low_keep{background:#f3f4f6}.keep_low_keep_auto{background:#dbeafe}.review_extreme_tradeoff{background:#fef3c7}.extreme_if_cleanliness_priority{background:#fee2e2}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Low-Keep vs Extreme</h1>\n');
fprintf(fid, '<div class="note">This page compares the low-keep auto report image set with the stricter extreme fallback. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>.</div>\n');
fprintf(fid, '<h2>Decision Table</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Low-keep tier</th><th>Low-keep keep %%</th><th>Low-keep RMS30</th><th>Extreme tier</th><th>Extreme keep %%</th><th>Extreme RMS30</th><th>Keep loss %%</th><th>Extra RMS30 gain %%</th><th>Recommendation</th><th>Reason</th></tr>\n');
for i = 1:height(decision)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td><td>%s</td></tr>\n', ...
        htmlText(decision.Recommendation{i}), htmlText(decision.PointID{i}), ...
        htmlText(decision.LowKeepTier{i}), decision.LowKeepKeepPct(i), ...
        decision.LowKeepRMS30Max(i), htmlText(decision.ExtremeTier{i}), ...
        decision.ExtremeKeepPct(i), decision.ExtremeRMS30Max(i), ...
        decision.KeepLossPct(i), decision.ExtraRMS30GainPct(i), ...
        htmlText(decision.Recommendation{i}), htmlText(decision.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Side-by-Side Board</h2><div class="figure"><img src="%s" alt="comparison board"></div>\n', ...
    htmlText(localFileName(boardPath)));
fprintf(fid, '<h2>Per-Point Images</h2><div class="grid">\n');
for i = 1:height(decision)
    fprintf(fid, '<div class="figure"><h2>%s low-keep auto</h2><img src="%s" alt="%s low-keep"></div>\n', ...
        htmlText(decision.PointID{i}), htmlText(localFileName(decision.LowKeepPlotPath{i})), ...
        htmlText(decision.PointID{i}));
    fprintf(fid, '<div class="figure"><h2>%s extreme fallback</h2><img src="%s" alt="%s extreme"></div>\n', ...
        htmlText(decision.PointID{i}), htmlText(localFileName(decision.ExtremePlotPath{i})), ...
        htmlText(decision.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function writeReadme(path, decision, boardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Low-Keep vs Extreme\n\n');
fprintf(fid, '- Open `index.html` for the review page.\n');
fprintf(fid, '- Decision table: `CableAccelLowKeepVsExtreme_decision.xlsx`\n');
fprintf(fid, '- Side-by-side board: `%s`\n\n', localFileName(boardPath));
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Low-keep keep %% | Extreme keep %% | Keep loss %% | Extra RMS30 gain %% | Recommendation |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---|\n');
for i = 1:height(decision)
    fprintf(fid, '| %s | %.3f | %.3f | %.3f | %.1f | %s |\n', ...
        decision.PointID{i}, decision.LowKeepKeepPct(i), ...
        decision.ExtremeKeepPct(i), decision.KeepLossPct(i), ...
        decision.ExtraRMS30GainPct(i), decision.Recommendation{i});
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
