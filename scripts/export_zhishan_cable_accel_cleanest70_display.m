function result = export_zhishan_cable_accel_cleanest70_display(minKeepPct)
%EXPORT_ZHISHAN_CABLE_ACCEL_CLEANEST70_DISPLAY Export min-RMS >= keep floor.
%   Automatically picks, per point, the candidate with the lowest RMS30 max
%   among generated display tiers that keep at least minKeepPct finite data.
%   Display/report review only.

if nargin < 1 || isempty(minKeepPct)
    minKeepPct = 70;
end
minKeepPct = double(minKeepPct);
if ~isfinite(minKeepPct) || minKeepPct <= 0 || minKeepPct >= 100
    error('minKeepPct must be between 0 and 100.');
end

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
currentDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([24403 21069 26368 20339 25512 33616 23637 31034])]);
outputDir = fullfile(stableDir, 'cleanest70_display_export');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

sources = {
    'current_best', fullfile(currentDir, 'CableAccelCurrentBestReport_manifest.csv'), ...
        currentDir, 'CableAccelCurrentBestReport_%s_20260301_20260331.jpg';
    'aggressive', fullfile(stableDir, 'aggressive_display_export', ...
        'CableAccelAggressiveDisplay_manifest.csv'), ...
        fullfile(stableDir, 'aggressive_display_export'), ...
        'CableAccelAggressiveDisplay_%s_20260301_20260331.jpg';
    'target80', fullfile(stableDir, 'target80_display_export', ...
        'CableAccelTarget80Display_manifest.csv'), ...
        fullfile(stableDir, 'target80_display_export'), ...
        'CableAccelTarget80Display_%s_20260301_20260331.jpg';
    'target75', fullfile(stableDir, 'target75_display_export', ...
        'CableAccelTarget75Display_manifest.csv'), ...
        fullfile(stableDir, 'target75_display_export'), ...
        'CableAccelTarget75Display_%s_20260301_20260331.jpg';
    'target70', fullfile(stableDir, 'target70_display_export', ...
        'CableAccelTarget70Display_manifest.csv'), ...
        fullfile(stableDir, 'target70_display_export'), ...
        'CableAccelTarget70Display_%s_20260301_20260331.jpg';
    'visual_best', fullfile(stableDir, 'visual_best_display_export', ...
        'CableAccelVisualBestDisplay_manifest.csv'), ...
        fullfile(stableDir, 'visual_best_display_export'), ...
        'CableAccelVisualBestDisplay_%s_20260301_20260331.jpg';
    'decisive_visual', fullfile(stableDir, 'decisive_visual_display_export', ...
        'CableAccelDecisiveVisualDisplay_manifest.csv'), ...
        fullfile(stableDir, 'decisive_visual_display_export'), ...
        'CableAccelDecisiveVisualDisplay_%s_20260301_20260331.jpg'
    };

candidates = table();
for i = 1:size(sources, 1)
    candidates = [candidates; normalizeManifest(sources(i, :))]; %#ok<AGROW>
end

points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
current = candidates(strcmp(candidates.SourceTier, 'current_best'), :);
rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    pointRows = candidates(strcmp(candidates.PointID, pointId), :);
    eligible = pointRows(pointRows.KeepPct >= minKeepPct, :);
    if isempty(eligible)
        eligible = pointRows;
    end
    eligible = sortrows(eligible, {'RMS30Max','KeepPct'}, {'ascend','descend'});
    selected = eligible(1, :);
    srcImage = selected.ImagePath{1};
    if ~isfile(srcImage)
        error('Missing selected image %s.', srcImage);
    end
    outImage = fullfile(outputDir, sprintf( ...
        'CableAccelCleanest70Display_%s_20260301_20260331.jpg', pointId));
    copyfile(srcImage, outImage, 'f');
    plotPaths{i} = outImage;

    curIdx = find(strcmp(current.PointID, pointId), 1);
    keepDelta = selected.KeepPct - current.KeepPct(curIdx);
    rmsImprove = pctReduction(current.RMS30Max(curIdx), selected.RMS30Max);
    reason = sprintf('lowest RMS30 max among candidates with keep >= %.0f%%', minKeepPct);
    rows(end+1, :) = {pointId, selected.SourceTier{1}, selected.Strategy{1}, ...
        selected.KeepPct, selected.RMS30Max, selected.RMS30P95, keepDelta, ...
        rmsImprove, reason, outImage}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedTier','Strategy','KeepPct','RMS30Max','RMS30P95', ...
    'KeepDeltaVsCurrentBestPct','RMS30MaxImprovementVsCurrentBestPct', ...
    'Reason','PlotPath'});

