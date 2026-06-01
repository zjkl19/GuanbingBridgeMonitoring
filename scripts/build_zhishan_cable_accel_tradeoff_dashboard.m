function result = build_zhishan_cable_accel_tradeoff_dashboard()
%BUILD_ZHISHAN_CABLE_ACCEL_TRADEOFF_DASHBOARD Plot keep/RMS tradeoffs.
%   Display-only dashboard for choosing a satisfactory cable-acceleration
%   threshold set. Formal spectrum/force calculation is not changed.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
outputDir = fullfile(stableDir, 'tradeoff_dashboard');
plotDir = fullfile(outputDir, 'plots');
if ~exist(plotDir, 'dir'), mkdir(plotDir); end

ladder = readtable(fullfile(stableDir, 'keep_ladder_review', ...
    'CableAccelKeepLadder_manifest.csv'), 'Encoding', 'UTF-8');
finalPick = readtable(fullfile(stableDir, 'CableAccelFinalDisplay_rules.csv'), ...
    'Encoding', 'UTF-8');
polished = readtable(fullfile(stableDir, 'polished_min90_display_pick', ...
    'CableAccelPolishedMin90_manifest.csv'), 'Encoding', 'UTF-8');

points = unique(ladder.PointID, 'stable');
rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    pointRows = ladder(strcmp(ladder.PointID, pointId), :);
    finalIdx = find(strcmp(finalPick.PointID, pointId), 1);
    polishedIdx = find(strcmp(polished.PointID, pointId), 1);
    if isempty(finalIdx) || isempty(polishedIdx)
        error('Missing final or polished row for %s.', pointId);
    end
    selected = selectKnee(pointRows, finalPick(finalIdx, :));
    plotPaths{i} = plotTradeoff(plotDir, pointId, pointRows, ...
        finalPick(finalIdx, :), polished(polishedIdx, :), selected);
    rows(end+1, :) = {pointId, selected.KeepTargetPct, selected.Strategy{1}, ...
        selected.ThresholdAbsMps2, selected.SegmentFilterTopPctRMS30, ...
        selected.KeepPct, selected.RMS30Max, finalPick.KeepPct(finalIdx), ...
        finalPick.RMS30Max(finalIdx), polished.KeepPct(polishedIdx), ...
        polished.RMS30Max(polishedIdx), plotPaths{i}}; %#ok<AGROW>
end

summary = cell2table(rows, 'VariableNames', { ...
    'PointID','SuggestedKeepTargetPct','SuggestedStrategy', ...
    'SuggestedThresholdAbsMps2','SuggestedSegmentFilterTopPctRMS30', ...
    'SuggestedKeepPct','SuggestedRMS30Max','FinalKeepPct', ...
    'FinalRMS30Max','PolishedKeepPct','PolishedRMS30Max','PlotPath'});
summary.RMS30DeltaVsFinalPct = 100 * (summary.FinalRMS30Max - summary.SuggestedRMS30Max) ./ max(summary.FinalRMS30Max, eps);
summary.KeepDeltaVsFinalPct = summary.SuggestedKeepPct - summary.FinalKeepPct;

manifestXlsx = fullfile(outputDir, 'CableAccelTradeoffDashboard_suggestions.xlsx');
manifestCsv = fullfile(outputDir, 'CableAccelTradeoffDashboard_suggestions.csv');
writetable(summary, manifestXlsx, 'Sheet', 'suggestions');
writetable(summary, manifestCsv, 'Encoding', 'UTF-8');

contactSheet = buildReviewBoard(plotPaths, points, outputDir, 'CableAccelTradeoffDashboard_ContactSheet.jpg');
htmlPath = fullfile(outputDir, 'index.html');
readmePath = fullfile(outputDir, 'README.md');
writeHtml(htmlPath, summary, contactSheet);
writeReadme(readmePath, summary);

