function result = export_zhishan_cable_accel_decisive_visual_display()
%EXPORT_ZHISHAN_CABLE_ACCEL_DECISIVE_VISUAL_DISPLAY Export cleaner-priority pick.
%   Uses the retention tradeoff decision table to make one stricter visual
%   package: target75 where the extra RMS reduction is large, otherwise the
%   visual-best mixed pick. Display/report review only.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
outputDir = fullfile(stableDir, 'decisive_visual_display_export');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

decision = readtable(fullfile(stableDir, 'retention_tradeoff_summary', ...
    'CableAccelRetentionTradeoff_decisions.csv'), 'Encoding', 'UTF-8');
visualBest = readtable(fullfile(stableDir, 'visual_best_display_export', ...
    'CableAccelVisualBestDisplay_manifest.csv'), 'Encoding', 'UTF-8');
target75 = readtable(fullfile(stableDir, 'target75_display_export', ...
    'CableAccelTarget75Display_manifest.csv'), 'Encoding', 'UTF-8');
currentBest = readtable(fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([24403 21069 26368 20339 25512 33616 23637 31034])], ...
    'CableAccelCurrentBestReport_manifest.csv'), 'Encoding', 'UTF-8');

points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    dIdx = find(strcmp(decision.PointID, pointId), 1);
    if isempty(dIdx)
        error('Missing decision row for %s.', pointId);
    end
    if strcmp(decision.NextReviewTier{dIdx}, 'target75_review_only')
        selectedTier = 'target75';
        sourceDir = fullfile(stableDir, 'target75_display_export');
        sourceImage = fullfile(sourceDir, sprintf( ...
            'CableAccelTarget75Display_%s_20260301_20260331.jpg', pointId));
        sIdx = find(strcmp(target75.PointID, pointId), 1);
        sourceRow = target75(sIdx, :);
        strategy = ['target75 ' sourceRow.Strategy{1}];
        sourceKeep = sourceRow.KeepPct;
        sourceRms = sourceRow.RMS30Max;
        sourceP95 = sourceRow.RMS30P95;
    else
        selectedTier = 'visual_best';
        sourceDir = fullfile(stableDir, 'visual_best_display_export');
        sourceImage = fullfile(sourceDir, sprintf( ...
            'CableAccelVisualBestDisplay_%s_20260301_20260331.jpg', pointId));
        sIdx = find(strcmp(visualBest.PointID, pointId), 1);
        sourceRow = visualBest(sIdx, :);
        strategy = sourceRow.Strategy{1};
        sourceKeep = sourceRow.KeepPct;
        sourceRms = sourceRow.RMS30Max;
        sourceP95 = sourceRow.RMS30P95;
    end
    if ~isfile(sourceImage)
        error('Missing selected image %s.', sourceImage);
    end

    outImage = fullfile(outputDir, sprintf( ...
        'CableAccelDecisiveVisualDisplay_%s_20260301_20260331.jpg', pointId));
    copyfile(sourceImage, outImage, 'f');
    plotPaths{i} = outImage;

    cIdx = find(strcmp(currentBest.PointID, pointId), 1);
    keepDelta = sourceKeep - currentBest.KeepPct(cIdx);
    rmsImprove = pctReduction(currentBest.RMS30Max(cIdx), sourceRms);
    rows(end+1, :) = {pointId, selectedTier, strategy, sourceKeep, sourceRms, ...
        sourceP95, keepDelta, rmsImprove, decision.Reason{dIdx}, outImage}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedTier','Strategy','KeepPct','RMS30Max','RMS30P95', ...
    'KeepDeltaVsCurrentBestPct','RMS30MaxImprovementVsCurrentBestPct', ...
    'Reason','PlotPath'});

contactSheet = buildReviewBoard(plotPaths, points, outputDir, ...
    'CableAccelDecisiveVisualDisplay_ContactSheet.jpg');
reviewBoard = buildReviewBoard(plotPaths, points, outputDir, ...
    'CableAccelDecisiveVisualDisplay_ReviewBoard.jpg');
manifestPath = fullfile(outputDir, 'CableAccelDecisiveVisualDisplay_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelDecisiveVisualDisplay_manifest.csv');
htmlPath = writeHtml(outputDir, manifest, contactSheet, reviewBoard);
readmePath = writeReadme(outputDir, manifest, htmlPath, contactSheet);
writetable(manifest, manifestPath, 'Sheet', 'manifest');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');

result = struct();
result.output_dir = outputDir;
result.manifest = manifestPath;
result.manifest_csv = manifestCsvPath;
result.html = htmlPath;
result.readme = readmePath;
result.contact_sheet = contactSheet;
result.review_board = reviewBoard;

fprintf('decisive visual output dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('html %s\n', htmlPath);
disp(manifest(:, {'PointID','SelectedTier','KeepPct','RMS30Max', ...
    'RMS30MaxImprovementVsCurrentBestPct'}));
end

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 1800 1400], 'Color', 'w');
tiledlayout(fig, 2, 4, 'Padding', 'compact', 'TileSpacing', 'compact');
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
exportgraphics(fig, boardPath, 'Resolution', 150);
close(fig);
end

function htmlPath = writeHtml(outputDir, manifest, contactSheet, reviewBoard)
htmlPath = fullfile(outputDir, 'index.html');
fid = fopen(htmlPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Decisive Visual Display</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #b91c1c;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.target75{background:#fff1f2}.visual_best{background:#eaf7f2}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;}');
fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Decisive Visual Display</h1>\n');
fprintf(fid, '<div class="note">Display-only cleaner-priority mixed pick. Uses target75 for CF-1/CF-2/CF-5 and visual-best for the other points. Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.</div>\n');
fprintf(fid, '<h2>Manifest</h2>\n<table>\n');
fprintf(fid, '<tr><th>Point</th><th>Selected tier</th><th>Strategy</th><th>Keep %%</th><th>RMS30 max</th><th>RMS30 P95</th><th>RMS improvement vs current-best %%</th><th>Reason</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        htmlText(manifest.SelectedTier{i}), htmlText(manifest.PointID{i}), ...
        htmlText(manifest.SelectedTier{i}), htmlText(manifest.Strategy{i}), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), manifest.RMS30P95(i), ...
        manifest.RMS30MaxImprovementVsCurrentBestPct(i), htmlText(manifest.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', ...
    htmlText(localFileName(contactSheet)));
fprintf(fid, '<h2>Review Board</h2><div class="figure"><img src="%s" alt="review board"></div>\n', ...
    htmlText(localFileName(reviewBoard)));
fprintf(fid, '<h2>Per-Point</h2><div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(localFileName(manifest.PlotPath{i})), ...
        htmlText(manifest.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function readmePath = writeReadme(outputDir, manifest, htmlPath, contactSheet)
readmePath = fullfile(outputDir, 'README.md');
fid = fopen(readmePath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Decisive Visual Display\n\n');
fprintf(fid, '- Open `%s` for the cleaner-priority mixed pick.\n', localFileName(htmlPath));
fprintf(fid, '- Contact sheet: `%s`\n\n', localFileName(contactSheet));
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Selected tier | Keep %% | RMS30 max | RMS improvement vs current-best %% |\n');
fprintf(fid, '|---|---|---:|---:|---:|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %.3f | %.3f | %.1f |\n', ...
        manifest.PointID{i}, manifest.SelectedTier{i}, manifest.KeepPct(i), ...
        manifest.RMS30Max(i), manifest.RMS30MaxImprovementVsCurrentBestPct(i));
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
