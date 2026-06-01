function result = compare_zhishan_cable_accel_three_level_review()
%COMPARE_ZHISHAN_CABLE_ACCEL_THREE_LEVEL_REVIEW Three-tier visual review.
%   Compares current-best, aggressive, and target80 display exports in one
%   package. This is display/report review only; formal spectrum/force
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
target80Dir = fullfile(stableDir, 'target80_display_export');
outputDir = fullfile(stableDir, 'three_level_tradeoff_review');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

current = readtable(fullfile(currentDir, ...
    'CableAccelCurrentBestReport_manifest.csv'), 'Encoding', 'UTF-8');
aggressive = readtable(fullfile(aggressiveDir, ...
    'CableAccelAggressiveDisplay_manifest.csv'), 'Encoding', 'UTF-8');
target80 = readtable(fullfile(target80Dir, ...
    'CableAccelTarget80Display_manifest.csv'), 'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    cIdx = find(strcmp(current.PointID, pointId), 1);
    aIdx = find(strcmp(aggressive.PointID, pointId), 1);
    tIdx = find(strcmp(target80.PointID, pointId), 1);
    if isempty(cIdx) || isempty(aIdx) || isempty(tIdx)
        error('Missing manifest row for %s.', pointId);
    end

    currentImage = fullfile(currentDir, sprintf( ...
        'CableAccelCurrentBestReport_%s_20260301_20260331.jpg', pointId));
    aggressiveImage = fullfile(aggressiveDir, sprintf( ...
        'CableAccelAggressiveDisplay_%s_20260301_20260331.jpg', pointId));
    target80Image = fullfile(target80Dir, sprintf( ...
        'CableAccelTarget80Display_%s_20260301_20260331.jpg', pointId));
    tier = recommendTier(current(cIdx, :), aggressive(aIdx, :), target80(tIdx, :));
    plotPaths{i} = plotTriple(outputDir, pointId, currentImage, aggressiveImage, ...
        target80Image, current(cIdx, :), aggressive(aIdx, :), target80(tIdx, :), tier);

    aggrImprove = pctReduction(current.RMS30Max(cIdx), aggressive.RMS30Max(aIdx));
    targetImprove = pctReduction(current.RMS30Max(cIdx), target80.RMS30Max(tIdx));
    targetExtraImprove = pctReduction(aggressive.RMS30Max(aIdx), target80.RMS30Max(tIdx));
    rows(end+1, :) = {pointId, tier, current.KeepPct(cIdx), current.RMS30Max(cIdx), ...
        aggressive.KeepPct(aIdx), aggressive.RMS30Max(aIdx), aggrImprove, ...
        target80.KeepPct(tIdx), target80.RMS30Max(tIdx), targetImprove, ...
        targetExtraImprove, aggressive.KeepPct(aIdx) - current.KeepPct(cIdx), ...
        target80.KeepPct(tIdx) - current.KeepPct(cIdx), ...
        target80.KeepPct(tIdx) - aggressive.KeepPct(aIdx), ...
        decisionText(tier, aggrImprove, targetExtraImprove), plotPaths{i}}; %#ok<AGROW>
end

comparison = cell2table(rows, 'VariableNames', { ...
    'PointID','SuggestedTier','CurrentBestKeepPct','CurrentBestRMS30Max', ...
    'AggressiveKeepPct','AggressiveRMS30Max','AggressiveRMS30MaxImprovementPct', ...
    'Target80KeepPct','Target80RMS30Max','Target80RMS30MaxImprovementPct', ...
    'Target80ExtraImprovementVsAggressivePct', ...
    'AggressiveKeepDeltaVsCurrentPct','Target80KeepDeltaVsCurrentPct', ...
    'Target80KeepDeltaVsAggressivePct','Decision','TripleImage'});

boardPath = buildReviewBoard(plotPaths, points, outputDir, ...
    'CableAccelThreeLevelTradeoff_ReviewBoard.jpg');
manifestPath = fullfile(outputDir, 'CableAccelThreeLevelTradeoff_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelThreeLevelTradeoff_manifest.csv');
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
result.triple_images = plotPaths;

fprintf('three-level tradeoff dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('review board %s\n', boardPath);
fprintf('html %s\n', htmlPath);
disp(comparison(:, {'PointID','SuggestedTier','AggressiveRMS30MaxImprovementPct', ...
    'Target80RMS30MaxImprovementPct','Target80ExtraImprovementVsAggressivePct', ...
    'AggressiveKeepDeltaVsCurrentPct','Target80KeepDeltaVsCurrentPct'}));
end

function tier = recommendTier(currentRow, aggressiveRow, targetRow)
aggrImprove = pctReduction(currentRow.RMS30Max, aggressiveRow.RMS30Max);
targetImprove = pctReduction(currentRow.RMS30Max, targetRow.RMS30Max);
targetExtraImprove = pctReduction(aggressiveRow.RMS30Max, targetRow.RMS30Max);

if aggressiveRow.KeepPct >= 85 && aggrImprove >= 18
    tier = 'aggressive_first_backup';
else
    tier = 'current_best_default';
end

if targetRow.KeepPct >= 80 && targetImprove > aggrImprove && targetExtraImprove >= 15
    tier = 'target80_visual_reference';
end
end

function text = decisionText(tier, aggrImprove, targetExtraImprove)
switch tier
    case 'target80_visual_reference'
        text = sprintf('target80 gives another %.1f%% RMS drop beyond aggressive; use only if cleaner chart is more important than retention', targetExtraImprove);
    case 'aggressive_first_backup'
        text = sprintf('aggressive gives %.1f%% RMS drop and keeps about 85%%+; review this before target80', aggrImprove);
    otherwise
        text = 'current-best remains the default; stricter tiers do not have enough net benefit';
end
end

function path = plotTriple(outputDir, pointId, currentImage, aggressiveImage, target80Image, ...
    currentRow, aggressiveRow, target80Row, tier)
fig = figure('Visible', 'off', 'Position', [100 100 3000 900], 'Color', 'w');
tiledlayout(fig, 1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

drawTier(nexttile, currentImage, 'current-best missing', 'current-best', ...
    currentRow.KeepPct, currentRow.RMS30Max);
drawTier(nexttile, aggressiveImage, 'aggressive missing', 'aggressive', ...
    aggressiveRow.KeepPct, aggressiveRow.RMS30Max);
drawTier(nexttile, target80Image, 'target80 missing', 'target80', ...
    target80Row.KeepPct, target80Row.RMS30Max);

sgtitle(fig, sprintf('%s three-level tradeoff | suggested: %s', pointId, tier), ...
    'Interpreter', 'none');
path = fullfile(outputDir, sprintf('CableAccelThreeLevelTradeoff_%s.jpg', pointId));
exportgraphics(fig, path, 'Resolution', 140);
close(fig);
end

function drawTier(ax, imagePath, missingLabel, tierName, keepPct, rmsMax)
if isfile(imagePath)
    image(ax, imread(imagePath));
    axis(ax, 'image');
    axis(ax, 'off');
else
    axis(ax, 'off');
    text(ax, 0.5, 0.5, missingLabel, 'HorizontalAlignment', 'center', ...
        'Interpreter', 'none');
end
title(ax, sprintf('%s | keep %.2f%% | RMS max %.2f', tierName, keepPct, rmsMax), ...
    'Interpreter', 'none');
end

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 2600 3000], 'Color', 'w');
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
exportgraphics(fig, boardPath, 'Resolution', 130);
close(fig);
end

function htmlPath = writeHtml(outputDir, comparison, plotPaths, points, boardPath)
htmlPath = fullfile(outputDir, 'index.html');
fid = fopen(htmlPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Three-Level Tradeoff</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #7c3aed;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.current_best_default{background:#eef6ff}.aggressive_first_backup{background:#fff7ed}.target80_visual_reference{background:#f4edff}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;}');
fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(900px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;} a{color:#075da8;text-decoration:none;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Three-Level Tradeoff</h1>\n');
fprintf(fid, '<div class="note">Display-only review. Columns are current-best, aggressive, and target80. Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.</div>\n');
fprintf(fid, '<h2>Decision Table</h2>\n<table>\n');
fprintf(fid, '<tr><th>Point</th><th>Suggested tier</th><th>Current keep/RMS</th><th>Aggressive keep/RMS</th><th>Target80 keep/RMS</th><th>Aggressive RMS improvement %%</th><th>Target80 RMS improvement %%</th><th>Decision</th></tr>\n');
for i = 1:height(comparison)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.2f / %.2f</td><td class="num">%.2f / %.2f</td><td class="num">%.2f / %.2f</td><td class="num">%.1f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        htmlText(comparison.SuggestedTier{i}), htmlText(comparison.PointID{i}), ...
        htmlText(comparison.SuggestedTier{i}), comparison.CurrentBestKeepPct(i), ...
        comparison.CurrentBestRMS30Max(i), comparison.AggressiveKeepPct(i), ...
        comparison.AggressiveRMS30Max(i), comparison.Target80KeepPct(i), ...
        comparison.Target80RMS30Max(i), comparison.AggressiveRMS30MaxImprovementPct(i), ...
        comparison.Target80RMS30MaxImprovementPct(i), htmlText(comparison.Decision{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Review Board</h2>\n<div class="figure"><img src="%s" alt="review board"></div>\n', htmlText(localFileName(boardPath)));
fprintf(fid, '<h2>Per-Point Three-Level Views</h2>\n<div class="grid">\n');
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
fprintf(fid, '# Zhishan Cable Acceleration Three-Level Tradeoff\n\n');
fprintf(fid, '- Open `index.html` for the side-by-side review.\n');
fprintf(fid, '- Review board: `%s`\n', localFileName(boardPath));
fprintf(fid, '- Source HTML: `%s`\n\n', localFileName(htmlPath));
fprintf(fid, 'Formal spectrum/force calculation remains unchanged. This package is display-only.\n\n');
fprintf(fid, '| Point | Suggested tier | Aggressive RMS improvement %% | Target80 RMS improvement %% | Decision |\n');
fprintf(fid, '|---|---|---:|---:|---|\n');
for i = 1:height(comparison)
    fprintf(fid, '| %s | %s | %.1f | %.1f | %s |\n', ...
        comparison.PointID{i}, comparison.SuggestedTier{i}, ...
        comparison.AggressiveRMS30MaxImprovementPct(i), ...
        comparison.Target80RMS30MaxImprovementPct(i), comparison.Decision{i});
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
