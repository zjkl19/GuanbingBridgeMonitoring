function result = build_zhishan_cable_accel_balanced_display_pick()
%BUILD_ZHISHAN_CABLE_ACCEL_BALANCED_DISPLAY_PICK Promote balanced display pick.
%   Selects cleaner for points with useful RMS improvement and at least
%   92% retention; otherwise keeps current recommendation. Display-only.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
reportDirName = [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' char([25512 33616 23637 31034])];
currentDir = fullfile(dataRoot, reportDirName);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
cleanerDir = fullfile(stableDir, 'cleaner_display_export');
compareDir = fullfile(stableDir, 'current_vs_cleaner_review');
outputDir = fullfile(stableDir, 'balanced_display_pick');
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

current = readtable(fullfile(currentDir, 'CableAccelRecommendationDisplay_manifest.csv'), ...
    'Encoding', 'UTF-8');
cleaner = readtable(fullfile(cleanerDir, 'CableAccelCleanerDisplay_manifest.csv'), ...
    'Encoding', 'UTF-8');
comparison = readtable(fullfile(compareDir, 'CableAccelCurrentVsCleaner_manifest.csv'), ...
    'Encoding', 'UTF-8');
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

minKeepPct = 92.0;
minImprovementPct = 2.0;
rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    cIdx = find(strcmp(current.PointID, pointId), 1);
    kIdx = find(strcmp(cleaner.PointID, pointId), 1);
    dIdx = find(strcmp(comparison.PointID, pointId), 1);
    if isempty(cIdx) || isempty(kIdx) || isempty(dIdx)
        error('Missing data row for %s.', pointId);
    end

    useCleaner = cleaner.KeepPct(kIdx) >= minKeepPct && ...
        (comparison.RMS30MaxImprovementPct(dIdx) >= minImprovementPct || ...
         comparison.RMS30P95ImprovementPct(dIdx) >= minImprovementPct);

    if useCleaner
        source = 'cleaner';
        selected = cleaner(kIdx, :);
        sourceImage = fullfile(cleanerDir, sprintf( ...
            'CableAccelCleanerDisplay_%s_20260301_20260331.jpg', pointId));
        rationale = sprintf('cleaner improves RMS with keep %.3f%% >= %.1f%%', ...
            cleaner.KeepPct(kIdx), minKeepPct);
    else
        source = 'current';
        selected = current(cIdx, :);
        sourceImage = fullfile(currentDir, sprintf( ...
            'CableAccelRecommendationDisplay_%s_20260301_20260331.jpg', pointId));
        rationale = 'cleaner has no material gain; keep current recommendation';
    end

    targetImage = fullfile(outputDir, sprintf( ...
        'CableAccelBalancedDisplay_%s_20260301_20260331.jpg', pointId));
    copyfile(sourceImage, targetImage, 'f');
    plotPaths{i} = targetImage;

    rows(end+1, :) = {pointId, source, selected.Strategy{1}, selected.KeepPct, ...
        selected.RMS30Max, selected.RMS30P95, comparison.KeepDeltaPct(dIdx), ...
        comparison.RMS30MaxImprovementPct(dIdx), comparison.RMS30P95ImprovementPct(dIdx), ...
        rationale, targetImage}; %#ok<AGROW>
end

pick = cell2table(rows, 'VariableNames', { ...
    'PointID','SelectedSource','Strategy','KeepPct','RMS30Max','RMS30P95', ...
    'CleanerKeepDeltaPct','CleanerRMS30MaxImprovementPct', ...
    'CleanerRMS30P95ImprovementPct','Rationale','PlotPath'});

contactSheetPath = buildContactSheet(plotPaths, points, outputDir, ...
    'CableAccelBalancedDisplay_ContactSheet.jpg');
reviewBoardPath = buildReviewBoard(plotPaths, points, outputDir, ...
    'CableAccelBalancedDisplay_ReviewBoard.jpg');
manifestPath = fullfile(outputDir, 'CableAccelBalancedDisplay_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelBalancedDisplay_manifest.csv');
policyPath = fullfile(outputDir, 'CableAccelBalancedDisplay_policy.json');
htmlPath = writeHtml(outputDir, pick, contactSheetPath, reviewBoardPath);
readmePath = writeReadme(outputDir, pick, contactSheetPath, reviewBoardPath, htmlPath);
writePolicy(policyPath, pick, minKeepPct, minImprovementPct);
writetable(pick, manifestPath, 'Sheet', 'balanced_pick');
writetable(pick, manifestCsvPath, 'Encoding', 'UTF-8');

result = struct();
result.output_dir = outputDir;
result.manifest = manifestPath;
result.manifest_csv = manifestCsvPath;
result.policy = policyPath;
result.html = htmlPath;
result.readme = readmePath;
result.contact_sheet = contactSheetPath;
result.review_board = reviewBoardPath;
result.selected = pick;

fprintf('balanced pick dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('policy %s\n', policyPath);
fprintf('html %s\n', htmlPath);
disp(pick(:, {'PointID','SelectedSource','Strategy','KeepPct','RMS30Max','Rationale'}));
end

function sheetPath = buildContactSheet(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 2600 1250], 'Color', 'w');
tiledlayout(fig, 2, 4, 'Padding', 'compact', 'TileSpacing', 'compact');
for i = 1:numel(points)
    ax = nexttile;
    showImageOrMissing(ax, plotPaths{i}, points{i});
    title(ax, points{i}, 'Interpreter', 'none', 'FontWeight', 'bold');
end
sheetPath = fullfile(outputDir, fileName);
exportgraphics(fig, sheetPath, 'Resolution', 150);
close(fig);
end

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 1800 2200], 'Color', 'w');
tiledlayout(fig, 4, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
for i = 1:numel(points)
    ax = nexttile;
    showImageOrMissing(ax, plotPaths{i}, points{i});
    title(ax, points{i}, 'Interpreter', 'none');
end
boardPath = fullfile(outputDir, fileName);
exportgraphics(fig, boardPath, 'Resolution', 150);
close(fig);
end

function showImageOrMissing(ax, imagePath, pointId)
if isfile(imagePath)
    image(ax, imread(imagePath));
    axis(ax, 'image');
    axis(ax, 'off');
else
    axis(ax, 'off');
    text(ax, 0.5, 0.5, sprintf('%s missing', pointId), ...
        'HorizontalAlignment', 'center', 'Interpreter', 'none');
end
end

function htmlPath = writeHtml(outputDir, pick, contactSheetPath, reviewBoardPath)
htmlPath = fullfile(outputDir, 'index.html');
fid = fopen(htmlPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Balanced Display Pick</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #2f6fed;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.cleaner{background:#eaf7f2}.current{background:#f4f6f8}.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;}');
fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#33258;&#21160;&#24179;&#34913;&#26368;&#32456;&#20505;&#36873; / Balanced Display Pick</h1>\n');
fprintf(fid, '<div class="note">&#36873;&#25321;&#35268;&#21017;: cleaner &#20445;&#30041;&#29575; &gt;= 92%% &#19988; RMS &#26377;&#25913;&#21892;&#26102;&#37319;&#29992; cleaner; &#21542;&#21017;&#20445;&#30041; current. &#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;&#12290;</div>\n');
fprintf(fid, '<h2>&#26368;&#32456;&#20505;&#36873;&#31574;&#30053; / Selected Strategy</h2>\n<table>\n');
fprintf(fid, '<tr><th>Point</th><th>Selected</th><th>Strategy</th><th>Keep %%</th><th>RMS30 max</th><th>Cleaner RMS max improvement %%</th><th>Rationale</th></tr>\n');
for i = 1:height(pick)
    fprintf(fid, '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        htmlText(pick.SelectedSource{i}), htmlText(pick.PointID{i}), ...
        htmlText(pick.SelectedSource{i}), htmlText(pick.Strategy{i}), ...
        pick.KeepPct(i), pick.RMS30Max(i), pick.CleanerRMS30MaxImprovementPct(i), ...
        htmlText(pick.Rationale{i}));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>&#32039;&#20945;&#22797;&#26680; / Contact Sheet</h2>\n<div class="figure"><img src="%s" alt="contact sheet"></div>\n', htmlText(localFileName(contactSheetPath)));
fprintf(fid, '<h2>&#24635;&#35272; / Review Board</h2>\n<div class="figure"><img src="%s" alt="review board"></div>\n', htmlText(localFileName(reviewBoardPath)));
fprintf(fid, '<h2>&#21333;&#28857;&#22270; / Per-Point Figures</h2>\n<div class="grid">\n');
for i = 1:height(pick)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(pick.PointID{i}), htmlText(localFileName(pick.PlotPath{i})), ...
        htmlText(pick.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function readmePath = writeReadme(outputDir, pick, contactSheetPath, reviewBoardPath, htmlPath)
readmePath = fullfile(outputDir, 'README.md');
fid = fopen(readmePath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Balanced Display Pick\n\n');
fprintf(fid, '- Open `index.html` for the balanced pick review page.\n');
fprintf(fid, '- Contact sheet: `%s`\n', localFileName(contactSheetPath));
fprintf(fid, '- Review board: `%s`\n', localFileName(reviewBoardPath));
fprintf(fid, '- Source HTML: `%s`\n\n', localFileName(htmlPath));
fprintf(fid, 'Formal spectrum/force calculation remains unchanged. This package is display-only.\n\n');
fprintf(fid, '| Point | Selected | Strategy | Keep %% | RMS30 max | Rationale |\n');
fprintf(fid, '|---|---|---|---:|---:|---|\n');
for i = 1:height(pick)
    fprintf(fid, '| %s | %s | %s | %.3f | %.3f | %s |\n', ...
        pick.PointID{i}, pick.SelectedSource{i}, pick.Strategy{i}, ...
        pick.KeepPct(i), pick.RMS30Max(i), pick.Rationale{i});
end
end

function writePolicy(path, pick, minKeepPct, minImprovementPct)
policy = struct();
policy.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
policy.scope = 'display_only';
policy.formal_policy = 'Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.';
policy.selection_rule = sprintf('Use cleaner when cleaner keep >= %.1f%% and RMS improvement >= %.1f%%; otherwise use current.', ...
    minKeepPct, minImprovementPct);
policy.points = struct();
for i = 1:height(pick)
    pointId = pick.PointID{i};
    [thresholdAbs, segmentPct] = parseStrategy(pick.Strategy{i});
    field = matlab.lang.makeValidName(strrep(pointId, '-', '_'));
    policy.points.(field) = struct( ...
        'point_id', pointId, ...
        'selected_source', pick.SelectedSource{i}, ...
        'strategy', pick.Strategy{i}, ...
        'threshold_abs_mps2', thresholdAbs, ...
        'segment_filter_top_pct_rms30', segmentPct, ...
        'keep_pct', pick.KeepPct(i), ...
        'rms30_max', pick.RMS30Max(i), ...
        'rationale', pick.Rationale{i});
end
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(policy));
end

function [thresholdAbs, segmentPct] = parseStrategy(strategy)
strategy = char(strategy);
thresholdAbs = NaN;
segmentPct = 0;
token = regexp(strategy, 'abs<=([0-9.]+)', 'tokens', 'once');
if ~isempty(token)
    thresholdAbs = str2double(token{1});
elseif contains(strategy, 'formal abs<=100')
    thresholdAbs = 100;
end
segToken = regexp(strategy, 'drop top ([0-9.]+)% RMS30', 'tokens', 'once');
if ~isempty(segToken)
    segmentPct = str2double(segToken{1});
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