scoreMatrix = addBaselineScores(candidates, current, points, minKeepPct);
contactSheet = buildReviewBoard(plotPaths, points, outputDir, ...
    'CableAccelCleanest70Display_ContactSheet.jpg');
reviewBoard = buildReviewBoard(plotPaths, points, outputDir, ...
    'CableAccelCleanest70Display_ReviewBoard.jpg');
manifestPath = fullfile(outputDir, 'CableAccelCleanest70Display_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelCleanest70Display_manifest.csv');
scorePath = fullfile(outputDir, 'CableAccelCleanest70Display_score_matrix.xlsx');
scoreCsvPath = fullfile(outputDir, 'CableAccelCleanest70Display_score_matrix.csv');
htmlPath = writeHtml(outputDir, manifest, scoreMatrix, contactSheet, reviewBoard, minKeepPct);
readmePath = writeReadme(outputDir, manifest, htmlPath, contactSheet, minKeepPct);
writetable(manifest, manifestPath, 'Sheet', 'manifest');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');
writetable(scoreMatrix, scorePath, 'Sheet', 'score_matrix');
writetable(scoreMatrix, scoreCsvPath, 'Encoding', 'UTF-8');

result = struct();
result.output_dir = outputDir;
result.manifest = manifestPath;
result.manifest_csv = manifestCsvPath;
result.score_matrix = scorePath;
result.score_matrix_csv = scoreCsvPath;
result.html = htmlPath;
result.readme = readmePath;
result.contact_sheet = contactSheet;
result.review_board = reviewBoard;
result.min_keep_pct = minKeepPct;

