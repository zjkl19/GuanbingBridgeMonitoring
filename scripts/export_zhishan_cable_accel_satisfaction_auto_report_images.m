function result = export_zhishan_cable_accel_satisfaction_auto_report_images()
%EXPORT_ZHISHAN_CABLE_ACCEL_SATISFACTION_AUTO_REPORT_IMAGES Export auto pick.
%   Copies the satisfaction-review automatic recommendation into one
%   neutral report-facing folder. This is display/report review only; no
%   formal calculation or configuration is modified.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
reviewDir = fullfile(stableDir, 'satisfaction_review');
currentDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([24403 21069 26368 20339 25512 33616 23637 31034])]);
cleanerDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26356 24178 20928 20248 20808 23637 31034])]);
cleanestDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26368 24178 20928 33258 21160 23637 31034])]);
outputDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28385 24847 24230 33258 21160 25512 33616 23637 31034])]);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

decision = readtable(fullfile(reviewDir, ...
    'CableAccelSatisfactionReview_decision.csv'), 'Encoding', 'UTF-8');
reviewManifest = readtable(fullfile(reviewDir, ...
    'CableAccelSatisfactionReview_manifest.csv'), 'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    decisionRow = rowFor(decision, 'PointID', pointId);
    selectedTier = decisionRow.AutoReviewRecommendation{1};
    manifestRow = rowForTier(reviewManifest, pointId, selectedTier);

    src = sourceImageForTier(selectedTier, currentDir, cleanerDir, ...
        cleanestDir, pointId);
    dst = fullfile(outputDir, sprintf( ...
        'CableAccelSatisfactionAutoReport_%s_20260301_20260331.jpg', pointId));
    copyfile(src, dst, 'f');
    plotPaths{i} = dst;

    rows(end+1, :) = {pointId, selectedTier, manifestRow.SourceTier{1}, ...
        manifestRow.KeepPct(1), manifestRow.RMS30Max(1), ...
        manifestRow.RMS30MaxImprovementVsCurrentBestPct(1), ...
        decisionRow.Reason{1}, src, dst}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedReviewTier','SourceTier','KeepPct','RMS30Max', ...
    'RMS30MaxImprovementVsCurrentBestPct','Reason','SourcePlotPath','PlotPath'});

contactSheetPath = buildContactSheet(plotPaths, manifest, outputDir, ...
    'CableAccelSatisfactionAutoReport_ContactSheet.jpg');
reviewBoardPath = buildContactSheet(plotPaths, manifest, outputDir, ...
    'CableAccelSatisfactionAutoReport_ReviewBoard.jpg');
manifestPath = fullfile(outputDir, 'CableAccelSatisfactionAutoReport_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelSatisfactionAutoReport_manifest.csv');
readmePath = fullfile(outputDir, 'README.md');
htmlPath = fullfile(outputDir, 'index.html');

writetable(manifest, manifestPath, 'Sheet', 'manifest');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');
writeReadme(readmePath, manifest, contactSheetPath, reviewBoardPath);
writeHtml(htmlPath, manifest, contactSheetPath, reviewBoardPath);

result = struct();
result.output_dir = outputDir;
result.manifest = manifestPath;
result.manifest_csv = manifestCsvPath;
result.readme = readmePath;
result.html = htmlPath;
result.contact_sheet = contactSheetPath;
result.review_board = reviewBoardPath;

