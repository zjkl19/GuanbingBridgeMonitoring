function result = compare_zhishan_cable_accel_satisfaction_review()
%COMPARE_ZHISHAN_CABLE_ACCEL_SATISFACTION_REVIEW Compare three final tiers.
%   Puts current-best, cleaner-priority, and cleanest70 report images side
%   by side per point. Display/report review only.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
currentDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([24403 21069 26368 20339 25512 33616 23637 31034])]);
cleanerDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26356 24178 20928 20248 20808 23637 31034])]);
cleanestDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26368 24178 20928 33258 21160 23637 31034])]);
outputDir = fullfile(stableDir, 'satisfaction_review');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

current = readtable(fullfile(currentDir, 'CableAccelCurrentBestReport_manifest.csv'), ...
    'Encoding', 'UTF-8');
cleaner = readtable(fullfile(cleanerDir, 'CableAccelDecisiveVisualReport_manifest.csv'), ...
    'Encoding', 'UTF-8');
cleanest = readtable(fullfile(cleanestDir, 'CableAccelCleanest70Report_manifest.csv'), ...
    'Encoding', 'UTF-8');

points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
rows = {};
plotRows = cell(numel(points), 3);
for i = 1:numel(points)
    pointId = points{i};
    c = rowFor(current, pointId);
    m = rowFor(cleaner, pointId);
    x = rowFor(cleanest, pointId);
    tiers = {
        'current_best', tierLabel(c, 'SelectedSource'), c.KeepPct, c.RMS30Max, ...
            0, currentImage(currentDir, pointId)
        'cleaner_priority', tierLabel(m, 'SelectedTier'), m.KeepPct, m.RMS30Max, ...
            pctReduction(c.RMS30Max, m.RMS30Max), cleanerImage(cleanerDir, pointId)
        'cleanest70', tierLabel(x, 'SelectedTier'), x.KeepPct, x.RMS30Max, ...
            pctReduction(c.RMS30Max, x.RMS30Max), cleanestImage(cleanestDir, pointId)
        };
    for j = 1:size(tiers, 1)
        rows(end+1, :) = {pointId, tiers{j, 1}, tiers{j, 2}, ...
            tiers{j, 3}, tiers{j, 4}, tiers{j, 5}, tiers{j, 6}}; %#ok<AGROW>
        plotRows{i, j} = tiers{j, 6};
    end
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','ReviewTier','SourceTier','KeepPct','RMS30Max', ...
    'RMS30MaxImprovementVsCurrentBestPct','PlotPath'});
decision = buildDecision(manifest, points);
reviewBoard = buildReviewBoard(plotRows, points, outputDir, ...
    'CableAccelSatisfactionReview_Board.jpg');
manifestPath = fullfile(outputDir, 'CableAccelSatisfactionReview_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelSatisfactionReview_manifest.csv');
decisionCsvPath = fullfile(outputDir, 'CableAccelSatisfactionReview_decision.csv');
htmlPath = writeHtml(outputDir, manifest, decision, reviewBoard);
readmePath = writeReadme(outputDir, decision, reviewBoard);
writetable(manifest, manifestPath, 'Sheet', 'manifest');
writetable(decision, manifestPath, 'Sheet', 'decision');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');
writetable(decision, decisionCsvPath, 'Encoding', 'UTF-8');

result = struct();
result.output_dir = outputDir;
result.html = htmlPath;
result.readme = readmePath;
result.manifest = manifestPath;
result.manifest_csv = manifestCsvPath;
result.decision_csv = decisionCsvPath;
result.review_board = reviewBoard;

fprintf('satisfaction review %s\n', htmlPath);
disp(decision);
end

function r = rowFor(T, pointId)
idx = find(strcmp(T.PointID, pointId), 1);
if isempty(idx)
    error('Missing row for %s.', pointId);
end
r = T(idx, :);
end

function label = tierLabel(row, columnName)
if ismember(columnName, row.Properties.VariableNames)
    label = row.(columnName){1};
else
    label = '';
end
end

function path = currentImage(folder, pointId)
path = fullfile(folder, sprintf( ...
    'CableAccelCurrentBestReport_%s_20260301_20260331.jpg', pointId));
assert(isfile(path), 'Missing image %s.', path);
end

