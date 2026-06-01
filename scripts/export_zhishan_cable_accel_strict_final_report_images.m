function result = export_zhishan_cable_accel_strict_final_report_images()
%EXPORT_ZHISHAN_CABLE_ACCEL_STRICT_FINAL_REPORT_IMAGES Export final figures.
%   Copies the strict display/report-review candidate into a neutral
%   report-ready image folder. This is display/report review only; formal
%   cable acceleration spectrum/force calculation is not changed.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
strictDir = fullfile(stableDir, 'strict_report_candidate');
outputDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([20005 26684 26368 32456 25512 33616 23637 31034])]);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

strictManifest = readtable(fullfile(strictDir, ...
    'CableAccelStrictReport_manifest.csv'), 'Encoding', 'UTF-8');
strictDecision = readtable(fullfile(strictDir, ...
    'CableAccelStrictReport_decision.csv'), 'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    s = rowFor(strictManifest, 'PointID', pointId);
    d = rowFor(strictDecision, 'PointID', pointId);
    sourcePlot = asText(s.PlotPath);
    if ~isfile(sourcePlot)
        sourcePlot = fullfile(strictDir, 'images', sprintf( ...
            'CableAccelStrictReport_%s_20260301_20260331.jpg', pointId));
    end
    if ~isfile(sourcePlot)
        error('Missing strict source image for %s: %s.', pointId, sourcePlot);
    end
    dst = fullfile(outputDir, sprintf( ...
        'CableAccelStrictFinalReport_%s_20260301_20260331.jpg', pointId));
    copyfile(sourcePlot, dst, 'f');
    plotPaths{i} = dst;

    rows(end+1, :) = {pointId, s.Source{1}, s.ThresholdAbsMps2(1), ...
        s.SegmentFilterTopPctRMS30(1), s.KeepPct(1), s.RMS30Max(1), ...
        s.RMS30P95(1), s.BandWidthP95Median(1), ...
        s.KeepLossVsAutoPct(1), s.RMS30GainVsAutoPct(1), ...
        s.RMS30P95GainVsAutoPct(1), d.AutoClass{1}, s.Reason{1}, ...
        sourcePlot, dst}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedSource','ThresholdAbsMps2', ...
    'SegmentFilterTopPctRMS30','KeepPct','RMS30Max','RMS30P95', ...
    'BandWidthP95Median','KeepLossVsAutoPct','RMS30GainVsAutoPct', ...
    'RMS30P95GainVsAutoPct','AutoClass','Reason','SourcePlotPath', ...
    'PlotPath'});

contactSheetPath = buildContactSheet(plotPaths, manifest, outputDir, ...
    'CableAccelStrictFinalReport_ContactSheet.jpg');
reviewBoardPath = copyOrBuildReviewBoard(strictDir, plotPaths, manifest, ...
    outputDir, 'CableAccelStrictFinalReport_ReviewBoard.jpg');
manifestPath = fullfile(outputDir, 'CableAccelStrictFinalReport_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelStrictFinalReport_manifest.csv');
summaryJsonPath = fullfile(outputDir, 'CableAccelStrictFinalReport_summary.json');
readmePath = fullfile(outputDir, 'README.md');
htmlPath = fullfile(outputDir, 'index.html');

writetable(manifest, manifestPath, 'Sheet', 'manifest');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');
writeSummaryJson(summaryJsonPath, manifest);
writeReadme(readmePath, manifest, contactSheetPath, reviewBoardPath);
writeHtml(htmlPath, manifest, contactSheetPath, reviewBoardPath);

result = struct();
result.output_dir = outputDir;
result.manifest = manifestPath;
result.manifest_csv = manifestCsvPath;
result.summary_json = summaryJsonPath;
result.readme = readmePath;
result.html = htmlPath;
result.contact_sheet = contactSheetPath;
result.review_board = reviewBoardPath;

fprintf('strict final report output dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('html %s\n', htmlPath);
disp(manifest(:, {'PointID','SelectedSource','ThresholdAbsMps2', ...
    'SegmentFilterTopPctRMS30','KeepPct','RMS30Max'}));
end

function r = rowFor(T, key, value)
idx = find(strcmp(string(T.(key)), string(value)), 1);
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
        manifest.PointID{i}, manifest.SelectedSource{i}, ...
        manifest.KeepPct(i), manifest.RMS30Max(i)), 'Interpreter', 'none');
