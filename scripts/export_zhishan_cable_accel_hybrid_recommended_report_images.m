function result = export_zhishan_cable_accel_hybrid_recommended_report_images()
%EXPORT_ZHISHAN_CABLE_ACCEL_HYBRID_RECOMMENDED_REPORT_IMAGES Export hybrid pick.
%   Uses the low-keep auto report image by default, and switches only the
%   points marked review_extreme_tradeoff to the extreme fallback. This is
%   display/report review only.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
decisionPath = fullfile(stableDir, 'low_keep_vs_extreme_report', ...
    'CableAccelLowKeepVsExtreme_decision.csv');
outputDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([28151 21512 25512 33616 23637 31034])]);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

decision = readtable(decisionPath, 'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    d = rowFor(decision, 'PointID', pointId);
    if strcmp(d.Recommendation{1}, 'review_extreme_tradeoff')
        selectedPackage = 'extreme_fallback';
        selectedTier = d.ExtremeTier{1};
        keepPct = d.ExtremeKeepPct(1);
        rms30Max = d.ExtremeRMS30Max(1);
        sourcePlot = d.ExtremePlotPath{1};
        reason = sprintf('use extreme fallback: extra RMS30 gain %.1f%% for keep loss %.1f%%', ...
            d.ExtraRMS30GainPct(1), d.KeepLossPct(1));
    else
        selectedPackage = 'low_keep_auto';
        selectedTier = d.LowKeepTier{1};
        keepPct = d.LowKeepKeepPct(1);
        rms30Max = d.LowKeepRMS30Max(1);
        sourcePlot = d.LowKeepPlotPath{1};
        reason = sprintf('keep low-keep auto: extreme extra RMS30 gain %.1f%%, keep loss %.1f%%', ...
            d.ExtraRMS30GainPct(1), d.KeepLossPct(1));
    end
    if ~isfile(sourcePlot)
        error('Missing source image %s.', sourcePlot);
    end
    dst = fullfile(outputDir, sprintf( ...
        'CableAccelHybridRecommendedReport_%s_20260301_20260331.jpg', pointId));
    copyfile(sourcePlot, dst, 'f');
    plotPaths{i} = dst;

    rows(end+1, :) = {pointId, selectedPackage, selectedTier, ...
        keepPct, rms30Max, d.LowKeepKeepPct(1), d.LowKeepRMS30Max(1), ...
        d.ExtremeKeepPct(1), d.ExtremeRMS30Max(1), d.KeepLossPct(1), ...
        d.ExtraRMS30GainPct(1), d.Recommendation{1}, reason, ...
        sourcePlot, dst}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedPackage','SelectedTier','KeepPct','RMS30Max', ...
    'LowKeepKeepPct','LowKeepRMS30Max','ExtremeKeepPct', ...
    'ExtremeRMS30Max','KeepLossPct','ExtraRMS30GainPct', ...
    'DecisionRecommendation','Reason','SourcePlotPath','PlotPath'});

contactSheetPath = buildContactSheet(plotPaths, manifest, outputDir, ...
    'CableAccelHybridRecommendedReport_ContactSheet.jpg');
reviewBoardPath = buildContactSheet(plotPaths, manifest, outputDir, ...
    'CableAccelHybridRecommendedReport_ReviewBoard.jpg');
manifestPath = fullfile(outputDir, ...
    'CableAccelHybridRecommendedReport_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, ...
    'CableAccelHybridRecommendedReport_manifest.csv');
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

fprintf('hybrid recommended report output dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('html %s\n', htmlPath);
disp(manifest(:, {'PointID','SelectedPackage','SelectedTier', ...
    'KeepPct','RMS30Max','DecisionRecommendation'}));
end

function r = rowFor(T, key, value)
idx = find(strcmp(T.(key), value), 1);
if isempty(idx)
    error('Missing row where %s=%s.', key, value);
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
fprintf(fid, '# Zhishan Cable Acceleration Hybrid Recommended Report Images\n\n');
fprintf(fid, '- Open `index.html` for visual review.\n');
fprintf(fid, '- Manifest: `CableAccelHybridRecommendedReport_manifest.xlsx`\n');
fprintf(fid, '- Contact sheet: `%s`\n', localFileName(contactSheetPath));
fprintf(fid, '- Review board: `%s`\n\n', localFileName(reviewBoardPath));
fprintf(fid, 'Rule: use low-keep auto by default; switch only review_extreme_tradeoff points to extreme fallback.\n');
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
fprintf(fid, '<title>Zhishan Cable Acceleration Hybrid Recommended Report Images</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #2563eb;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.low_keep_auto{background:#dbeafe}.extreme_fallback{background:#fee2e2}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Hybrid Recommended Report Images</h1>\n');
fprintf(fid, '<div class="note">This package uses low-keep auto by default and switches only review_extreme_tradeoff points to the extreme fallback. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>.</div>\n');
fprintf(fid, '<h2>Automatic Selection</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Package</th><th>Tier</th><th>Keep %%</th><th>RMS30 max</th><th>Keep loss if extreme %%</th><th>Extra RMS30 gain %%</th><th>Reason</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        htmlText(manifest.SelectedPackage{i}), htmlText(manifest.PointID{i}), ...
        htmlText(manifest.SelectedPackage{i}), htmlText(manifest.SelectedTier{i}), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), ...
        manifest.KeepLossPct(i), manifest.ExtraRMS30GainPct(i), ...
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