function path = cleanerImage(folder, pointId)
path = fullfile(folder, sprintf( ...
    'CableAccelDecisiveVisualReport_%s_20260301_20260331.jpg', pointId));
assert(isfile(path), 'Missing image %s.', path);
end

function path = cleanestImage(folder, pointId)
path = fullfile(folder, sprintf( ...
    'CableAccelCleanest70Report_%s_20260301_20260331.jpg', pointId));
assert(isfile(path), 'Missing image %s.', path);
end

function decision = buildDecision(manifest, points)
rows = {};
for i = 1:numel(points)
    pointId = points{i};
    P = manifest(strcmp(manifest.PointID, pointId), :);
    current = P(strcmp(P.ReviewTier, 'current_best'), :);
    cleaner = P(strcmp(P.ReviewTier, 'cleaner_priority'), :);
    cleanest = P(strcmp(P.ReviewTier, 'cleanest70'), :);
    if cleanest.KeepPct >= 70 && cleanest.RMS30MaxImprovementVsCurrentBestPct >= ...
            cleaner.RMS30MaxImprovementVsCurrentBestPct + 5
        recommended = 'cleanest70';
        reason = sprintf('cleanest70 improves RMS %.1f%% with keep %.1f%%; use if 70%% keep is acceptable', ...
            cleanest.RMS30MaxImprovementVsCurrentBestPct, cleanest.KeepPct);
    elseif cleaner.KeepPct >= 75 && cleaner.RMS30MaxImprovementVsCurrentBestPct >= 20
        recommended = 'cleaner_priority';
        reason = sprintf('cleaner-priority improves RMS %.1f%% with keep %.1f%%', ...
            cleaner.RMS30MaxImprovementVsCurrentBestPct, cleaner.KeepPct);
    else
        recommended = 'current_best';
        reason = sprintf('current-best keeps %.1f%% and is the validated default', current.KeepPct);
    end
    rows(end+1, :) = {pointId, current.KeepPct, current.RMS30Max, ...
        cleaner.KeepPct, cleaner.RMS30Max, cleaner.RMS30MaxImprovementVsCurrentBestPct, ...
        cleanest.KeepPct, cleanest.RMS30Max, cleanest.RMS30MaxImprovementVsCurrentBestPct, ...
        recommended, reason}; %#ok<AGROW>
end
decision = cell2table(rows, 'VariableNames', { ...
    'PointID','CurrentBestKeepPct','CurrentBestRMS30Max', ...
    'CleanerKeepPct','CleanerRMS30Max','CleanerImprovementPct', ...
    'Cleanest70KeepPct','Cleanest70RMS30Max','Cleanest70ImprovementPct', ...
    'AutoReviewRecommendation','Reason'});
end

function boardPath = buildReviewBoard(plotRows, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 2400 3000], 'Color', 'w');
labels = {'current-best', 'cleaner-priority', 'cleanest70'};
rows = numel(points);
cols = numel(labels);
marginX = 0.018;
marginY = 0.016;
gapX = 0.014;
gapY = 0.012;
tileW = (1 - 2 * marginX - (cols - 1) * gapX) / cols;
tileH = (1 - 2 * marginY - (rows - 1) * gapY) / rows;
for i = 1:numel(points)
    for j = 1:3
        left = marginX + (j - 1) * (tileW + gapX);
        bottom = 1 - marginY - i * tileH - (i - 1) * gapY;
        ax = axes(fig, 'Position', [left bottom tileW tileH]); %#ok<LAXES>
        image(ax, imread(plotRows{i, j}));
        axis(ax, 'image');
        axis(ax, 'off');
        title(ax, sprintf('%s | %s', points{i}, labels{j}), 'Interpreter', 'none');
    end
end
boardPath = fullfile(outputDir, fileName);
exportgraphics(fig, boardPath, 'Resolution', 150);
close(fig);
end