result = struct();
result.output_dir = outputDir;
result.html = htmlPath;
result.manifest = manifestXlsx;
result.manifest_csv = manifestCsv;
result.contact_sheet = contactSheet;

fprintf('tradeoff dashboard html %s\n', htmlPath);
fprintf('tradeoff dashboard manifest %s\n', manifestXlsx);
disp(summary(:, {'PointID','SuggestedKeepTargetPct','SuggestedKeepPct','SuggestedRMS30Max','RMS30DeltaVsFinalPct','KeepDeltaVsFinalPct'}));
end

function selected = selectKnee(pointRows, finalRow)
eligible = pointRows(pointRows.KeepPct >= 90, :);
if isempty(eligible)
    eligible = pointRows;
end
eligible = sortrows(eligible, {'KeepPct','RMS30Max'}, {'descend','ascend'});
finalKeep = finalRow.KeepPct;
finalRms = finalRow.RMS30Max;
improvementPct = 100 * (finalRms - eligible.RMS30Max) ./ max(finalRms, eps);
keepDeltaPct = eligible.KeepPct - finalKeep;
dataLossPct = max(0, -keepDeltaPct);
keepGainPct = max(0, keepDeltaPct);
score = improvementPct - 5.5 * dataLossPct + 0.5 * keepGainPct;
score(improvementPct < -0.5) = -Inf;

if isempty(score) || all(~isfinite(score)) || max(score) < 2
    selected = finalAsSelected(finalRow);
    return;
end
[~, idx] = max(score);
selected = eligible(idx, :);
end

function selected = finalAsSelected(finalRow)
selected = table();
selected.PointID = finalRow.PointID;
selected.KeepTargetPct = NaN;
selected.ThresholdAbsMps2 = finalRow.ThresholdAbsMps2;
selected.SegmentFilterTopPctRMS30 = finalRow.SegmentFilterTopPctRMS30;
selected.Strategy = strcat({'balanced final: '}, finalRow.Strategy);
selected.BaseFiniteCount = NaN;
selected.KeepPct = finalRow.KeepPct;
selected.RMS30Max = finalRow.RMS30Max;
selected.RMS30P95 = NaN;
selected.AcceptancePass = true;
selected.Rationale = {'keep balanced final; no stricter candidate has enough net gain'};
selected.PlotPath = {''};
end

function plotPath = plotTradeoff(plotDir, pointId, ladderRows, finalRow, polishedRow, selected)
fig = figure('Visible', 'off', 'Position', [100 100 950 700]);
ax = axes(fig);
hold(ax, 'on');
ladderRows = sortrows(ladderRows, 'KeepPct', 'descend');
plot(ax, ladderRows.KeepPct, ladderRows.RMS30Max, '-o', ...
    'Color', [0.10 0.33 0.58], 'MarkerFaceColor', [0.66 0.82 0.95], ...
    'LineWidth', 1.4, 'DisplayName', 'keep ladder');
scatter(ax, finalRow.KeepPct, finalRow.RMS30Max, 90, 's', ...
    'MarkerFaceColor', [0.10 0.62 0.36], 'MarkerEdgeColor', 'none', ...
    'DisplayName', 'balanced final');
scatter(ax, polishedRow.KeepPct, polishedRow.RMS30Max, 90, 'd', ...
    'MarkerFaceColor', [0.86 0.48 0.12], 'MarkerEdgeColor', 'none', ...
    'DisplayName', 'polished min90');
scatter(ax, selected.KeepPct, selected.RMS30Max, 130, 'p', ...
    'MarkerFaceColor', [0.72 0.12 0.18], 'MarkerEdgeColor', 'none', ...
    'DisplayName', 'auto knee');

for i = 1:height(ladderRows)
    text(ax, ladderRows.KeepPct(i), ladderRows.RMS30Max(i), ...
        sprintf(' %.0f%%', ladderRows.KeepTargetPct(i)), ...
        'FontSize', 8, 'Color', [0.20 0.24 0.30]);