end
outPath = fullfile(outputDir, fileName);
exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function outPath = copyOrBuildReviewBoard(strictDir, plotPaths, manifest, ...
        outputDir, fileName)
src = fullfile(strictDir, 'CableAccelStrictReport_CompareBoard.jpg');
outPath = fullfile(outputDir, fileName);
if isfile(src)
    copyfile(src, outPath, 'f');
else
    outPath = buildContactSheet(plotPaths, manifest, outputDir, fileName);
end
end

function writeSummaryJson(path, manifest)
payload = struct();
payload.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
payload.scope = 'display_report_review_only';
payload.source_candidate = 'strict_report_candidate';
payload.formal_policy = 'daily_median + [-100,100] m/s^2';
payload.manifest = table2struct(manifest);
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(payload, 'PrettyPrint', true));
end

function writeReadme(path, manifest, contactSheetPath, reviewBoardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Strict Final Report Images\n\n');
fprintf(fid, '- Open `index.html` for visual review.\n');
fprintf(fid, '- Manifest: `CableAccelStrictFinalReport_manifest.xlsx`\n');
fprintf(fid, '- Contact sheet: `%s`\n', localFileName(contactSheetPath));
fprintf(fid, '- Review board: `%s`\n\n', localFileName(reviewBoardPath));
fprintf(fid, 'Source: `report_cable_accel_display_recommendation/strict_report_candidate`.\n');
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n\n');
fprintf(fid, '| Point | Source | Threshold | Drop top %% | Keep %% | RMS30 max | Reason |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %.3f | %.1f | %.3f | %.3f | %s |\n', ...
        manifest.PointID{i}, manifest.SelectedSource{i}, ...
        manifest.ThresholdAbsMps2(i), manifest.SegmentFilterTopPctRMS30(i), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), manifest.Reason{i});
end
end

function writeHtml(path, manifest, contactSheetPath, reviewBoardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Strict Final Report Images</title>\n');
writeCss(fid);
fprintf(fid, '</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration Strict Final Report Images</h1>\n');
fprintf(fid, '<div class="note">Report-ready copy of <code>strict_report_candidate</code>. Formal spectrum/force calculation remains <code>daily_median + [-100,100] m/s^2</code>.</div>\n');
fprintf(fid, '<h2>Selection</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Class</th><th>Source</th><th>|x| threshold</th><th>Drop top RMS30 %%</th><th>Keep %%</th><th>RMS30 max</th><th>Reason</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%.3f</td><td class="num">%.3f</td><td>%s</td></tr>\n', ...
        htmlText(manifest.AutoClass{i}), htmlText(manifest.PointID{i}), ...
        htmlText(manifest.AutoClass{i}), htmlText(manifest.SelectedSource{i}), ...
        manifest.ThresholdAbsMps2(i), manifest.SegmentFilterTopPctRMS30(i), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), ...
        htmlText(manifest.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheetPath)));
fprintf(fid, '<h2>Review Board</h2><div class="figure"><img src="%s" alt="review board"></div>\n', htmlText(localFileName(reviewBoardPath)));
fprintf(fid, '<h2>Per-Point Images</h2><div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s | %s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(manifest.SelectedSource{i}), ...
        htmlText(localFileName(manifest.PlotPath{i})), ...
        htmlText(manifest.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function writeCss(fid)
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #0f766e;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.severe_noise{background:#fee2e2}.moderate_noise{background:#fef3c7}.mixed_noise{background:#dbeafe}.stable_signal{background:#dcfce7}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n');
end

function text = asText(value)
if iscell(value)
    text = value{1};
elseif isstring(value)
    text = char(value(1));
else
    text = char(string(value));
end
end

function name = localFileName(pathText)
[~, base, ext] = fileparts(char(pathText));
name = [base ext];
end

function out = htmlText(value)
out = char(string(value));
out = strrep(out, '&', '&amp;');
out = strrep(out, '<', '&lt;');
out = strrep(out, '>', '&gt;');
out = strrep(out, '"', '&quot;');
end
