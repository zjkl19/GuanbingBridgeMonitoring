function result = export_zhishan_cable_accel_refined55_report_images()
%EXPORT_ZHISHAN_CABLE_ACCEL_REFINED55_REPORT_IMAGES Export refined candidate.
%   Starts from the hybrid recommendation, then uses the cleanest55 CF-8
%   candidate because it improves CF-8 without dropping to the 50% tier.
%   Display/report review only.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
hybridDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28151 21512 25512 33616 23637 31034])]);
outputDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28151 21512]) '55' char([25512 33616 23637 31034])]);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

hybrid = readtable(fullfile(hybridDir, ...
    'CableAccelHybridRecommendedReport_manifest.csv'), 'Encoding', 'UTF-8');
cleanest55 = readtable(fullfile(stableDir, 'cleanest55_display_export', ...
    'CableAccelCleanest55Display_manifest.csv'), 'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    h = rowFor(hybrid, pointId);
    selectedPackage = h.SelectedPackage{1};
    selectedTier = h.SelectedTier{1};
    keepPct = h.KeepPct(1);
    rms30Max = h.RMS30Max(1);
    sourcePlot = h.PlotPath{1};
    sourceManifest = 'hybrid_recommended_report';
    reason = h.Reason{1};
    if strcmp(pointId, 'CF-8')
        c55 = rowFor(cleanest55, pointId);
        selectedPackage = 'cleanest55_refinement';
        selectedTier = c55.SelectedTier{1};
        keepPct = c55.KeepPct(1);
        rms30Max = c55.RMS30Max(1);
        sourcePlot = c55.PlotPath{1};
        sourceManifest = 'cleanest55_display_export';
        reason = 'CF-8 uses cleanest55: cleaner than low-keep auto without dropping to the 50% tier';
    end
    if ~isfile(sourcePlot)
        error('Missing source image %s.', sourcePlot);
    end
    dst = fullfile(outputDir, sprintf( ...
        'CableAccelRefined55Report_%s_20260301_20260331.jpg', pointId));
    copyfile(sourcePlot, dst, 'f');
    plotPaths{i} = dst;
    rows(end+1, :) = {pointId, selectedPackage, selectedTier, ...
        sourceManifest, keepPct, rms30Max, reason, sourcePlot, dst}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedPackage','SelectedTier','SourceManifest', ...
    'KeepPct','RMS30Max','Reason','SourcePlotPath','PlotPath'});
contactSheetPath = buildContactSheet(plotPaths, manifest, outputDir, ...
    'CableAccelRefined55Report_ContactSheet.jpg');
reviewBoardPath = buildContactSheet(plotPaths, manifest, outputDir, ...
    'CableAccelRefined55Report_ReviewBoard.jpg');
manifestPath = fullfile(outputDir, 'CableAccelRefined55Report_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelRefined55Report_manifest.csv');
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

fprintf('refined55 report output dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('html %s\n', htmlPath);
disp(manifest(:, {'PointID','SelectedPackage','SelectedTier','KeepPct','RMS30Max'}));
end

function r = rowFor(T, pointId)
idx = find(strcmp(T.PointID, pointId), 1);
if isempty(idx)
    error('Missing row for %s.', pointId);
end
r = T(idx, :);
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
        manifest.PointID{i}, manifest.SelectedPackage{i}, ...
        manifest.KeepPct(i), manifest.RMS30Max(i)), 'Interpreter', 'none');
end
outPath = fullfile(outputDir, fileName);
exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function writeReadme(path, manifest, contactSheetPath, reviewBoardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Refined55 Report Images\n\n');
fprintf(fid, '- Open `index.html` for visual review.\n');
fprintf(fid, '- Manifest: `CableAccelRefined55Report_manifest.xlsx`\n');
fprintf(fid, '- Contact sheet: `%s`\n', localFileName(contactSheetPath));
fprintf(fid, '- Review board: `%s`\n\n', localFileName(reviewBoardPath));
fprintf(fid, 'Rule: start from hybrid recommended; switch CF-8 to cleanest55.\n');
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Package | Tier | Keep %% | RMS30 max | Reason |\n');
fprintf(fid, '|---|---|---|---:|---:|---|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %s | %.3f | %.3f | %s |\n', ...
        manifest.PointID{i}, manifest.SelectedPackage{i}, ...
        manifest.SelectedTier{i}, manifest.KeepPct(i), ...
        manifest.RMS30Max(i), manifest.Reason{i});
end
end

function writeHtml(path, manifest, contactSheetPath, reviewBoardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Refined55 Report Images</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #0f766e;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.low_keep_auto{background:#dbeafe}.extreme_fallback{background:#fee2e2}.cleanest55_refinement{background:#ccfbf1}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Refined55 Report Images</h1>\n');
fprintf(fid, '<div class="note">This package starts from hybrid recommended and switches CF-8 to cleanest55. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>.</div>\n');
fprintf(fid, '<h2>Automatic Selection</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Package</th><th>Tier</th><th>Source manifest</th><th>Keep %%</th><th>RMS30 max</th><th>Reason</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td>%s</td></tr>\n', ...
        htmlText(manifest.SelectedPackage{i}), htmlText(manifest.PointID{i}), ...
        htmlText(manifest.SelectedPackage{i}), htmlText(manifest.SelectedTier{i}), ...
        htmlText(manifest.SourceManifest{i}), manifest.KeepPct(i), ...
        manifest.RMS30Max(i), htmlText(manifest.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheetPath)));
fprintf(fid, '<h2>Review Board</h2><div class="figure"><img src="%s" alt="review board"></div>\n', htmlText(localFileName(reviewBoardPath)));
fprintf(fid, '<h2>Per-Point Images</h2><div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s | %s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(manifest.SelectedPackage{i}), ...
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
