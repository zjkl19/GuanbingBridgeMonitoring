function result = compare_zhishan_cable_accel_low_keep_review()
%COMPARE_ZHISHAN_CABLE_ACCEL_LOW_KEEP_REVIEW Compare low-keep candidates.
%   Compares satisfaction-auto, cleanest60, and cleanest50 side by side,
%   and suggests the next review tier per point. Display/report review only.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
satisfactionDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28385 24847 24230 33258 21160 25512 33616 23637 31034])]);
cleanest60Dir = fullfile(stableDir, 'cleanest60_display_export');
cleanest50Dir = fullfile(stableDir, 'cleanest50_display_export');
outputDir = fullfile(stableDir, 'low_keep_tradeoff_review');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

satisfaction = readtable(fullfile(satisfactionDir, ...
    'CableAccelSatisfactionAutoReport_manifest.csv'), 'Encoding', 'UTF-8');
cleanest60 = readtable(fullfile(cleanest60Dir, ...
    'CableAccelCleanest60Display_manifest.csv'), 'Encoding', 'UTF-8');
cleanest50 = readtable(fullfile(cleanest50Dir, ...
    'CableAccelCleanest50Display_manifest.csv'), 'Encoding', 'UTF-8');

points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
rows = {};
plotRows = cell(numel(points), 3);
for i = 1:numel(points)
    pointId = points{i};
    s = rowFor(satisfaction, pointId);
    c60 = rowFor(cleanest60, pointId);
    c50 = rowFor(cleanest50, pointId);
    tiers = {
        'satisfaction_auto', s.SelectedReviewTier{1}, s.KeepPct, s.RMS30Max, ...
            0, satisfactionImage(satisfactionDir, pointId)
        'cleanest60', c60.SelectedTier{1}, c60.KeepPct, c60.RMS30Max, ...
            pctReduction(s.RMS30Max, c60.RMS30Max), cleanest60Image(cleanest60Dir, pointId)
        'cleanest50', c50.SelectedTier{1}, c50.KeepPct, c50.RMS30Max, ...
            pctReduction(s.RMS30Max, c50.RMS30Max), cleanest50Image(cleanest50Dir, pointId)
        };
    for j = 1:size(tiers, 1)
        rows(end+1, :) = {pointId, tiers{j, 1}, tiers{j, 2}, ...
            tiers{j, 3}, tiers{j, 4}, tiers{j, 5}, tiers{j, 6}}; %#ok<AGROW>
        plotRows{i, j} = tiers{j, 6};
    end
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','ReviewTier','SourceTier','KeepPct','RMS30Max', ...
    'RMS30MaxImprovementVsSatisfactionAutoPct','PlotPath'});
decision = buildDecision(manifest, points);
reviewBoard = buildReviewBoard(plotRows, points, outputDir, ...
    'CableAccelLowKeepTradeoff_Board.jpg');
manifestPath = fullfile(outputDir, 'CableAccelLowKeepTradeoff_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelLowKeepTradeoff_manifest.csv');
decisionCsvPath = fullfile(outputDir, 'CableAccelLowKeepTradeoff_decision.csv');
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

fprintf('low-keep tradeoff review %s\n', htmlPath);
disp(decision);
end

function r = rowFor(T, pointId)
idx = find(strcmp(T.PointID, pointId), 1);
if isempty(idx)
    error('Missing row for %s.', pointId);
end
r = T(idx, :);
end

function path = satisfactionImage(folder, pointId)
path = fullfile(folder, sprintf( ...
    'CableAccelSatisfactionAutoReport_%s_20260301_20260331.jpg', pointId));
assert(isfile(path), 'Missing image %s.', path);
end

function path = cleanest60Image(folder, pointId)
path = fullfile(folder, sprintf( ...
    'CableAccelCleanest60Display_%s_20260301_20260331.jpg', pointId));
assert(isfile(path), 'Missing image %s.', path);
end

function path = cleanest50Image(folder, pointId)
path = fullfile(folder, sprintf( ...
    'CableAccelCleanest50Display_%s_20260301_20260331.jpg', pointId));
assert(isfile(path), 'Missing image %s.', path);
end

function decision = buildDecision(manifest, points)
rows = {};
for i = 1:numel(points)
    pointId = points{i};
    P = manifest(strcmp(manifest.PointID, pointId), :);
    s = P(strcmp(P.ReviewTier, 'satisfaction_auto'), :);
    c60 = P(strcmp(P.ReviewTier, 'cleanest60'), :);
    c50 = P(strcmp(P.ReviewTier, 'cleanest50'), :);
    midGain = pctReduction(s.RMS30Max, c60.RMS30Max);
    extremeGain = pctReduction(c60.RMS30Max, c50.RMS30Max);
    if c60.KeepPct >= 60 && midGain >= 10
        recommended = 'cleanest60';
        reason = sprintf('cleanest60 improves RMS %.1f%% vs satisfaction-auto with keep %.1f%%', ...
            midGain, c60.KeepPct);
    else
        recommended = 'satisfaction_auto';
        reason = sprintf('satisfaction-auto is enough; cleanest60 gain %.1f%% with keep %.1f%%', ...
            midGain, c60.KeepPct);
    end
    if c50.KeepPct >= 50 && extremeGain >= 15
        fallback = 'cleanest50_extreme';
        fallbackReason = sprintf('cleanest50 adds %.1f%% RMS gain vs cleanest60 but keep is %.1f%%', ...
            extremeGain, c50.KeepPct);
    else
        fallback = 'none';
        fallbackReason = 'cleanest50 does not add enough gain to justify the extra data loss';
    end
    rows(end+1, :) = {pointId, s.KeepPct, s.RMS30Max, ...
        c60.KeepPct, c60.RMS30Max, midGain, c50.KeepPct, ...
        c50.RMS30Max, pctReduction(s.RMS30Max, c50.RMS30Max), ...
        recommended, reason, fallback, fallbackReason}; %#ok<AGROW>
