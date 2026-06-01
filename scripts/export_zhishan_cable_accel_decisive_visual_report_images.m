function result = export_zhishan_cable_accel_decisive_visual_report_images()
%EXPORT_ZHISHAN_CABLE_ACCEL_DECISIVE_VISUAL_REPORT_IMAGES Export cleaner images.
%   Copies the decisive visual backup into a neutral report-facing folder.
%   No formal calculation is recomputed or modified.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
sourceDir = fullfile(stableDir, 'decisive_visual_display_export');
outputDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26356 24178 20928 20248 20808 23637 31034])]);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

sourceManifest = readtable(fullfile(sourceDir, ...
    'CableAccelDecisiveVisualDisplay_manifest.csv'), 'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

rows = {};
for i = 1:numel(points)
    pointId = points{i};
    idx = find(strcmp(sourceManifest.PointID, pointId), 1);
    if isempty(idx)
        error('Missing decisive visual row for %s.', pointId);
    end

    src = fullfile(sourceDir, sprintf( ...
        'CableAccelDecisiveVisualDisplay_%s_20260301_20260331.jpg', pointId));
    if ~isfile(src)
        error('Missing decisive visual image %s.', src);
    end
    dst = fullfile(outputDir, sprintf( ...
        'CableAccelDecisiveVisualReport_%s_20260301_20260331.jpg', pointId));
    copyfile(src, dst, 'f');

    rows(end+1, :) = {pointId, sourceManifest.SelectedTier{idx}, ...
        sourceManifest.Strategy{idx}, sourceManifest.KeepPct(idx), ...
        sourceManifest.RMS30Max(idx), sourceManifest.RMS30P95(idx), ...
        sourceManifest.KeepDeltaVsCurrentBestPct(idx), ...
        sourceManifest.RMS30MaxImprovementVsCurrentBestPct(idx), ...
        sourceManifest.Reason{idx}, dst}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedTier','Strategy','KeepPct','RMS30Max','RMS30P95', ...
    'KeepDeltaVsCurrentBestPct','RMS30MaxImprovementVsCurrentBestPct', ...
    'Reason','PlotPath'});

contactSheetPath = fullfile(outputDir, 'CableAccelDecisiveVisualReport_ContactSheet.jpg');
reviewBoardPath = fullfile(outputDir, 'CableAccelDecisiveVisualReport_ReviewBoard.jpg');
copyfile(fullfile(sourceDir, 'CableAccelDecisiveVisualDisplay_ContactSheet.jpg'), ...
    contactSheetPath, 'f');
copyfile(fullfile(sourceDir, 'CableAccelDecisiveVisualDisplay_ReviewBoard.jpg'), ...
    reviewBoardPath, 'f');

manifestPath = fullfile(outputDir, 'CableAccelDecisiveVisualReport_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelDecisiveVisualReport_manifest.csv');
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

fprintf('decisive visual report output dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('html %s\n', htmlPath);
disp(manifest(:, {'PointID','SelectedTier','KeepPct','RMS30Max', ...
    'RMS30MaxImprovementVsCurrentBestPct'}));
end

function writeReadme(path, manifest, contactSheetPath, reviewBoardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Cleaner-Priority Report Images\n\n');
fprintf(fid, '- Open `index.html` for visual review.\n');
fprintf(fid, '- Manifest: `CableAccelDecisiveVisualReport_manifest.xlsx`\n');
fprintf(fid, '- Contact sheet: `%s`\n', localFileName(contactSheetPath));
fprintf(fid, '- Review board: `%s`\n\n', localFileName(reviewBoardPath));
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.\n');
fprintf(fid, 'This folder is a stricter display-only backup and should be used only after visual review.\n\n');
fprintf(fid, '| Point | Tier | Keep %% | RMS30 max | Improve %% | Image |\n');
fprintf(fid, '|---|---|---:|---:|---:|---|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %.3f | %.3f | %.1f | `%s` |\n', ...
        manifest.PointID{i}, manifest.SelectedTier{i}, manifest.KeepPct(i), ...
        manifest.RMS30Max(i), manifest.RMS30MaxImprovementVsCurrentBestPct(i), ...
        localFileName(manifest.PlotPath{i}));
end
end

function writeHtml(path, manifest, contactSheetPath, reviewBoardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Cleaner-Priority Report Images</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #b91c1c;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.target75{background:#fff1f2}.visual_best{background:#eaf7f2}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#26356;&#24178;&#20928;&#20248;&#20808;&#23637;&#31034;</h1>\n');
fprintf(fid, '<div class="note">&#36825;&#26159;&#26356;&#24178;&#20928;&#20248;&#20808;&#30340;&#23457;&#22270;&#22791;&#36873;&#65292;CF-1/CF-2/CF-5 &#20351;&#29992; target75&#65292;&#20854;&#20182;&#27979;&#28857;&#20351;&#29992; visual-best&#12290;&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;: <code>daily_median + [-100,100] m/s^2</code>&#12290;</div>\n');
fprintf(fid, '<h2>&#35268;&#21017; / Rules</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Tier</th><th>Strategy</th><th>Keep %%</th><th>RMS30 max</th><th>RMS30 P95</th><th>Improve %%</th><th>Reason</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        htmlText(manifest.SelectedTier{i}), htmlText(manifest.PointID{i}), ...
        htmlText(manifest.SelectedTier{i}), htmlText(manifest.Strategy{i}), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), manifest.RMS30P95(i), ...
        manifest.RMS30MaxImprovementVsCurrentBestPct(i), htmlText(manifest.Reason{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>&#32039;&#20945;&#22797;&#26680; / Contact Sheet</h2>\n<div class="figure"><img src="%s" alt="contact sheet"></div>\n', ...
    htmlText(localFileName(contactSheetPath)));
fprintf(fid, '<h2>&#23457;&#22270;&#24635;&#35272; / Review Board</h2>\n<div class="figure"><img src="%s" alt="review board"></div>\n', ...
    htmlText(localFileName(reviewBoardPath)));
fprintf(fid, '<h2>&#21333;&#28857;&#22270; / Per-Point Images</h2><div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(localFileName(manifest.PlotPath{i})), ...
        htmlText(manifest.PointID{i}));
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
