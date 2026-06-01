function result = export_zhishan_cable_accel_cleanest_keep_display(minKeepPct)
%EXPORT_ZHISHAN_CABLE_ACCEL_CLEANEST_KEEP_DISPLAY Export cleanest keep floor.
%   Chooses, per point, the lowest RMS30 max candidate among all generated
%   display tiers with keep rate >= minKeepPct. Display/report review only.

if nargin < 1 || isempty(minKeepPct)
    minKeepPct = 60;
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
tierName = sprintf('cleanest%d', round(minKeepPct));
titleName = titleCase(tierName);
outputDir = fullfile(stableDir, [tierName '_display_export']);
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
    'target60', fullfile(stableDir, 'target60_display_export', ...
        'CableAccelTarget60Display_manifest.csv'), ...
        fullfile(stableDir, 'target60_display_export'), ...
        'CableAccelTarget60Display_%s_20260301_20260331.jpg';
    'target55', fullfile(stableDir, 'target55_display_export', ...
        'CableAccelTarget55Display_manifest.csv'), ...
        fullfile(stableDir, 'target55_display_export'), ...
        'CableAccelTarget55Display_%s_20260301_20260331.jpg';
    'target50', fullfile(stableDir, 'target50_display_export', ...
        'CableAccelTarget50Display_manifest.csv'), ...
        fullfile(stableDir, 'target50_display_export'), ...
        'CableAccelTarget50Display_%s_20260301_20260331.jpg';
    'visual_best', fullfile(stableDir, 'visual_best_display_export', ...
        'CableAccelVisualBestDisplay_manifest.csv'), ...
        fullfile(stableDir, 'visual_best_display_export'), ...
        'CableAccelVisualBestDisplay_%s_20260301_20260331.jpg';
    'decisive_visual', fullfile(stableDir, 'decisive_visual_display_export', ...
        'CableAccelDecisiveVisualDisplay_manifest.csv'), ...
        fullfile(stableDir, 'decisive_visual_display_export'), ...
        'CableAccelDecisiveVisualDisplay_%s_20260301_20260331.jpg';
    'satisfaction_auto', fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
        char([32034 21147 21152 36895 24230]) '_' ...
        char([28385 24847 24230 33258 21160 25512 33616 23637 31034])], ...
        'CableAccelSatisfactionAutoReport_manifest.csv'), ...
        fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
        char([32034 21147 21152 36895 24230]) '_' ...
        char([28385 24847 24230 33258 21160 25512 33616 23637 31034])]), ...
        'CableAccelSatisfactionAutoReport_%s_20260301_20260331.jpg'
    };

candidates = table();
for i = 1:size(sources, 1)
    if isfile(sources{i, 2})
        candidates = [candidates; normalizeManifest(sources(i, :))]; %#ok<AGROW>
    end
end
if isempty(candidates)
    error('No candidate manifests found.');
end

points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
current = candidates(strcmp(candidates.SourceTier, 'current_best'), :);
if height(current) ~= numel(points)
    error('Current-best baseline must contain all 8 points.');
end

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
        'CableAccel%sDisplay_%s_20260301_20260331.jpg', titleName, pointId));
    copyfile(srcImage, outImage, 'f');
    plotPaths{i} = outImage;

    curIdx = find(strcmp(current.PointID, pointId), 1);
    keepDelta = selected.KeepPct - current.KeepPct(curIdx);
    rmsImprove = pctReduction(current.RMS30Max(curIdx), selected.RMS30Max);
    reason = sprintf('lowest RMS30 max among generated candidates with keep >= %.0f%%', minKeepPct);
    rows(end+1, :) = {pointId, selected.SourceTier{1}, selected.Strategy{1}, ...
        selected.KeepPct, selected.RMS30Max, selected.RMS30P95, keepDelta, ...
        rmsImprove, reason, outImage}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedTier','Strategy','KeepPct','RMS30Max','RMS30P95', ...
    'KeepDeltaVsCurrentBestPct','RMS30MaxImprovementVsCurrentBestPct', ...
    'Reason','PlotPath'});
scoreMatrix = addScores(candidates, current, points, minKeepPct);
contactSheet = buildReviewBoard(plotPaths, points, outputDir, ...
    sprintf('CableAccel%sDisplay_ContactSheet.jpg', titleName));
reviewBoard = buildReviewBoard(plotPaths, points, outputDir, ...
    sprintf('CableAccel%sDisplay_ReviewBoard.jpg', titleName));
manifestPath = fullfile(outputDir, sprintf('CableAccel%sDisplay_manifest.xlsx', titleName));
manifestCsvPath = fullfile(outputDir, sprintf('CableAccel%sDisplay_manifest.csv', titleName));
scorePath = fullfile(outputDir, sprintf('CableAccel%sDisplay_score_matrix.xlsx', titleName));
scoreCsvPath = fullfile(outputDir, sprintf('CableAccel%sDisplay_score_matrix.csv', titleName));
htmlPath = writeHtml(outputDir, tierName, titleName, minKeepPct, manifest, ...
    scoreMatrix, contactSheet, reviewBoard);
readmePath = writeReadme(outputDir, titleName, minKeepPct, manifest, htmlPath, contactSheet);