end
hold(ax, 'off');
grid(ax, 'on');
xlabel(ax, 'keep rate (%)');
ylabel(ax, 'RMS30 max (m/s^2)');
title(ax, sprintf('%s keep/RMS tradeoff | lower-left is cleaner', pointId), ...
    'Interpreter', 'none');
legend(ax, 'Location', 'northeast', 'Box', 'off');
set(ax, 'XDir', 'normal');
padX = max(range(ladderRows.KeepPct) * 0.08, 0.6);
padY = max(range(ladderRows.RMS30Max) * 0.10, 0.5);
xlim(ax, [min(ladderRows.KeepPct) - padX, max(ladderRows.KeepPct) + padX]);
ylim(ax, [max(0, min(ladderRows.RMS30Max) - padY), max(ladderRows.RMS30Max) + padY]);

if isnan(selected.KeepTargetPct)
    note = sprintf('suggested: balanced final | keep %.2f%% | RMS %.2f', ...
        selected.KeepPct, selected.RMS30Max);
else
    note = sprintf('suggested: keep>=%.0f%% | keep %.2f%% | RMS %.2f', ...
        selected.KeepTargetPct, selected.KeepPct, selected.RMS30Max);
end
annotation(fig, 'textbox', [0.12 0.01 0.78 0.06], 'String', note, ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'Interpreter', 'none', 'FontSize', 11);

plotPath = fullfile(plotDir, sprintf('CableAccelTradeoff_%s.jpg', pointId));
exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
end

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 1800 1400]);
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

function writeHtml(path, summary, contactSheet)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Tradeoff Dashboard</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #7c3aed;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Keep/RMS Tradeoff Dashboard</h1>\n');
fprintf(fid, '<div class="note">Display-only tradeoff view. The red star is an automatic knee suggestion from the keep-rate ladder. Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.</div>\n');
fprintf(fid, '<h2>Suggested Knee Points</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Keep target</th><th>Strategy</th><th>Keep %%</th><th>RMS30 max</th><th>RMS delta vs final %%</th><th>Keep delta vs final %%</th></tr>\n');
for i = 1:height(summary)
    fprintf(fid, '<tr><td>%s</td><td class="num">%.0f</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%.2f</td></tr>\n', ...
        htmlText(summary.PointID{i}), summary.SuggestedKeepTargetPct(i), ...
        htmlText(summary.SuggestedStrategy{i}), summary.SuggestedKeepPct(i), ...
        summary.SuggestedRMS30Max(i), summary.RMS30DeltaVsFinalPct(i), ...
        summary.KeepDeltaVsFinalPct(i));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheet)));
fprintf(fid, '<h2>Per-Point Tradeoffs</h2><div class="grid">\n');
for i = 1:height(summary)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="plots/%s" alt="%s"></div>\n', ...
        htmlText(summary.PointID{i}), htmlText(localFileName(summary.PlotPath{i})), ...
        htmlText(summary.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function writeReadme(path, summary)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Tradeoff Dashboard\n\n');
fprintf(fid, '- Display-only keep/RMS tradeoff view.\n');
fprintf(fid, '- Open `index.html` for visual review.\n');
fprintf(fid, '- Suggestions: `CableAccelTradeoffDashboard_suggestions.xlsx`\n\n');
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Keep target | Strategy | Keep %% | RMS30 max | RMS delta vs final %% | Keep delta vs final %% |\n');
fprintf(fid, '|---|---:|---|---:|---:|---:|---:|\n');
for i = 1:height(summary)
    fprintf(fid, '| %s | %.0f | %s | %.3f | %.3f | %.1f | %.2f |\n', ...
        summary.PointID{i}, summary.SuggestedKeepTargetPct(i), ...
        summary.SuggestedStrategy{i}, summary.SuggestedKeepPct(i), ...
        summary.SuggestedRMS30Max(i), summary.RMS30DeltaVsFinalPct(i), ...
        summary.KeepDeltaVsFinalPct(i));
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
