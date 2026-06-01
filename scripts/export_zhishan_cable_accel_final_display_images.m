function result = export_zhishan_cable_accel_final_display_images()
%EXPORT_ZHISHAN_CABLE_ACCEL_FINAL_DISPLAY_IMAGES Export final report images.
%   Copies the accepted balanced display pick into a report-ready final
%   output folder. No data cleaning or formal calculation is recomputed.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
balancedDir = fullfile(stableDir, 'balanced_display_pick');
outputDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26368 32456 25512 33616 23637 31034])]);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

rules = readtable(fullfile(stableDir, 'CableAccelFinalDisplay_rules.csv'), ...
    'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

plotPaths = cell(numel(points), 1);
rows = {};
for i = 1:numel(points)
    pointId = points{i};
    idx = find(strcmp(rules.PointID, pointId), 1);
    if isempty(idx)
        error('Missing final rule row for %s.', pointId);
    end
    src = fullfile(balancedDir, sprintf( ...
        'CableAccelBalancedDisplay_%s_20260301_20260331.jpg', pointId));
    dst = fullfile(outputDir, sprintf( ...
        'CableAccelFinalDisplay_%s_20260301_20260331.jpg', pointId));
    copyfile(src, dst, 'f');
    plotPaths{i} = dst;
    rows(end+1, :) = {pointId, rules.SelectedSource{idx}, rules.ThresholdAbsMps2(idx), ...
        rules.SegmentFilterTopPctRMS30(idx), rules.KeepPct(idx), ...
        rules.RMS30Max(idx), rules.AcceptancePass(idx), rules.Rationale{idx}, dst}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedSource','ThresholdAbsMps2','SegmentFilterTopPctRMS30', ...
    'KeepPct','RMS30Max','AcceptancePass','Rationale','PlotPath'});

contactSheetPath = fullfile(outputDir, 'CableAccelFinalDisplay_ContactSheet.jpg');
reviewBoardPath = fullfile(outputDir, 'CableAccelFinalDisplay_ReviewBoard.jpg');
copyfile(fullfile(balancedDir, 'CableAccelBalancedDisplay_ContactSheet.jpg'), contactSheetPath, 'f');
copyfile(fullfile(balancedDir, 'CableAccelBalancedDisplay_ReviewBoard.jpg'), reviewBoardPath, 'f');

manifestPath = fullfile(outputDir, 'CableAccelFinalDisplay_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelFinalDisplay_manifest.csv');
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

fprintf('final display output dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('html %s\n', htmlPath);
disp(manifest(:, {'PointID','SelectedSource','ThresholdAbsMps2','SegmentFilterTopPctRMS30','KeepPct','AcceptancePass'}));
end

function writeReadme(path, manifest, contactSheetPath, reviewBoardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Final Report Images\n\n');
fprintf(fid, '- Open `index.html` for visual review.\n');
fprintf(fid, '- Manifest: `CableAccelFinalDisplay_manifest.xlsx`\n');
fprintf(fid, '- Contact sheet: `%s`\n', localFileName(contactSheetPath));
fprintf(fid, '- Review board: `%s`\n\n', localFileName(reviewBoardPath));
fprintf(fid, 'Formal spectrum/force calculation remains unchanged. These are final display/report images.\n\n');
fprintf(fid, '| Point | Selected | |x| threshold | RMS30 top %% | Keep %% | Pass | Image |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %.3f | %.1f | %.3f | %d | `%s` |\n', ...
        manifest.PointID{i}, manifest.SelectedSource{i}, manifest.ThresholdAbsMps2(i), ...
        manifest.SegmentFilterTopPctRMS30(i), manifest.KeepPct(i), ...
        manifest.AcceptancePass(i), localFileName(manifest.PlotPath{i}));
end
end

function writeHtml(path, manifest, contactSheetPath, reviewBoardPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Final Report Images</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #067a46;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.cleaner{background:#eaf7f2}.current{background:#f4f6f8}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#26368;&#32456;&#25253;&#21578;&#22270; / Final Report Images</h1>\n');
fprintf(fid, '<div class="note">&#26412;&#30446;&#24405;&#26159;&#26368;&#32456;&#33258;&#21160;&#24179;&#34913;&#20505;&#36873;&#30340;&#25253;&#21578;&#21462;&#22270;&#29256;&#26412;&#12290;&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;&#12290;</div>\n');
fprintf(fid, '<h2>&#35268;&#21017; / Rules</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Selected</th><th>|x| threshold</th><th>RMS30 top %%</th><th>Keep %%</th><th>Pass</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%.3f</td><td class="num">%d</td></tr>\n', ...
        htmlText(manifest.SelectedSource{i}), htmlText(manifest.PointID{i}), ...
        htmlText(manifest.SelectedSource{i}), manifest.ThresholdAbsMps2(i), ...
        manifest.SegmentFilterTopPctRMS30(i), manifest.KeepPct(i), manifest.AcceptancePass(i));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>&#32039;&#20945;&#22797;&#26680; / Contact Sheet</h2>\n<div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheetPath)));
fprintf(fid, '<h2>&#24635;&#35272; / Review Board</h2>\n<div class="figure"><img src="%s" alt="review board"></div>\n', htmlText(localFileName(reviewBoardPath)));
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
