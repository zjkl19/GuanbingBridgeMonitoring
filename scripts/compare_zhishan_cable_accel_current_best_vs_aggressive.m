function result = compare_zhishan_cable_accel_current_best_vs_aggressive()
%COMPARE_ZHISHAN_CABLE_ACCEL_CURRENT_BEST_VS_AGGRESSIVE Side-by-side review.
%   Compares the accepted current-best display with the aggressive display
%   tier. This is display/report review only; formal spectrum/force
%   calculation is not modified.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
currentDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([24403 21069 26368 20339 25512 33616 23637 31034])]);
aggressiveDir = fullfile(stableDir, 'aggressive_display_export');
outputDir = fullfile(stableDir, 'current_best_vs_aggressive_review');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

current = readtable(fullfile(currentDir, ...
    'CableAccelCurrentBestReport_manifest.csv'), 'Encoding', 'UTF-8');
aggressive = readtable(fullfile(aggressiveDir, ...
    'CableAccelAggressiveDisplay_manifest.csv'), 'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    cIdx = find(strcmp(current.PointID, pointId), 1);
    aIdx = find(strcmp(aggressive.PointID, pointId), 1);
    if isempty(cIdx) || isempty(aIdx)
        error('Missing current-best or aggressive manifest row for %s.', pointId);
    end

    currentImage = fullfile(currentDir, sprintf( ...
        'CableAccelCurrentBestReport_%s_20260301_20260331.jpg', pointId));
    aggressiveImage = fullfile(aggressiveDir, sprintf( ...
        'CableAccelAggressiveDisplay_%s_20260301_20260331.jpg', pointId));
    plotPaths{i} = plotPair(outputDir, pointId, currentImage, aggressiveImage, ...
        current(cIdx, :), aggressive(aIdx, :));

    keepDelta = aggressive.KeepPct(aIdx) - current.KeepPct(cIdx);
    rmsMaxImprovement = pctReduction(current.RMS30Max(cIdx), aggressive.RMS30Max(aIdx));
    rmsP95Improvement = pctReduction(current.RMS30P95(cIdx), aggressive.RMS30P95(aIdx));
    rows(end+1, :) = {pointId, strategyText(current(cIdx, :)), ...
        aggressive.Strategy{aIdx}, current.KeepPct(cIdx), aggressive.KeepPct(aIdx), ...
        keepDelta, current.RMS30Max(cIdx), aggressive.RMS30Max(aIdx), ...
        rmsMaxImprovement, current.RMS30P95(cIdx), aggressive.RMS30P95(aIdx), ...
        rmsP95Improvement, conclusionText(keepDelta, rmsMaxImprovement, rmsP95Improvement), ...
        plotPaths{i}}; %#ok<AGROW>
end

comparison = cell2table(rows, 'VariableNames', { ...
    'PointID','CurrentBestStrategy','AggressiveStrategy', ...
    'CurrentBestKeepPct','AggressiveKeepPct','KeepDeltaPct', ...
    'CurrentBestRMS30Max','AggressiveRMS30Max','RMS30MaxImprovementPct', ...
    'CurrentBestRMS30P95','AggressiveRMS30P95','RMS30P95ImprovementPct', ...
    'Conclusion','PairImage'});

boardPath = buildReviewBoard(plotPaths, points, outputDir, ...
    'CableAccelCurrentBestVsAggressive_ReviewBoard.jpg');
manifestPath = fullfile(outputDir, 'CableAccelCurrentBestVsAggressive_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelCurrentBestVsAggressive_manifest.csv');
htmlPath = writeHtml(outputDir, comparison, plotPaths, points, boardPath);
readmePath = writeReadme(outputDir, comparison, boardPath, htmlPath);
writetable(comparison, manifestPath, 'Sheet', 'comparison');
writetable(comparison, manifestCsvPath, 'Encoding', 'UTF-8');

result = struct();
result.output_dir = outputDir;
result.manifest = manifestPath;
result.manifest_csv = manifestCsvPath;
result.html = htmlPath;
result.readme = readmePath;
result.review_board = boardPath;
result.pair_images = plotPaths;

fprintf('current-best vs aggressive dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('review board %s\n', boardPath);
fprintf('html %s\n', htmlPath);
disp(comparison(:, {'PointID','AggressiveKeepPct','KeepDeltaPct', ...
    'RMS30MaxImprovementPct','RMS30P95ImprovementPct','Conclusion'}));
end

function text = strategyText(row)
source = char(string(row.SelectedSource{1}));
text = sprintf('%s abs<=%g', source, row.ThresholdAbsMps2);
if row.SegmentFilterTopPctRMS30 > 0
    text = sprintf('%s + drop top %g%% RMS30 segments', ...
        text, row.SegmentFilterTopPctRMS30);
end
end

function path = plotPair(outputDir, pointId, currentImage, aggressiveImage, currentRow, aggressiveRow)
fig = figure('Visible', 'off', 'Position', [100 100 2200 850], 'Color', 'w');
tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

ax1 = nexttile;
drawImage(ax1, currentImage, 'current-best missing');
title(ax1, sprintf('current-best | keep %.2f%% | RMS max %.2f', ...
    currentRow.KeepPct, currentRow.RMS30Max), 'Interpreter', 'none');

ax2 = nexttile;
drawImage(ax2, aggressiveImage, 'aggressive missing');
title(ax2, sprintf('aggressive | keep %.2f%% | RMS max %.2f', ...
    aggressiveRow.KeepPct, aggressiveRow.RMS30Max), 'Interpreter', 'none');

sgtitle(fig, sprintf('%s current-best vs aggressive display', pointId), ...
    'Interpreter', 'none');
path = fullfile(outputDir, sprintf('CableAccelCurrentBestVsAggressive_%s.jpg', pointId));
exportgraphics(fig, path, 'Resolution', 145);
close(fig);
end

function drawImage(ax, path, missingLabel)
if isfile(path)
    image(ax, imread(path));
    axis(ax, 'image');
    axis(ax, 'off');
else
    axis(ax, 'off');
    text(ax, 0.5, 0.5, missingLabel, 'HorizontalAlignment', 'center', ...
        'Interpreter', 'none');
end
end

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 2200 2400], 'Color', 'w');
tiledlayout(fig, 4, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
for i = 1:numel(points)
    ax = nexttile;
    if isempty(plotPaths{i}) || ~isfile(plotPaths{i})
        axis(ax, 'off');
        text(ax, 0.5, 0.5, sprintf('%s missing', points{i}), ...
            'HorizontalAlignment', 'center', 'Interpreter', 'none');
    else
        image(ax, imread(plotPaths{i}));
        axis(ax, 'image');
        axis(ax, 'off');
        title(ax, points{i}, 'Interpreter', 'none');
    end
end
boardPath = fullfile(outputDir, fileName);
exportgraphics(fig, boardPath, 'Resolution', 140);
close(fig);
end

function htmlPath = writeHtml(outputDir, comparison, plotPaths, points, boardPath)
htmlPath = fullfile(outputDir, 'index.html');
fid = fopen(htmlPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Current-Best vs Aggressive</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #b45309;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.big{background:#eaf7f2}.medium{background:#fff7ed}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;}');
fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(760px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Current-Best vs Aggressive</h1>\n');
fprintf(fid, '<div class="note">Display-only comparison. Aggressive keeps less data but usually makes the report chart cleaner. Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.</div>\n');
fprintf(fid, '<h2>Delta Table</h2>\n<table>\n');
fprintf(fid, '<tr><th>Point</th><th>Aggressive strategy</th><th>Current-best keep %%</th><th>Aggressive keep %%</th><th>Keep delta %%</th><th>RMS max improvement %%</th><th>RMS P95 improvement %%</th><th>Conclusion</th></tr>\n');
for i = 1:height(comparison)
    cls = 'medium';
    if comparison.RMS30MaxImprovementPct(i) >= 25 || comparison.RMS30P95ImprovementPct(i) >= 20
        cls = 'big';
    end
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        cls, htmlText(comparison.PointID{i}), htmlText(comparison.AggressiveStrategy{i}), ...
        comparison.CurrentBestKeepPct(i), comparison.AggressiveKeepPct(i), ...
        comparison.KeepDeltaPct(i), comparison.RMS30MaxImprovementPct(i), ...
        comparison.RMS30P95ImprovementPct(i), htmlText(comparison.Conclusion{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Review Board</h2>\n<div class="figure"><img src="%s" alt="review board"></div>\n', htmlText(localFileName(boardPath)));
fprintf(fid, '<h2>Per-Point Side By Side</h2>\n<div class="grid">\n');
for i = 1:numel(points)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(points{i}), htmlText(localFileName(plotPaths{i})), htmlText(points{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function readmePath = writeReadme(outputDir, comparison, boardPath, htmlPath)
readmePath = fullfile(outputDir, 'README.md');
fid = fopen(readmePath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Current-Best vs Aggressive\n\n');
fprintf(fid, '- Open `index.html` for the side-by-side review.\n');
fprintf(fid, '- Review board: `%s`\n', localFileName(boardPath));
fprintf(fid, '- Source HTML: `%s`\n\n', localFileName(htmlPath));
fprintf(fid, 'Formal spectrum/force calculation remains unchanged. This package is display-only.\n\n');
fprintf(fid, '| Point | Keep delta %% | RMS max improvement %% | RMS P95 improvement %% | Conclusion |\n');
fprintf(fid, '|---|---:|---:|---:|---|\n');
for i = 1:height(comparison)
    fprintf(fid, '| %s | %.3f | %.1f | %.1f | %s |\n', ...
        comparison.PointID{i}, comparison.KeepDeltaPct(i), ...
        comparison.RMS30MaxImprovementPct(i), comparison.RMS30P95ImprovementPct(i), ...
        comparison.Conclusion{i});
end
end

function text = conclusionText(keepDelta, rmsMaxImprovement, rmsP95Improvement)
if rmsMaxImprovement >= 25 || rmsP95Improvement >= 20
    text = 'aggressive materially improves display';
elseif rmsMaxImprovement >= 8 || rmsP95Improvement >= 8
    text = 'aggressive improves display';
elseif rmsMaxImprovement > 1 || rmsP95Improvement > 1
    text = 'aggressive slightly improves display';
else
    text = 'aggressive mostly preserves current result';
end
if keepDelta < -7.5
    text = [text '; high data-loss tradeoff'];
elseif keepDelta < -5
    text = [text '; moderate data-loss tradeoff'];
end
end

function pct = pctReduction(beforeValue, afterValue)
if ~isfinite(beforeValue) || beforeValue == 0 || ~isfinite(afterValue)
    pct = NaN;
else
    pct = 100 * (beforeValue - afterValue) / abs(beforeValue);
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
