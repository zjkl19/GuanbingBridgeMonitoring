function result = export_zhishan_cable_accel_auto_knee_report_images()
%EXPORT_ZHISHAN_CABLE_ACCEL_AUTO_KNEE_REPORT_IMAGES Export auto-knee report images.
%   Copies the auto-knee display candidate into a report-facing folder.
%   No formal spectrum/force calculation is recomputed or modified.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
autoKneeDir = fullfile(stableDir, 'auto_knee_display_pick');
outputDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_auto_knee_' ...
    char([25512 33616 23637 31034])]);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

sourceManifest = readtable(fullfile(autoKneeDir, 'CableAccelAutoKnee_manifest.csv'), ...
    'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

rows = {};
for i = 1:numel(points)
    pointId = points{i};
    idx = find(strcmp(sourceManifest.PointID, pointId), 1);
    if isempty(idx)
        error('Missing auto-knee row for %s.', pointId);
    end
    src = fullfile(autoKneeDir, 'plots', sprintf('CableAccelAutoKnee_%s.jpg', pointId));
    dst = fullfile(outputDir, sprintf( ...
        'CableAccelAutoKneeReport_%s_20260301_20260331.jpg', pointId));
    copyfile(src, dst, 'f');
    rows(end+1, :) = {pointId, sourceManifest.SelectedSource{idx}, ...
        sourceManifest.ThresholdAbsMps2(idx), ...
        sourceManifest.SegmentFilterTopPctRMS30(idx), ...
        sourceManifest.KeepPct(idx), sourceManifest.RMS30Max(idx), ...
        sourceManifest.FinalRMS30Max(idx), ...
        sourceManifest.RMS30MaxDeltaVsFinalPct(idx), ...
        sourceManifest.AcceptancePass(idx), sourceManifest.Rationale{idx}, dst}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedSource','ThresholdAbsMps2','SegmentFilterTopPctRMS30', ...
    'KeepPct','RMS30Max','FinalRMS30Max','RMS30MaxDeltaVsFinalPct', ...
    'AcceptancePass','Rationale','PlotPath'});

contactSheetPath = fullfile(outputDir, 'CableAccelAutoKneeReport_ContactSheet.jpg');
copyfile(fullfile(autoKneeDir, 'CableAccelAutoKnee_ContactSheet.jpg'), contactSheetPath, 'f');

manifestPath = fullfile(outputDir, 'CableAccelAutoKneeReport_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelAutoKneeReport_manifest.csv');
readmePath = fullfile(outputDir, 'README.md');
htmlPath = fullfile(outputDir, 'index.html');
writetable(manifest, manifestPath, 'Sheet', 'manifest');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');
writeReadme(readmePath, manifest, contactSheetPath);
writeHtml(htmlPath, manifest, contactSheetPath);

result = struct();
result.output_dir = outputDir;
result.manifest = manifestPath;
result.manifest_csv = manifestCsvPath;
result.readme = readmePath;
result.html = htmlPath;
result.contact_sheet = contactSheetPath;

fprintf('auto-knee report output dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('html %s\n', htmlPath);
disp(manifest(:, {'PointID','SelectedSource','ThresholdAbsMps2','SegmentFilterTopPctRMS30','KeepPct','RMS30Max','AcceptancePass'}));
end

function writeReadme(path, manifest, contactSheetPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Auto-Knee Report Images\n\n');
fprintf(fid, '- Open `index.html` for visual review.\n');
fprintf(fid, '- Manifest: `CableAccelAutoKneeReport_manifest.xlsx`\n');
fprintf(fid, '- Contact sheet: `%s`\n\n', localFileName(contactSheetPath));
fprintf(fid, 'Formal spectrum/force calculation remains unchanged. These are display/report images only.\n\n');
fprintf(fid, '| Point | Selected | |x| threshold | RMS30 top %% | Keep %% | RMS30 max | Pass | Image |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %.3f | %.1f | %.3f | %.3f | %d | `%s` |\n', ...
        manifest.PointID{i}, manifest.SelectedSource{i}, ...
        manifest.ThresholdAbsMps2(i), manifest.SegmentFilterTopPctRMS30(i), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), manifest.AcceptancePass(i), ...
        localFileName(manifest.PlotPath{i}));
end
end

function writeHtml(path, manifest, contactSheetPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Auto-Knee Report Images</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #7c3aed;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.auto_knee{background:#f4edff}.balanced_final{background:#eaf7f2}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230; Auto-Knee &#25253;&#21578;&#22270;</h1>\n');
fprintf(fid, '<div class="note">Auto-knee &#20505;&#36873;&#21482;&#25910;&#32039; CF-3/CF-4/CF-5&#65292;&#20854;&#20313;&#28857;&#20445;&#25345; balanced final&#12290;&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;&#12290;</div>\n');
fprintf(fid, '<h2>&#35268;&#21017; / Rules</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Selected</th><th>|x| threshold</th><th>RMS30 top %%</th><th>Keep %%</th><th>RMS30 max</th><th>Pass</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.1f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%d</td></tr>\n', ...
        htmlText(manifest.SelectedSource{i}), htmlText(manifest.PointID{i}), ...
        htmlText(manifest.SelectedSource{i}), manifest.ThresholdAbsMps2(i), ...
        manifest.SegmentFilterTopPctRMS30(i), manifest.KeepPct(i), ...
        manifest.RMS30Max(i), manifest.AcceptancePass(i));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>&#32039;&#20945;&#22797;&#26680; / Contact Sheet</h2>\n<div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheetPath)));
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