fprintf('satisfaction auto report output dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('html %s\n', htmlPath);
disp(manifest(:, {'PointID','SelectedReviewTier','KeepPct','RMS30Max', ...
    'RMS30MaxImprovementVsCurrentBestPct'}));
end

function r = rowFor(T, key, value)
idx = find(strcmp(T.(key), value), 1);
if isempty(idx)
    error('Missing row where %s=%s.', key, value);
end
r = T(idx, :);
end

function r = rowForTier(T, pointId, selectedTier)
idx = find(strcmp(T.PointID, pointId) & strcmp(T.ReviewTier, selectedTier), 1);
if isempty(idx)
    error('Missing review row for %s / %s.', pointId, selectedTier);
end
r = T(idx, :);
end

function path = sourceImageForTier(tier, currentDir, cleanerDir, cleanestDir, pointId)
switch char(tier)
    case 'current_best'
        path = fullfile(currentDir, sprintf( ...
            'CableAccelCurrentBestReport_%s_20260301_20260331.jpg', pointId));
    case 'cleaner_priority'
        path = fullfile(cleanerDir, sprintf( ...
            'CableAccelDecisiveVisualReport_%s_20260301_20260331.jpg', pointId));
    case 'cleanest70'
        path = fullfile(cleanestDir, sprintf( ...
            'CableAccelCleanest70Report_%s_20260301_20260331.jpg', pointId));
    otherwise
        error('Unknown satisfaction tier %s.', char(tier));
end
if ~isfile(path)
    error('Missing source image %s.', path);
end
end

function outPath = buildContactSheet(plotPaths, manifest, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 2200 1500], 'Color', 'w');
tiledlayout(fig, 2, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
for i = 1:numel(plotPaths)
    ax = nexttile;
    image(ax, imread(plotPaths{i}));
    axis(ax, 'image');
    axis(ax, 'off');
    title(ax, sprintf('%s | %s | keep %.1f%% | RMS30 %.2f', ...
        manifest.PointID{i}, manifest.SelectedReviewTier{i}, ...
        manifest.KeepPct(i), manifest.RMS30Max(i)), 'Interpreter', 'none');
end
outPath = fullfile(outputDir, fileName);
exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function writeReadme(path, manifest, contactSheetPath, reviewBoardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Satisfaction Auto Report Images\n\n');
fprintf(fid, '- Open `index.html` for visual review.\n');
fprintf(fid, '- Manifest: `CableAccelSatisfactionAutoReport_manifest.xlsx`\n');
fprintf(fid, '- Contact sheet: `%s`\n', localFileName(contactSheetPath));
fprintf(fid, '- Review board: `%s`\n\n', localFileName(reviewBoardPath));
fprintf(fid, 'Rule: use the automatic recommendation from `satisfaction_review`.\n');
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n');
fprintf(fid, 'This folder is display/report review only.\n\n');
fprintf(fid, '| Point | Selected review tier | Keep %% | RMS30 max | Improve %% | Image |\n');
fprintf(fid, '|---|---|---:|---:|---:|---|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %.3f | %.3f | %.1f | `%s` |\n', ...
        manifest.PointID{i}, manifest.SelectedReviewTier{i}, ...
        manifest.KeepPct(i), manifest.RMS30Max(i), ...
        manifest.RMS30MaxImprovementVsCurrentBestPct(i), ...
        localFileName(manifest.PlotPath{i}));
end
end

function writeHtml(path, manifest, contactSheetPath, reviewBoardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Satisfaction Auto Report Images</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #2563eb;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.current_best{background:#eef6ff}.cleaner_priority{background:#fff7ed}.cleanest70{background:#fee2e2}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Satisfaction Auto Report Images</h1>\n');
fprintf(fid, '<div class="note">This folder copies the automatic recommendation from the satisfaction review into one report-facing image set. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>.</div>\n');
fprintf(fid, '<h2>Automatic Selection</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Selected review tier</th><th>Source tier</th><th>Keep %%</th><th>RMS30 max</th><th>Improve %%</th><th>Reason</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        htmlText(manifest.SelectedReviewTier{i}), htmlText(manifest.PointID{i}), ...
        htmlText(manifest.SelectedReviewTier{i}), htmlText(manifest.SourceTier{i}), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), ...
        manifest.RMS30MaxImprovementVsCurrentBestPct(i), ...
        htmlText(manifest.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Contact Sheet</h2>\n<div class="figure"><img src="%s" alt="contact sheet"></div>\n', ...
    htmlText(localFileName(contactSheetPath)));
fprintf(fid, '<h2>Review Board</h2>\n<div class="figure"><img src="%s" alt="review board"></div>\n', ...
    htmlText(localFileName(reviewBoardPath)));
fprintf(fid, '<h2>Per-Point Images</h2><div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s | %s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(manifest.SelectedReviewTier{i}), ...
        htmlText(localFileName(manifest.PlotPath{i})), htmlText(manifest.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
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
