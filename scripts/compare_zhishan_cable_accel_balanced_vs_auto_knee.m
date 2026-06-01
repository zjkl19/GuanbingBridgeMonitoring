function result = compare_zhishan_cable_accel_balanced_vs_auto_knee()
%COMPARE_ZHISHAN_CABLE_ACCEL_BALANCED_VS_AUTO_KNEE Build side-by-side review.
%   Compares the balanced final display images with auto-knee report images.
%   This is display-only and does not change formal calculations.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
balancedReportDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' ...
    char([26368 32456 25512 33616 23637 31034])]);
autoKneeReportDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_auto_knee_' ...
    char([25512 33616 23637 31034])]);
outputDir = fullfile(stableDir, 'balanced_vs_auto_knee_review');
plotDir = fullfile(outputDir, 'plots');
if ~exist(plotDir, 'dir'), mkdir(plotDir); end

balanced = readtable(fullfile(balancedReportDir, 'CableAccelFinalDisplay_manifest.csv'), ...
    'Encoding', 'UTF-8');
autoKnee = readtable(fullfile(autoKneeReportDir, 'CableAccelAutoKneeReport_manifest.csv'), ...
    'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    bIdx = find(strcmp(balanced.PointID, pointId), 1);
    aIdx = find(strcmp(autoKnee.PointID, pointId), 1);
    if isempty(bIdx) || isempty(aIdx)
        error('Missing balanced or auto-knee row for %s.', pointId);
    end
    balancedImage = fullfile(balancedReportDir, sprintf( ...
        'CableAccelFinalDisplay_%s_20260301_20260331.jpg', pointId));
    autoKneeImage = fullfile(autoKneeReportDir, sprintf( ...
        'CableAccelAutoKneeReport_%s_20260301_20260331.jpg', pointId));
    plotPaths{i} = buildSideBySide(plotDir, pointId, balancedImage, autoKneeImage);
    keepDelta = autoKnee.KeepPct(aIdx) - balanced.KeepPct(bIdx);
    rmsDelta = balanced.RMS30Max(bIdx) - autoKnee.RMS30Max(aIdx);
    rmsDeltaPct = 100 * rmsDelta / max(balanced.RMS30Max(bIdx), eps);
    decision = 'same as balanced';
    if strcmp(autoKnee.SelectedSource{aIdx}, 'auto_knee')
        decision = 'auto-knee cleaner';
    end
    rows(end+1, :) = {pointId, autoKnee.SelectedSource{aIdx}, ...
        balanced.KeepPct(bIdx), autoKnee.KeepPct(aIdx), keepDelta, ...
        balanced.RMS30Max(bIdx), autoKnee.RMS30Max(aIdx), rmsDelta, ...
        rmsDeltaPct, decision, plotPaths{i}}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','AutoKneeSource','BalancedKeepPct','AutoKneeKeepPct', ...
    'KeepDeltaPct','BalancedRMS30Max','AutoKneeRMS30Max', ...
    'RMS30MaxDelta','RMS30MaxDeltaPct','Decision','PlotPath'});

manifestXlsx = fullfile(outputDir, 'CableAccelBalancedVsAutoKnee_manifest.xlsx');
manifestCsv = fullfile(outputDir, 'CableAccelBalancedVsAutoKnee_manifest.csv');
contactSheet = buildReviewBoard(plotPaths, points, outputDir, 'CableAccelBalancedVsAutoKnee_ContactSheet.jpg');
htmlPath = fullfile(outputDir, 'index.html');
readmePath = fullfile(outputDir, 'README.md');
writetable(manifest, manifestXlsx, 'Sheet', 'comparison');
writetable(manifest, manifestCsv, 'Encoding', 'UTF-8');
writeHtml(htmlPath, manifest, contactSheet);
writeReadme(readmePath, manifest);

result = struct();
result.output_dir = outputDir;
result.html = htmlPath;
result.manifest = manifestXlsx;
result.manifest_csv = manifestCsv;
result.contact_sheet = contactSheet;

fprintf('balanced vs auto-knee html %s\n', htmlPath);
fprintf('balanced vs auto-knee manifest %s\n', manifestXlsx);
disp(manifest(:, {'PointID','AutoKneeSource','KeepDeltaPct','RMS30MaxDeltaPct','Decision'}));
end