writetable(manifest, manifestPath, 'Sheet', 'manifest');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');
writetable(scoreMatrix, scorePath, 'Sheet', 'score_matrix');
writetable(scoreMatrix, scoreCsvPath, 'Encoding', 'UTF-8');

result = struct();
result.tier = tierName;
result.min_keep_pct = minKeepPct;
result.output_dir = outputDir;
result.manifest = manifestPath;
result.manifest_csv = manifestCsvPath;
result.score_matrix = scorePath;
result.score_matrix_csv = scoreCsvPath;
result.html = htmlPath;
result.readme = readmePath;
result.contact_sheet = contactSheet;
result.review_board = reviewBoard;

fprintf('%s output dir %s\n', tierName, outputDir);
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
T = readtable(path, 'Encoding', 'UTF-8');
rows = {};
for i = 1:height(T)
    pointId = T.PointID{i};
    strategy = '';
    if ismember('Strategy', T.Properties.VariableNames)
        strategy = char(string(T.Strategy{i}));
    elseif ismember('Reason', T.Properties.VariableNames)
        strategy = char(string(T.Reason{i}));
    elseif ismember('Rationale', T.Properties.VariableNames)
        strategy = char(string(T.Rationale{i}));
    elseif ismember('SelectedReviewTier', T.Properties.VariableNames)
        strategy = char(string(T.SelectedReviewTier{i}));
    elseif ismember('SelectedTier', T.Properties.VariableNames)
        strategy = char(string(T.SelectedTier{i}));
    end
    imagePath = fullfile(folder, sprintf(imagePattern, pointId));
    rows(end+1, :) = {pointId, tier, strategy, T.KeepPct(i), ...
        T.RMS30Max(i), resolveRmsP95(T, i), imagePath}; %#ok<AGROW>
end
out = cell2table(rows, 'VariableNames', { ...
    'PointID','SourceTier','Strategy','KeepPct','RMS30Max','RMS30P95','ImagePath'});
end

function value = resolveRmsP95(T, i)
if ismember('RMS30P95', T.Properties.VariableNames)
    value = T.RMS30P95(i);
else
    value = NaN;
end
end

function scoreMatrix = addScores(candidates, current, points, minKeepPct)
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
    'EligibleForKeepFloor','AutoScore','ImagePath'});
rankValues = zeros(height(scoreMatrix), 1);
for i = 1:numel(points)
    idx = find(strcmp(scoreMatrix.PointID, points{i}));
    ranked = sortrows(scoreMatrix(idx, :), {'RMS30Max','KeepPct'}, {'ascend','descend'});
    for r = 1:height(ranked)
        original = idx(strcmp(scoreMatrix.SourceTier(idx), ranked.SourceTier{r}) & ...
            abs(scoreMatrix.RMS30Max(idx) - ranked.RMS30Max(r)) < 1e-9);
        if ~isempty(original)
            rankValues(original(1)) = r;
        end
    end
end
scoreMatrix.RMS30RankWithinPoint = rankValues;
end

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 1800 1400], 'Color', 'w');
tiledlayout(fig, 2, 4, 'Padding', 'compact', 'TileSpacing', 'compact');
for i = 1:numel(points)
    ax = nexttile;
    image(ax, imread(plotPaths{i}));
    axis(ax, 'image');
    axis(ax, 'off');
    title(ax, points{i}, 'Interpreter', 'none');
end
boardPath = fullfile(outputDir, fileName);
exportgraphics(fig, boardPath, 'Resolution', 150);
close(fig);
end

function htmlPath = writeHtml(outputDir, tierName, titleName, minKeepPct, ...
    manifest, scoreMatrix, contactSheet, reviewBoard)
htmlPath = fullfile(outputDir, 'index.html');
fid = fopen(htmlPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration %s Display</title>\n', htmlText(tierName));
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #b91c1c;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.current_best{background:#eef6ff}.aggressive{background:#fff7ed}.target80{background:#f4edff}.target75{background:#fff1f2}.target70{background:#fee2e2}.target60{background:#fecaca}.target50{background:#fca5a5}.visual_best{background:#eaf7f2}.decisive_visual{background:#fef3c7}.satisfaction_auto{background:#dbeafe}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration %s Display</h1>\n', htmlText(tierName));
fprintf(fid, '<div class="note">Automatic non-LLM pick: choose the lowest RMS30 max candidate per point with keep rate at least %.0f%%. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>.</div>\n', minKeepPct);
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
        scoreMatrix.EligibleForKeepFloor(i), scoreMatrix.RMS30RankWithinPoint(i), ...
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

function readmePath = writeReadme(outputDir, titleName, minKeepPct, manifest, htmlPath, contactSheet)
readmePath = fullfile(outputDir, 'README.md');
fid = fopen(readmePath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration %s Display\n\n', titleName);
fprintf(fid, '- Open `%s` for review.\n', localFileName(htmlPath));
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

function title = titleCase(textValue)
parts = split(string(textValue), {'_', '-', ' '});
for i = 1:numel(parts)
    p = char(parts(i));
    if isempty(p)
        continue;
    end
    parts(i) = string([upper(p(1)) p(2:end)]);
end
title = char(strjoin(parts, ''));
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