end
decision = cell2table(rows, 'VariableNames', { ...
    'PointID','SatisfactionAutoKeepPct','SatisfactionAutoRMS30Max', ...
    'Cleanest60KeepPct','Cleanest60RMS30Max','Cleanest60GainPct', ...
    'Cleanest50KeepPct','Cleanest50RMS30Max','Cleanest50GainPct', ...
    'NextReviewRecommendation','Reason','ExtremeFallback','ExtremeFallbackReason'});
end

function boardPath = buildReviewBoard(plotRows, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 2400 3000], 'Color', 'w');
labels = {'satisfaction-auto', 'cleanest60', 'cleanest50'};
rows = numel(points);
cols = numel(labels);
marginX = 0.018;
marginY = 0.016;
gapX = 0.014;
gapY = 0.012;
tileW = (1 - 2 * marginX - (cols - 1) * gapX) / cols;
tileH = (1 - 2 * marginY - (rows - 1) * gapY) / rows;
for i = 1:numel(points)
    for j = 1:cols
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
fprintf(fid, '<title>Zhishan Cable Acceleration Low-Keep Tradeoff Review</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #b91c1c;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.satisfaction_auto{background:#dbeafe}.cleanest60{background:#fed7aa}.cleanest50{background:#fecaca}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .point{display:grid;grid-template-columns:repeat(3,minmax(360px,1fr));gap:12px;margin:18px 0 28px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Low-Keep Tradeoff Review</h1>\n');
fprintf(fid, '<div class="note">Compares satisfaction-auto, cleanest60, and cleanest50. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>. Lower keep tiers are review candidates only.</div>\n');
fprintf(fid, '<h2>Next Review Recommendation</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Satisfaction keep/RMS</th><th>Cleanest60 keep/RMS/gain</th><th>Cleanest50 keep/RMS/gain</th><th>Next</th><th>Reason</th><th>Extreme fallback</th></tr>\n');
for i = 1:height(decision)
    fprintf(fid, '<tr><td>%s</td><td class="num">%.2f / %.2f</td><td class="num">%.2f / %.2f / %.1f%%</td><td class="num">%.2f / %.2f / %.1f%%</td><td>%s</td><td>%s</td><td>%s: %s</td></tr>\n', ...
        htmlText(decision.PointID{i}), decision.SatisfactionAutoKeepPct(i), ...
        decision.SatisfactionAutoRMS30Max(i), decision.Cleanest60KeepPct(i), ...
        decision.Cleanest60RMS30Max(i), decision.Cleanest60GainPct(i), ...
        decision.Cleanest50KeepPct(i), decision.Cleanest50RMS30Max(i), ...
        decision.Cleanest50GainPct(i), htmlText(decision.NextReviewRecommendation{i}), ...
        htmlText(decision.Reason{i}), htmlText(decision.ExtremeFallback{i}), ...
        htmlText(decision.ExtremeFallbackReason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Review Board</h2><div class="figure"><img src="%s" alt="review board"></div>\n', htmlText(localFileName(reviewBoard)));
fprintf(fid, '<h2>Per-Point Side By Side</h2>\n');
points = unique(manifest.PointID, 'stable');
for i = 1:numel(points)
    P = manifest(strcmp(manifest.PointID, points{i}), :);
    fprintf(fid, '<h2>%s</h2><div class="point">\n', htmlText(points{i}));
    for j = 1:height(P)
        fprintf(fid, '<div class="figure %s"><h2>%s</h2><p>keep %.2f%% | RMS30 %.2f | gain %.1f%%</p><img src="%s" alt="%s %s"></div>\n', ...
            htmlText(P.ReviewTier{j}), htmlText(P.ReviewTier{j}), ...
            P.KeepPct(j), P.RMS30Max(j), ...
            P.RMS30MaxImprovementVsSatisfactionAutoPct(j), ...
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
fprintf(fid, '# Zhishan Cable Acceleration Low-Keep Tradeoff Review\n\n');
fprintf(fid, '- Open `index.html` for side-by-side review.\n');
fprintf(fid, '- Review board: `%s`\n\n', localFileName(reviewBoard));
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Next | Reason | Extreme fallback |\n');
fprintf(fid, '|---|---|---|---|\n');
for i = 1:height(decision)
    fprintf(fid, '| %s | %s | %s | %s: %s |\n', ...
        decision.PointID{i}, decision.NextReviewRecommendation{i}, ...
        decision.Reason{i}, decision.ExtremeFallback{i}, ...
        decision.ExtremeFallbackReason{i});
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
    return;
end
upCount = numel(baseParts) - common;
relParts = [repmat({'..'}, 1, upCount), targetParts(common+1:end)];
if isempty(relParts)
    out = localFileName(target);
else
    out = strjoin(relParts, '/');
end
out = htmlText(out);
end

function parts = splitPath(pathText)
pathText = strrep(char(pathText), '/', '\');
parts = regexp(pathText, '\\', 'split');
parts = parts(~cellfun(@isempty, parts));
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
