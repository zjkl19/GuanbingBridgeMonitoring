function result = compare_zhishan_cable_accel_current_vs_cleaner()
%COMPARE_ZHISHAN_CABLE_ACCEL_CURRENT_VS_CLEANER Visual side-by-side review.
%   Compares the current recommended display export with the cleaner-tier
%   export. This is a display-only review artifact.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
reportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' char([25512 33616 23637 31034])];
currentDir = fullfile(dataRoot, reportDirName);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
cleanerDir = fullfile(stableDir, 'cleaner_display_export');
outputDir = fullfile(stableDir, 'current_vs_cleaner_review');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

current = readtable(fullfile(currentDir, 'CableAccelRecommendationDisplay_manifest.csv'), ...
    'Encoding', 'UTF-8');
cleaner = readtable(fullfile(cleanerDir, 'CableAccelCleanerDisplay_manifest.csv'), ...
    'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    cIdx = find(strcmp(current.PointID, pointId), 1);
    kIdx = find(strcmp(cleaner.PointID, pointId), 1);
    if isempty(cIdx) || isempty(kIdx)
        error('Missing current or cleaner manifest row for %s.', pointId);
    end

    currentImage = fullfile(currentDir, sprintf( ...
        'CableAccelRecommendationDisplay_%s_20260301_20260331.jpg', pointId));
    cleanerImage = fullfile(cleanerDir, sprintf( ...
        'CableAccelCleanerDisplay_%s_20260301_20260331.jpg', pointId));
    plotPaths{i} = plotPair(outputDir, pointId, currentImage, cleanerImage, ...
        current(cIdx, :), cleaner(kIdx, :));

    keepDelta = cleaner.KeepPct(kIdx) - current.KeepPct(cIdx);
    rmsMaxImprovement = pctReduction(current.RMS30Max(cIdx), cleaner.RMS30Max(kIdx));
    rmsP95Improvement = pctReduction(current.RMS30P95(cIdx), cleaner.RMS30P95(kIdx));
    rows(end+1, :) = {pointId, current.Strategy{cIdx}, cleaner.Strategy{kIdx}, ...
        current.KeepPct(cIdx), cleaner.KeepPct(kIdx), keepDelta, ...
        current.RMS30Max(cIdx), cleaner.RMS30Max(kIdx), rmsMaxImprovement, ...
        current.RMS30P95(cIdx), cleaner.RMS30P95(kIdx), rmsP95Improvement, ...
        conclusionText(keepDelta, rmsMaxImprovement, rmsP95Improvement), plotPaths{i}}; %#ok<AGROW>
end

comparison = cell2table(rows, 'VariableNames', { ...
    'PointID','CurrentStrategy','CleanerStrategy','CurrentKeepPct','CleanerKeepPct', ...
    'KeepDeltaPct','CurrentRMS30Max','CleanerRMS30Max','RMS30MaxImprovementPct', ...
    'CurrentRMS30P95','CleanerRMS30P95','RMS30P95ImprovementPct', ...
    'Conclusion','PairImage'});

boardPath = buildReviewBoard(plotPaths, points, outputDir, 'CableAccelCurrentVsCleaner_ReviewBoard.jpg');
manifestPath = fullfile(outputDir, 'CableAccelCurrentVsCleaner_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelCurrentVsCleaner_manifest.csv');
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

fprintf('current vs cleaner dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('review board %s\n', boardPath);
fprintf('html %s\n', htmlPath);
disp(comparison(:, {'PointID','CleanerKeepPct','KeepDeltaPct','RMS30MaxImprovementPct','RMS30P95ImprovementPct','Conclusion'}));
end

function path = plotPair(outputDir, pointId, currentImage, cleanerImage, currentRow, cleanerRow)
fig = figure('Visible', 'off', 'Position', [100 100 2200 850], 'Color', 'w');
tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

ax1 = nexttile;
if isfile(currentImage)
    image(ax1, imread(currentImage));
    axis(ax1, 'image');
    axis(ax1, 'off');
else
    missingText(ax1, 'current missing');
end
title(ax1, sprintf('current | keep %.2f%% | RMS max %.2f', ...
    currentRow.KeepPct, currentRow.RMS30Max), 'Interpreter', 'none');

ax2 = nexttile;
if isfile(cleanerImage)
    image(ax2, imread(cleanerImage));
    axis(ax2, 'image');
    axis(ax2, 'off');
else
    missingText(ax2, 'cleaner missing');
end
title(ax2, sprintf('cleaner | keep %.2f%% | RMS max %.2f', ...
    cleanerRow.KeepPct, cleanerRow.RMS30Max), 'Interpreter', 'none');

sgtitle(fig, sprintf('%s current vs cleaner display', pointId), 'Interpreter', 'none');
path = fullfile(outputDir, sprintf('CableAccelCurrentVsCleaner_%s.jpg', pointId));
exportgraphics(fig, path, 'Resolution', 145);
close(fig);
end

function missingText(ax, textValue)
axis(ax, 'off');
text(ax, 0.5, 0.5, textValue, 'HorizontalAlignment', 'center', ...
    'Interpreter', 'none');
end

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 2200 2400], 'Color', 'w');
tiledlayout(fig, 4, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
for i = 1:numel(points)
    ax = nexttile;
    if isempty(plotPaths{i}) || ~isfile(plotPaths{i})
        missingText(ax, sprintf('%s missing', points{i}));
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
fprintf(fid, '<title>Zhishan Cable Acceleration Current vs Cleaner</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #2f6fed;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.same{background:#f4f6f8}.improve{background:#eaf7f2}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;}');
fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(760px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230; current vs cleaner</h1>\n');
fprintf(fid, '<div class="note">&#26412;&#39029;&#24182;&#25490;&#27604;&#36739;&#24403;&#21069;&#25512;&#33616;&#29256;&#21644; cleaner &#29256;&#12290;Cleaner &#29256;&#26159;&#26356;&#24178;&#20928;&#30340;&#20505;&#36873;&#65292;&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;&#12290;</div>\n');
fprintf(fid, '<h2>&#24046;&#20540;&#34920; / Delta Table</h2>\n<table>\n');
fprintf(fid, '<tr><th>Point</th><th>Cleaner strategy</th><th>Current keep %%</th><th>Cleaner keep %%</th><th>Keep delta %%</th><th>RMS max improvement %%</th><th>RMS P95 improvement %%</th><th>Conclusion</th></tr>\n');
for i = 1:height(comparison)
    cls = 'same';
    if comparison.RMS30MaxImprovementPct(i) > 2 || comparison.RMS30P95ImprovementPct(i) > 2
        cls = 'improve';
    end
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        cls, htmlText(comparison.PointID{i}), htmlText(comparison.CleanerStrategy{i}), ...
        comparison.CurrentKeepPct(i), comparison.CleanerKeepPct(i), ...
        comparison.KeepDeltaPct(i), comparison.RMS30MaxImprovementPct(i), ...
        comparison.RMS30P95ImprovementPct(i), htmlText(comparison.Conclusion{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>&#24635;&#35272; / Review Board</h2>\n<div class="figure"><img src="%s" alt="review board"></div>\n', htmlText(localFileName(boardPath)));
fprintf(fid, '<h2>&#21333;&#28857;&#24182;&#25490; / Per-Point Side By Side</h2>\n<div class="grid">\n');
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
fprintf(fid, '# Zhishan Cable Acceleration Current vs Cleaner\n\n');
fprintf(fid, '- Open `index.html` for the side-by-side review page.\n');
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
if abs(keepDelta) < 0.05 && abs(rmsMaxImprovement) < 0.5 && abs(rmsP95Improvement) < 0.5
    text = 'same as current';
elseif rmsMaxImprovement >= 8 || rmsP95Improvement >= 8
    text = 'cleaner materially improves display';
elseif rmsMaxImprovement > 1 || rmsP95Improvement > 1
    text = 'cleaner slightly improves display';
else
    text = 'cleaner mostly preserves current result';
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