fprintf('cleanest70 output dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('html %s\n', htmlPath);
disp(manifest(:, {'PointID','SelectedTier','KeepPct','RMS30Max', ...
    'RMS30MaxImprovementVsCurrentBestPct'}));
end

function out = normalizeManifest(source)
tier = source{1};
path = source{2};
folder = source{3};
imagePattern = source{4};
if ~isfile(path)
    error('Missing manifest %s.', path);
end
T = readtable(path, 'Encoding', 'UTF-8');
rows = {};
for i = 1:height(T)
    pointId = T.PointID{i};
    strategy = '';
    if ismember('Strategy', T.Properties.VariableNames)
        strategy = T.Strategy{i};
    elseif ismember('Rationale', T.Properties.VariableNames)
        strategy = T.Rationale{i};
    elseif ismember('SelectedSource', T.Properties.VariableNames)
        strategy = T.SelectedSource{i};
    end
    imagePath = fullfile(folder, sprintf(imagePattern, pointId));
    rows(end+1, :) = {pointId, tier, strategy, T.KeepPct(i), ...
        T.RMS30Max(i), T.RMS30P95(i), imagePath}; %#ok<AGROW>
end
out = cell2table(rows, 'VariableNames', { ...
    'PointID','SourceTier','Strategy','KeepPct','RMS30Max','RMS30P95','ImagePath'});
end

function scoreMatrix = addBaselineScores(candidates, current, points, minKeepPct)
rows = {};
for i = 1:height(candidates)
    pointId = candidates.PointID{i};
    curIdx = find(strcmp(current.PointID, pointId), 1);
    keepDelta = candidates.KeepPct(i) - current.KeepPct(curIdx);
    keepLoss = max(0, -keepDelta);
    rmsImprove = pctReduction(current.RMS30Max(curIdx), candidates.RMS30Max(i));
    eligible = candidates.KeepPct(i) >= minKeepPct;
    autoScore = rmsImprove - 0.8 * keepLoss - 2.5 * max(0, minKeepPct - candidates.KeepPct(i));
    rows(end+1, :) = {pointId, candidates.SourceTier{i}, candidates.Strategy{i}, ...
        candidates.KeepPct(i), candidates.RMS30Max(i), candidates.RMS30P95(i), ...
        keepDelta, rmsImprove, eligible, autoScore, candidates.ImagePath{i}}; %#ok<AGROW>
end
scoreMatrix = cell2table(rows, 'VariableNames', { ...
    'PointID','SourceTier','Strategy','KeepPct','RMS30Max','RMS30P95', ...
    'KeepDeltaVsCurrentBestPct','RMS30MaxImprovementVsCurrentBestPct', ...
    'EligibleForCleanest70','AutoScore','ImagePath'});
pointRank = zeros(height(scoreMatrix), 1);
for i = 1:numel(points)
    idx = find(strcmp(scoreMatrix.PointID, points{i}));
    ranked = sortrows(scoreMatrix(idx, :), {'RMS30Max','KeepPct'}, {'ascend','descend'});
    for r = 1:height(ranked)
        original = idx(strcmp(scoreMatrix.SourceTier(idx), ranked.SourceTier{r}) & ...
            abs(scoreMatrix.RMS30Max(idx) - ranked.RMS30Max(r)) < 1e-9);
        if ~isempty(original)
            pointRank(original(1)) = r;
        end
    end
end
scoreMatrix.RMS30RankWithinPoint = pointRank;
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

function htmlPath = writeHtml(outputDir, manifest, scoreMatrix, contactSheet, reviewBoard, minKeepPct)
htmlPath = fullfile(outputDir, 'index.html');
fid = fopen(htmlPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Cleanest70 Display</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #b91c1c;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.current_best{background:#eef6ff}.aggressive{background:#fff7ed}.target80{background:#f4edff}.target75{background:#fff1f2}.target70{background:#fee2e2}.visual_best{background:#eaf7f2}.decisive_visual{background:#fef3c7}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Cleanest70 Display</h1>\n');
fprintf(fid, '<div class="note">Automatic non-LLM pick: for each point, choose the lowest RMS30 max among generated display candidates with keep rate at least %.0f%%. Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.</div>\n', minKeepPct);
fprintf(fid, '<h2>Selected Manifest</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Selected tier</th><th>Strategy</th><th>Keep %%</th><th>RMS30 max</th><th>RMS30 P95</th><th>Keep delta</th><th>RMS improvement %%</th><th>Reason</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        htmlText(manifest.SelectedTier{i}), htmlText(manifest.PointID{i}), ...
        htmlText(manifest.SelectedTier{i}), htmlText(manifest.Strategy{i}), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), manifest.RMS30P95(i), ...
        manifest.KeepDeltaVsCurrentBestPct(i), ...
        manifest.RMS30MaxImprovementVsCurrentBestPct(i), htmlText(manifest.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', ...
    htmlText(localFileName(contactSheet)));
fprintf(fid, '<h2>Review Board</h2><div class="figure"><img src="%s" alt="review board"></div>\n', ...
    htmlText(localFileName(reviewBoard)));
fprintf(fid, '<h2>Score Matrix</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Tier</th><th>Keep %%</th><th>RMS30 max</th><th>RMS improvement %%</th><th>Eligible</th><th>RMS rank</th><th>Auto score</th><th>Strategy</th></tr>\n');
scoreMatrix = sortrows(scoreMatrix, {'PointID','RMS30RankWithinPoint','SourceTier'});
for i = 1:height(scoreMatrix)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%d</td><td class="num">%d</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        htmlText(scoreMatrix.SourceTier{i}), htmlText(scoreMatrix.PointID{i}), ...
        htmlText(scoreMatrix.SourceTier{i}), scoreMatrix.KeepPct(i), ...
        scoreMatrix.RMS30Max(i), scoreMatrix.RMS30MaxImprovementVsCurrentBestPct(i), ...
        scoreMatrix.EligibleForCleanest70(i), scoreMatrix.RMS30RankWithinPoint(i), ...
        scoreMatrix.AutoScore(i), htmlText(scoreMatrix.Strategy{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Per-Point</h2><div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(localFileName(manifest.PlotPath{i})), ...
        htmlText(manifest.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function readmePath = writeReadme(outputDir, manifest, htmlPath, contactSheet, minKeepPct)
readmePath = fullfile(outputDir, 'README.md');
fid = fopen(readmePath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Cleanest70 Display\n\n');
fprintf(fid, '- Open `%s` for the automatic cleanest pick.\n', localFileName(htmlPath));
fprintf(fid, '- Contact sheet: `%s`\n', localFileName(contactSheet));
fprintf(fid, '- Rule: choose the lowest RMS30 max candidate with keep >= `%.0f%%` for each point.\n\n', minKeepPct);
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Tier | Keep %% | RMS30 max | RMS improvement vs current-best %% |\n');
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
