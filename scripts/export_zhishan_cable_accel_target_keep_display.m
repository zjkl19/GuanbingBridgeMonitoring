function result = export_zhishan_cable_accel_target_keep_display(targetKeepPct)
%EXPORT_ZHISHAN_CABLE_ACCEL_TARGET_KEEP_DISPLAY Export target-keep display.
%   Selects, per point, the lowest-RMS candidate that keeps at least the
%   requested percentage of finite data. Display/report review only.

if nargin < 1 || isempty(targetKeepPct)
    targetKeepPct = 80;
end
targetKeepPct = double(targetKeepPct);
if ~isfinite(targetKeepPct) || targetKeepPct <= 0 || targetKeepPct >= 100
    error('targetKeepPct must be between 0 and 100.');
end

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
stableDir = fullfile(dataRoot, 'report_cable_accel_display_recommendation');
tierName = sprintf('target%d', round(targetKeepPct));
outputDir = fullfile(stableDir, [tierName '_display_export']);
if ~exist(outputDir, 'dir'), mkdir(outputDir); end

startDate = '2026-03-01';
endDate = '2026-03-31';
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
binMinutes = 30;
segmentMinutes = 30;

latest = readJson(fullfile(dataRoot, 'run_logs', ...
    'cable_accel_display_grid_search_latest.json'));
gridEval = readtable(fullfile(dataRoot, latest.workbook), 'Sheet', 'grid_eval');

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
    fprintf('export %s cable_accel display %s\n', tierName, pointId);
    selected = selectTargetCandidate(gridEval, pointId, targetKeepPct);

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

    clean = applyDisplayPolicy(times, values, selected.ThresholdAbs, ...
        selected.SegmentFilterTopPct, segmentEdges);
    metric = binnedMetric(times, clean, binEdges, binCenters);
    kp = 100 * nnz(isfinite(clean) & ~isnat(times)) / baseCount;
    strategy = strategyText(selected.ThresholdAbs, selected.SegmentFilterTopPct, segmentMinutes);
    plotPaths{i} = plotTarget(outputDir, pointId, tierName, targetKeepPct, ...
        binCenters, metric, strategy, kp, startDate, endDate);
    rows(end+1, :) = {pointId, targetKeepPct, strategy, selected.ThresholdAbs, ...
        selected.SegmentFilterTopPct, baseCount, kp, metric.rmsMax, metric.rmsP95, ...
        metric.bandWidthP95Median, plotPaths{i}}; %#ok<AGROW>
end

manifest = cell2table(rows, 'VariableNames', { ...
    'PointID','TargetKeepPct','Strategy','ThresholdAbs','SegmentFilterTopPct', ...
    'BaseFiniteCount','KeepPct','RMS30Max','RMS30P95','BandWidthP95Median','PlotPath'});
boardPath = buildReviewBoard(plotPaths, points, outputDir, ...
    sprintf('CableAccel%sDisplay_ReviewBoard.jpg', titleCase(tierName)));
contactSheetPath = buildReviewBoard(plotPaths, points, outputDir, ...
    sprintf('CableAccel%sDisplay_ContactSheet.jpg', titleCase(tierName)));
manifestPath = fullfile(outputDir, sprintf('CableAccel%sDisplay_manifest.xlsx', titleCase(tierName)));
manifestCsvPath = fullfile(outputDir, sprintf('CableAccel%sDisplay_manifest.csv', titleCase(tierName)));
htmlPath = writeHtml(outputDir, tierName, targetKeepPct, manifest, contactSheetPath);
writetable(manifest, manifestPath, 'Sheet', 'manifest');
writetable(manifest, manifestCsvPath, 'Encoding', 'UTF-8');

result = struct();
result.tier = tierName;
result.target_keep_pct = targetKeepPct;
result.output_dir = outputDir;
result.manifest = manifestPath;
result.manifest_csv = manifestCsvPath;
result.review_board = boardPath;
result.contact_sheet = contactSheetPath;
result.html = htmlPath;

fprintf('target keep output dir %s\n', outputDir);
fprintf('manifest %s\n', manifestPath);
fprintf('html %s\n', htmlPath);
disp(manifest(:, {'PointID','Strategy','KeepPct','RMS30Max','RMS30P95'}));
end

function selected = selectTargetCandidate(gridEval, pointId, targetKeepPct)
rows = gridEval(strcmp(gridEval.PointID, pointId) & gridEval.KeepPct >= targetKeepPct, :);
if isempty(rows)
    rows = gridEval(strcmp(gridEval.PointID, pointId), :);
end
rows = sortrows(rows, {'DisplayRMS30Max','KeepPct'}, {'ascend','descend'});
selected = rows(1, :);
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

function clean = applyDisplayPolicy(times, values, thresholdAbs, segmentPct, segmentEdges)
clean = values;
clean(abs(clean) > thresholdAbs) = NaN;
if segmentPct > 0
    clean = applyTopRmsSegmentMask(times, clean, segmentEdges, segmentPct);
end
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
if isempty(vals)
    return;
end
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