function htmlPath = writeHtml(outputDir, manifest, decision, reviewBoard)
htmlPath = fullfile(outputDir, 'index.html');
fid = fopen(htmlPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Satisfaction Review</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #2563eb;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.current_best{background:#eef6ff}.cleaner_priority{background:#fff7ed}.cleanest70{background:#fee2e2}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .point{display:grid;grid-template-columns:repeat(3,minmax(360px,1fr));gap:12px;margin:18px 0 28px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Satisfaction Review</h1>\n');
fprintf(fid, '<div class="note">Three key display candidates are compared in one page: current-best (validated default), cleaner-priority, and cleanest70. Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.</div>\n');
fprintf(fid, '<h2>Auto Review Recommendation</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Current keep/RMS</th><th>Cleaner keep/RMS/improve</th><th>Cleanest70 keep/RMS/improve</th><th>Recommendation</th><th>Reason</th></tr>\n');
for i = 1:height(decision)
    fprintf(fid, '<tr><td>%s</td><td class="num">%.2f / %.2f</td><td class="num">%.2f / %.2f / %.1f%%</td><td class="num">%.2f / %.2f / %.1f%%</td><td>%s</td><td>%s</td></tr>\n', ...
        htmlText(decision.PointID{i}), decision.CurrentBestKeepPct(i), ...
        decision.CurrentBestRMS30Max(i), decision.CleanerKeepPct(i), ...
        decision.CleanerRMS30Max(i), decision.CleanerImprovementPct(i), ...
        decision.Cleanest70KeepPct(i), decision.Cleanest70RMS30Max(i), ...
        decision.Cleanest70ImprovementPct(i), ...
        htmlText(decision.AutoReviewRecommendation{i}), htmlText(decision.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Review Board</h2><div class="figure"><img src="%s" alt="review board"></div>\n', htmlText(localFileName(reviewBoard)));
fprintf(fid, '<h2>Per-Point Side By Side</h2>\n');
points = unique(manifest.PointID, 'stable');
for i = 1:numel(points)
    P = manifest(strcmp(manifest.PointID, points{i}), :);
    fprintf(fid, '<h2>%s</h2><div class="point">\n', htmlText(points{i}));
    for j = 1:height(P)
        fprintf(fid, '<div class="figure %s"><h2>%s</h2><p>keep %.2f%% | RMS30 %.2f | improve %.1f%%</p><img src="%s" alt="%s %s"></div>\n', ...
            htmlText(P.ReviewTier{j}), htmlText(P.ReviewTier{j}), ...
            P.KeepPct(j), P.RMS30Max(j), P.RMS30MaxImprovementVsCurrentBestPct(j), ...
            relPath(outputDir, P.PlotPath{j}), htmlText(P.PointID{j}), htmlText(P.ReviewTier{j}));
    end
    fprintf(fid, '</div>\n');
end
fprintf(fid, '</body>\n</html>\n');
end

function readmePath = writeReadme(outputDir, decision, reviewBoard)
readmePath = fullfile(outputDir, 'README.md');
fid = fopen(readmePath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Satisfaction Review\n\n');
fprintf(fid, '- Open `index.html` for three-tier side-by-side review.\n');
fprintf(fid, '- Review board: `%s`\n\n', localFileName(reviewBoard));
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Recommendation | Reason |\n');
fprintf(fid, '|---|---|---|\n');
for i = 1:height(decision)
    fprintf(fid, '| %s | %s | %s |\n', ...
        decision.PointID{i}, decision.AutoReviewRecommendation{i}, decision.Reason{i});
end
end

function pct = pctReduction(beforeValue, afterValue)
if ~isfinite(beforeValue) || beforeValue == 0 || ~isfinite(afterValue)
    pct = NaN;
else
    pct = 100 * (beforeValue - afterValue) / abs(beforeValue);
end
end

function out = relPath(baseDir, targetPath)
base = char(java.io.File(baseDir).getCanonicalPath());
target = char(java.io.File(targetPath).getCanonicalPath());
baseParts = splitPath(base);
targetParts = splitPath(target);
common = 0;
limit = min(numel(baseParts), numel(targetParts));
for k = 1:limit
    if strcmpi(baseParts{k}, targetParts{k})
        common = k;
    else
        break;
    end
end
if common == 0
    out = strrep(target, '\', '/');
else
    relParts = [repmat({'..'}, 1, numel(baseParts) - common), targetParts(common+1:end)];
    if isempty(relParts)
        out = '.';
    else
        out = strjoin(relParts, '/');
    end
end
out = htmlText(out);
end

function parts = splitPath(pathText)
pathText = strrep(char(pathText), '/', filesep);
parts = strsplit(pathText, filesep);
parts = parts(~cellfun('isempty', parts));
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
