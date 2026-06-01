function result = export_zhishan_cable_accel_recommended_display()
%EXPORT_ZHISHAN_CABLE_ACCEL_RECOMMENDED_DISPLAY Export report-ready charts.
%   Uses the stable display policy JSON and source data. Formal
%   spectrum/force settings are not modified.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
runLogs = fullfile(dataRoot, 'run_logs');
policyPath = fullfile(dataRoot, 'report_cable_accel_display_recommendation', ...
    'CableAccelDisplayRecommendation_policy.json');
policy = readJson(policyPath);

startDate = '2026-03-01';
endDate = '2026-03-31';
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
binMinutes = 30;
segmentMinutes = 30;

outputDir = fullfile(dataRoot, [char([26102 31243 26354 32447]) '_' ...
    char([32034 21147 21152 36895 24230]) '_' char([25512 33616 23637 31034])]);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
subfolder = bms.config.ConfigReader.getSubfolder(cfgLoad, 'cable_accel', '');

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
binEdges = t0:minutes(binMinutes):t1;
binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);
segmentEdges = t0:minutes(segmentMinutes):t1;

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    fprintf('export recommended cable_accel display %s\n', pointId);
    p = policy.points.(matlab.lang.makeValidName(strrep(pointId, '-', '_')));
    [times, values] = load_timeseries_range(dataRoot, subfolder, pointId, ...
        startDate, endDate, cfgLoad, 'cable_accel');
    times = times(:);
    values = double(values(:));
    baseMask = isfinite(values) & ~isnat(times);
    baseCount = nnz(baseMask);
    if baseCount == 0
        warning('%s has no finite data.', pointId);
        continue;
    end

    clean = clipAbs(values, p.threshold_abs_mps2);
    if p.segment_filter_top_pct_rms30 > 0
        clean = applyTopRmsSegmentMask(times, clean, segmentEdges, p.segment_filter_top_pct_rms30);
    end
    metric = binnedMetric(times, clean, binEdges, binCenters);
    keepPct = 100 * nnz(isfinite(clean) & ~isnat(times)) / baseCount;
    plotPaths{i} = plotRecommended(outputDir, pointId, binCenters, metric, p, keepPct, startDate, endDate);
    rows(end+1, :) = {pointId, p.source, p.strategy, p.threshold_abs_mps2, ...
        p.segment_filter_top_pct_rms30, baseCount, keepPct, metric.rmsMax, ...
        metric.rmsP95, metric.bandWidthP95Median, plotPaths{i}}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','PolicySource','Strategy','ThresholdAbs','SegmentFilterTopPct', ...
    'BaseFiniteCount','KeepPct','RMS30Max','RMS30P95','BandWidthP95Median','PlotPath'});

boardPath = buildReviewBoard(plotPaths, points, outputDir, 'CableAccelRecommendationDisplay_ReviewBoard.jpg');
manifestPath = fullfile(outputDir, 'CableAccelRecommendationDisplay_manifest.xlsx');
manifestCsvPath = fullfile(outputDir, 'CableAccelRecommendationDisplay_manifest.csv');
manifestMdPath = fullfile(outputDir, 'CableAccelRecommendationDisplay_manifest.md');
writetable(manifest, manifestPath, 'Sheet', 'manifest');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');
writeManifestMarkdown(manifestMdPath, manifest, boardPath, policyPath);

stamp = datestr(now, 'yyyymmdd_HHMMSS');
runName = ['cable_accel_recommended_display_export_' stamp];
latestPaths = writeLatest(dataRoot, runName, manifest, outputDir, boardPath, ...
    manifestPath, manifestMdPath, policyPath);

result = struct();
result.run_name = runName;
result.output_dir = outputDir;
result.manifest = manifest;
result.manifest_workbook = manifestPath;
result.manifest_csv = manifestCsvPath;
result.markdown = manifestMdPath;
result.board = boardPath;
result.latest = latestPaths;