function outPath = buildSideBySide(plotDir, pointId, balancedImage, autoKneeImage)
left = imread(balancedImage);
right = imread(autoKneeImage);
targetHeight = min(size(left, 1), size(right, 1));
left = imresize(left, [targetHeight NaN]);
right = imresize(right, [targetHeight NaN]);
pad = uint8(255 * ones(targetHeight, 24, 3));
canvas = [left pad right];

fig = figure('Visible', 'off', 'Position', [100 100 1800 760]);
ax = axes(fig);
image(ax, canvas);
axis(ax, 'image');
axis(ax, 'off');
title(ax, sprintf('%s | left: balanced final | right: auto-knee', pointId), ...
    'Interpreter', 'none');
outPath = fullfile(plotDir, sprintf('CableAccelBalancedVsAutoKnee_%s.jpg', pointId));
exportgraphics(fig, outPath, 'Resolution', 150);
close(fig);
end

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
boardPath = fullfile(outputDir, fileName);
nCols = 2;
nRows = ceil(numel(points) / nCols);
tileWidth = 1150;
pad = 28;
tiles = cell(numel(points), 1);
tileHeights = zeros(numel(points), 1);
for i = 1:numel(points)
    if isempty(plotPaths{i}) || ~isfile(plotPaths{i})
        img = uint8(255 * ones(520, tileWidth, 3));
    else
        img = ensureRgb(imread(plotPaths{i}));
        img = imresize(img, [NaN tileWidth]);
    end
    tiles{i} = img;
    tileHeights(i) = size(img, 1);
end
tileHeight = max(tileHeights);
canvas = uint8(255 * ones(nRows * tileHeight + (nRows + 1) * pad, ...
    nCols * tileWidth + (nCols + 1) * pad, 3));
for i = 1:numel(tiles)
    row = floor((i - 1) / nCols) + 1;
    col = mod(i - 1, nCols) + 1;
    img = tiles{i};
    y0 = pad + (row - 1) * (tileHeight + pad) + 1;
    x0 = pad + (col - 1) * (tileWidth + pad) + 1;
    yOffset = floor((tileHeight - size(img, 1)) / 2);
    y = y0 + yOffset;
    canvas(y:y + size(img, 1) - 1, x0:x0 + size(img, 2) - 1, :) = img;
end
imwrite(canvas, boardPath);
end

function img = ensureRgb(img)
if ndims(img) == 2
    img = repmat(img, 1, 1, 3);
elseif size(img, 3) == 4
    img = img(:, :, 1:3);
end
end

function writeHtml(path, manifest, contactSheet)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Balanced vs Auto-Knee</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #7c3aed;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.cleaner{background:#f4edff}.same{background:#eaf7f2}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(620px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Balanced Final vs Auto-Knee Review</h1>\n');
fprintf(fid, '<div class="note">Left side is balanced final; right side is auto-knee. This page is for visual choice only. Formal spectrum/force calculation remains unchanged.</div>\n');
fprintf(fid, '<h2>Comparison Summary</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Auto source</th><th>Keep delta %%</th><th>RMS30 max delta %%</th><th>Decision</th></tr>\n');
for i = 1:height(manifest)
    cls = 'same';
    if strcmp(manifest.AutoKneeSource{i}, 'auto_knee'), cls = 'cleaner'; end
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        cls, htmlText(manifest.PointID{i}), htmlText(manifest.AutoKneeSource{i}), ...
        manifest.KeepDeltaPct(i), manifest.RMS30MaxDeltaPct(i), htmlText(manifest.Decision{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheet)));
fprintf(fid, '<h2>Per-Point Side-by-Side</h2><div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="plots/%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(localFileName(manifest.PlotPath{i})), ...
        htmlText(manifest.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function writeReadme(path, manifest)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Balanced vs Auto-Knee Review\n\n');
fprintf(fid, '- Left side is balanced final; right side is auto-knee.\n');
fprintf(fid, '- Open `index.html` for visual review.\n');
fprintf(fid, '- Manifest: `CableAccelBalancedVsAutoKnee_manifest.xlsx`\n\n');
fprintf(fid, 'Formal spectrum/force calculation remains unchanged.\n\n');
fprintf(fid, '| Point | Auto source | Keep delta %% | RMS30 max delta %% | Decision |\n');
fprintf(fid, '|---|---|---:|---:|---|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %.3f | %.1f | %s |\n', ...
        manifest.PointID{i}, manifest.AutoKneeSource{i}, ...
        manifest.KeepDeltaPct(i), manifest.RMS30MaxDeltaPct(i), ...
        manifest.Decision{i});
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