function strategy = strategyText(thresholdAbs, segmentPct, segmentMinutes)
strategy = sprintf('abs<=%g display', thresholdAbs);
if segmentPct > 0
    strategy = sprintf('%s + drop top %g%% RMS%d segments', ...
        strategy, segmentPct, segmentMinutes);
end
end

function plotPath = plotTarget(outputDir, pointId, tierName, targetKeepPct, ...
    binCenters, metric, strategy, keepPct, startDate, endDate)
fig = figure('Visible', 'off', 'Position', [100 100 1300 720], 'Color', 'w');
tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
hold(ax1, 'on');
fillBand(ax1, binCenters, metric.p05, metric.p95, [0.78 0.86 0.93], 0.45, '5%~95%');
fillBand(ax1, binCenters, metric.p25, metric.p75, [0.23 0.53 0.73], 0.58, '25%~75%');
plot(ax1, binCenters, metric.p50, 'Color', [0.02 0.20 0.34], 'LineWidth', 1.35, 'DisplayName', 'median');
hold(ax1, 'off');
grid(ax1, 'on');
grid(ax1, 'minor');
ylabel(ax1, 'm/s^2');
title(ax1, sprintf('%s cable acceleration %s display | %s to %s', pointId, tierName, startDate, endDate), ...
    'Interpreter', 'none');
subtitle(ax1, sprintf('target keep %.0f%% | %s | keep %.2f%%', targetKeepPct, strategy, keepPct), ...
    'Interpreter', 'none');
legend(ax1, 'Location', 'northeast', 'Box', 'off');
xtickformat(ax1, 'yyyy-MM-dd');

ax2 = nexttile;
plot(ax2, binCenters, metric.rms, 'Color', [0.58 0.32 0.08], 'LineWidth', 1.15);
grid(ax2, 'on');
grid(ax2, 'minor');
ylabel(ax2, 'RMS30 (m/s^2)');
xlabel(ax2, 'time');
title(ax2, sprintf('RMS30 max %.2f | RMS30 P95 %.2f | display-only target', ...
    metric.rmsMax, metric.rmsP95), 'Interpreter', 'none');
xtickformat(ax2, 'yyyy-MM-dd');
linkaxes([ax1 ax2], 'x');
xlim(ax1, [binCenters(1), binCenters(end)]);

plotPath = fullfile(outputDir, sprintf('CableAccel%sDisplay_%s_20260301_20260331.jpg', ...
    titleCase(tierName), pointId));
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
        visibility = 'on';
        displayName = label;
    else
        visibility = 'off';
        displayName = '';
    end
    fill(ax, x, y, color, 'FaceAlpha', alpha, 'EdgeColor', 'none', ...
        'HandleVisibility', visibility, 'DisplayName', displayName);
end
end

function runs = continuousRuns(mask)
mask = mask(:);
startIdx = find(diff([false; mask]) == 1);
endIdx = find(diff([mask; false]) == -1);
runs = [startIdx, endIdx];
end

function boardPath = buildReviewBoard(plotPaths, points, outputDir, fileName)
fig = figure('Visible', 'off', 'Position', [100 100 1800 1400], 'Color', 'w');
tiledlayout(fig, 2, 4, 'Padding', 'compact', 'TileSpacing', 'compact');
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

function htmlPath = writeHtml(outputDir, tierName, targetKeepPct, manifest, contactSheetPath)
htmlPath = fullfile(outputDir, 'index.html');
fid = fopen(htmlPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration %s Display</title>\n', htmlText(tierName));
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.note{background:white;border-left:4px solid #2563eb;padding:10px 12px;margin:14px 0 20px;color:#4b5563;line-height:1.7;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;} th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>Zhishan Cable Acceleration %s Display</h1>\n', htmlText(tierName));
fprintf(fid, '<div class="note">Display-only target-keep export. Target keep %.0f%%. Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.</div>\n', targetKeepPct);
fprintf(fid, '<h2>Manifest</h2><table>\n');
fprintf(fid, '<tr><th>Point</th><th>Strategy</th><th>Keep %%</th><th>RMS30 max</th><th>RMS30 P95</th></tr>\n');
for i = 1:height(manifest)
    fprintf(fid, '<tr><td>%s</td><td>%s</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td></tr>\n', ...
        htmlText(manifest.PointID{i}), htmlText(manifest.Strategy{i}), ...
        manifest.KeepPct(i), manifest.RMS30Max(i), manifest.RMS30P95(i));
end
fprintf(fid, '</table>\n');
fprintf(fid, '<h2>Contact Sheet</h2><div class="figure"><img src="%s" alt="contact sheet"></div>\n', ...
    htmlText(localFileName(contactSheetPath)));
fprintf(fid, '<h2>Per-Point</h2><div class="grid">\n');
for i = 1:height(manifest)
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(manifest.PointID{i}), htmlText(localFileName(manifest.PlotPath{i})), ...
        htmlText(manifest.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function title = titleCase(textValue)
parts = split(string(textValue), {'_', '-', ' '});
for i = 1:numel(parts)
    p = char(parts(i));
    if isempty(p)
        continue;
    end
    parts(i) = string([upper(p(1)) p(2:end)]);
end
title = char(strjoin(parts, ''));
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