fprintf('output dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('review board %s\n', boardPath);
fprintf('latest html %s\n', latestPaths.html);
disp(manifest(:, {'PointID','PolicySource','KeepPct','RMS30Max','PlotPath'}));
end

function data = readJson(path)
fid = fopen(path, 'r', 'n', 'UTF-8');
if fid < 0
    error('Cannot open %s.', path);
end
cleaner = onCleanup(@() fclose(fid));
text = fread(fid, '*char')';
data = jsondecode(text);
end

function cfgOut = removeCableAccelThresholds(cfgIn)
cfgOut = cfgIn;
if isfield(cfgOut, 'defaults') && isfield(cfgOut.defaults, 'cable_accel')
    cfgOut.defaults.cable_accel.thresholds = [];
    if isfield(cfgOut.defaults.cable_accel, 'value_scale')
        cfgOut.defaults.cable_accel = rmfield(cfgOut.defaults.cable_accel, 'value_scale');
    end
end
if isfield(cfgOut, 'per_point') && isfield(cfgOut.per_point, 'cable_accel')
    names = fieldnames(cfgOut.per_point.cable_accel);
    for k = 1:numel(names)
        if isfield(cfgOut.per_point.cable_accel.(names{k}), 'thresholds')
            cfgOut.per_point.cable_accel.(names{k}).thresholds = [];
        end
    end
end
end

function clean = clipAbs(values, thresholdAbs)
clean = values;
clean(abs(clean) > thresholdAbs) = NaN;
end

function clean = applyTopRmsSegmentMask(times, clean, segmentEdges, topPct)
valid = isfinite(clean) & ~isnat(times);
if ~any(valid)
    return;
end
nSegments = numel(segmentEdges) - 1;
idx = discretize(times(valid), segmentEdges);
good = ~isnan(idx);
vals = clean(valid);
vals = vals(good);
idx = idx(good);
rmsValues = accumarray(idx, vals, [nSegments 1], @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
ok = isfinite(rmsValues);
if ~any(ok)
    return;
end
cutoff = prctile(rmsValues(ok), 100 - topPct);
bad = ok & rmsValues >= cutoff;
allIdx = discretize(times, segmentEdges);
hasIdx = ~isnan(allIdx);
reject = false(size(clean));
reject(hasIdx) = bad(allIdx(hasIdx));
clean(reject) = NaN;
end

function metric = binnedMetric(times, values, binEdges, binCenters)
nBins = numel(binCenters);
metric = struct();
metric.p05 = NaN(nBins, 1);
metric.p25 = NaN(nBins, 1);
metric.p50 = NaN(nBins, 1);
metric.p75 = NaN(nBins, 1);
metric.p95 = NaN(nBins, 1);
metric.rms = NaN(nBins, 1);
metric.rmsMax = NaN;
metric.rmsP95 = NaN;
metric.bandWidthP95Median = NaN;
valid = isfinite(values) & ~isnat(times);
if ~any(valid)
    return;
end
idx = discretize(times(valid), binEdges);
good = ~isnan(idx);
vals = values(valid);
vals = vals(good);
idx = idx(good);
if isempty(vals)
    return;
end
metric.p05 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 5), NaN);
metric.p25 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 25), NaN);
metric.p50 = accumarray(idx, vals, [nBins 1], @(x) median(x, 'omitnan'), NaN);
metric.p75 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 75), NaN);
metric.p95 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 95), NaN);
metric.rms = accumarray(idx, vals, [nBins 1], @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
finiteRms = metric.rms(isfinite(metric.rms));
if ~isempty(finiteRms)
    metric.rmsMax = max(finiteRms);
    metric.rmsP95 = prctile(finiteRms, 95);
end
width = metric.p95 - metric.p05;
width = width(isfinite(width));
if ~isempty(width)
    metric.bandWidthP95Median = median(width, 'omitnan');
end
end

function plotPath = plotRecommended(outputDir, pointId, binCenters, metric, policyPoint, keepPct, startDate, endDate)
fig = figure('Visible', 'off', 'Position', [100 100 1300 720]);
tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
hold(ax1, 'on');
fillBand(ax1, binCenters, metric.p05, metric.p95, [0.80 0.88 0.96], 0.45, '5%~95%');
fillBand(ax1, binCenters, metric.p25, metric.p75, [0.38 0.64 0.86], 0.70, '25%~75%');
plot(ax1, binCenters, metric.p50, 'Color', [0 0.18 0.42], 'LineWidth', 1.35, 'DisplayName', 'median');
hold(ax1, 'off');
grid(ax1, 'on');
grid(ax1, 'minor');
ylabel(ax1, 'm/s^2');
title(ax1, sprintf('%s cable acceleration recommended display | %s to %s', pointId, startDate, endDate), ...
    'Interpreter', 'none');
subtitle(ax1, sprintf('%s | keep %.2f%%', policyPoint.strategy, keepPct), 'Interpreter', 'none');
legend(ax1, 'Location', 'northeast', 'Box', 'off');
xtickformat(ax1, 'yyyy-MM-dd');

ax2 = nexttile;
plot(ax2, binCenters, metric.rms, 'Color', [0.30 0.55 0.22], 'LineWidth', 1.15);
grid(ax2, 'on');
grid(ax2, 'minor');
ylabel(ax2, 'RMS30 (m/s^2)');
xlabel(ax2, 'time');
title(ax2, sprintf('RMS30 max %.2f | RMS30 P95 %.2f | display-only policy', ...
    metric.rmsMax, metric.rmsP95), 'Interpreter', 'none');
xtickformat(ax2, 'yyyy-MM-dd');
linkaxes([ax1 ax2], 'x');
xlim(ax1, [binCenters(1), binCenters(end)]);

plotPath = fullfile(outputDir, sprintf('CableAccelRecommendationDisplay_%s_20260301_20260331.jpg', pointId));
exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
end

function fillBand(ax, t, lo, hi, color, alpha, label)
ok = isfinite(lo) & isfinite(hi) & ~isnat(t);
if ~any(ok)
    return;
end
runs = continuousRuns(ok);
for k = 1:size(runs, 1)
    idx = runs(k, 1):runs(k, 2);
    x = [t(idx); flipud(t(idx))];
    y = [lo(idx); flipud(hi(idx))];
    if k == 1
        displayName = label;
        visibility = 'on';
    else
        displayName = '';
        visibility = 'off';
    end
    fill(ax, x, y, color, 'FaceAlpha', alpha, 'EdgeColor', 'none', ...
        'DisplayName', displayName, 'HandleVisibility', visibility);
end
end

function runs = continuousRuns(mask)
mask = mask(:);
starts = find(mask & [true; ~mask(1:end-1)]);
ends = find(mask & [~mask(2:end); true]);
runs = [starts ends];
end

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 1800 2200]);
tiledlayout(fig, 4, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
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

function writeManifestMarkdown(path, manifest, boardPath, policyPath)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Recommended Display Export\n\n');
fprintf(fid, '- Review board: `%s`\n', localFileName(boardPath));
fprintf(fid, '- Policy JSON: `%s`\n\n', localFileName(policyPath));
fprintf(fid, 'Formal spectrum/force calculation remains unchanged. These figures are display/report-review outputs.\n\n');
fprintf(fid, '| Point | Source | Strategy | Keep %% | RMS30 max | Plot |\n');
fprintf(fid, '|---|---|---|---:|---:|---|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %s | %.3f | %.3f | `%s` |\n', ...
        manifest.PointID{i}, manifest.PolicySource{i}, manifest.Strategy{i}, ...
        manifest.KeepPct(i), manifest.RMS30Max(i), localFileName(manifest.PlotPath{i}));
end
end

function latestPaths = writeLatest(dataRoot, runName, manifest, outputDir, boardPath, manifestPath, manifestMdPath, policyPath)
runLogs = fullfile(dataRoot, 'run_logs');
latestPaths = struct( ...
    'json', fullfile(runLogs, 'cable_accel_recommended_display_export_latest.json'), ...
    'markdown', fullfile(runLogs, 'cable_accel_recommended_display_export_latest.md'), ...
    'html', fullfile(runLogs, 'cable_accel_recommended_display_export_latest.html'));
pointer = struct();
pointer.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
pointer.run_name = runName;
pointer.output_dir = relPath(outputDir, dataRoot);
pointer.review_board = relPath(boardPath, dataRoot);
pointer.manifest = relPath(manifestPath, dataRoot);
pointer.manifest_markdown = relPath(manifestMdPath, dataRoot);
pointer.policy_json = relPath(policyPath, dataRoot);
pointer.review_html = relPath(latestPaths.html, dataRoot);
pointer.formal_policy = 'Formal spectrum/force calculation remains unchanged.';
pointer.display_policy = 'Recommended display-only cable acceleration charts.';

fid = fopen(latestPaths.json, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(pointer));
clear cleaner;

fid = fopen(latestPaths.markdown, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Latest Zhishan Cable Acceleration Recommended Display Export\n\n');
fprintf(fid, '- Generated: %s\n', pointer.generated_at);
fprintf(fid, '- Output dir: report-ready cable acceleration recommendation folder under the data root\n');
fprintf(fid, '- Review board: `%s`\n', localFileName(pointer.review_board));
fprintf(fid, '- Manifest: `%s`\n', localFileName(pointer.manifest));
fprintf(fid, '- Review HTML: `%s`\n', pointer.review_html);
fprintf(fid, '- Policy JSON: `%s`\n\n', localFileName(pointer.policy_json));
fprintf(fid, '| Point | Source | Keep %% | RMS30 max | Plot |\n');
fprintf(fid, '|---|---|---:|---:|---|\n');
for i = 1:height(manifest)
    fprintf(fid, '| %s | %s | %.3f | %.3f | `%s` |\n', ...
        manifest.PointID{i}, manifest.PolicySource{i}, manifest.KeepPct(i), ...
        manifest.RMS30Max(i), localFileName(manifest.PlotPath{i}));
end
clear cleaner;

writeLatestHtml(latestPaths.html, pointer, manifest);
end

function writeLatestHtml(path, pointer, manifest)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Recommended Display Export</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.meta,.note{line-height:1.7;color:#4b5563;} .note{background:white;border-left:4px solid #2f6fed;padding:10px 12px;margin:14px 0 20px;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.gridpick{background:#eaf7ee;} .figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} a{color:#075da8;text-decoration:none;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#25512;&#33616;&#23637;&#31034;&#22270; / Recommended Display Export</h1>\n');
fprintf(fid, '<div class="meta">Generated: %s<br>Output dir: <code>%s</code><br>Manifest: <a href="%s">%s</a></div>\n', ...
    htmlText(pointer.generated_at), htmlText(pointer.output_dir), htmlPath(pointer.manifest), htmlText(pointer.manifest));
fprintf(fid, '<div class="note">&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;&#12290;&#26412;&#39029;&#26159;&#25512;&#33616;&#28165;&#27927;&#21518;&#30340;&#25253;&#21578;/&#23457;&#22270;&#23637;&#31034;&#36755;&#20986;&#12290;</div>\n');
fprintf(fid, '<h2>&#36755;&#20986;&#28165;&#21333; / Output Manifest</h2>\n<table>\n');
fprintf(fid, '<tr><th>&#27979;&#28857;</th><th>&#31574;&#30053;&#26469;&#28304;</th><th>&#31574;&#30053;</th><th>&#20445;&#30041;&#29575;</th><th>RMS30 &#26368;&#22823;&#20540;</th></tr>\n');
for i = 1:height(manifest)
    cls = '';
    if strcmp(manifest.PolicySource{i}, 'grid')
        cls = ' class="gridpick"';
    end
    fprintf(fid, '<tr%s><td>%s</td><td>%s</td><td>%s</td><td class="num">%.3f%%</td><td class="num">%.3f</td></tr>\n', ...
        cls, htmlText(manifest.PointID{i}), htmlText(manifest.PolicySource{i}), ...
        htmlText(manifest.Strategy{i}), manifest.KeepPct(i), manifest.RMS30Max(i));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>&#24635;&#35272;&#22270; / Review Board</h2>\n<div class="figure"><img src="%s" alt="review board"></div>\n', htmlPath(pointer.review_board));
fprintf(fid, '<h2>&#21333;&#28857;&#22270; / Per-Point Figures</h2>\n<div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlPath(relPath(manifest.PlotPath{i}, fileparts(fileparts(path)))), ...
        htmlText(manifest.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function out = htmlPath(pathText)
out = char(pathText);
prefix = ['run_logs' filesep];
if startsWith(out, prefix)
    out = out(numel(prefix)+1:end);
elseif startsWith(out, ['report_' filesep]) || startsWith(out, 'report_') || startsWith(out, [char([26102 31243 26354 32447]) '_'])
    out = fullfile('..', out);
end
out = strrep(out, '\', '/');
out = htmlText(out);
end

function out = htmlText(value)
out = char(string(value));
out = strrep(out, '&', '&amp;');
out = strrep(out, '<', '&lt;');
out = strrep(out, '>', '&gt;');
out = strrep(out, '"', '&quot;');
end

function rel = relPath(pathText, rootText)
pathText = char(pathText);
rootText = char(rootText);
prefix = [rootText filesep];
if startsWith(pathText, prefix)
    rel = pathText(numel(prefix)+1:end);
else
    rel = pathText;
end
end

function name = localFileName(pathText)
[~, base, ext] = fileparts(char(pathText));
name = [base ext];
end
