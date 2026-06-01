function result = preview_zhishan_cable_accel_threshold(thresholdAbs)
%PREVIEW_ZHISHAN_CABLE_ACCEL_THRESHOLD Preview one cable-accel clipping threshold.
%   This diagnostic does not modify zhishan_config.json or formal outputs.

if nargin < 1 || isempty(thresholdAbs)
    thresholdAbs = 20;
end

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
startDate = '2026-03-01';
endDate = '2026-03-31';
binMinutes = 30;

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
points = resolveCableAccelPoints(cfgLoad);
subfolder = bms.config.ConfigReader.getSubfolder(cfgLoad, 'cable_accel', '');

stamp = datestr(now, 'yyyymmdd_HHMMSS');
safeThreshold = regexprep(sprintf('%.6g', thresholdAbs), '[^\w.-]', '_');
runName = sprintf('cable_accel_threshold_preview_%s_abs%s', stamp, safeThreshold);
outRoot = fullfile(dataRoot, 'run_logs', runName);
plotDir = fullfile(outRoot, 'envelope30');
if ~exist(plotDir, 'dir'), mkdir(plotDir); end

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
binEdges = t0:minutes(binMinutes):t1;
binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);

rows = {};
plotPaths = cell(numel(points), 1);
for i = 1:numel(points)
    pointId = points{i};
    fprintf('preview cable_accel %s threshold +/-%.6g\n', pointId, thresholdAbs);

    [times, values] = load_timeseries_range(dataRoot, subfolder, pointId, ...
        startDate, endDate, cfgLoad, 'cable_accel');
    times = times(:);
    values = double(values(:));
    baseMask = isfinite(values) & ~isnat(times);
    baseCount = nnz(baseMask);

    clean = values;
    clean(abs(clean) > thresholdAbs) = NaN;
    keepMask = isfinite(clean) & ~isnat(times);
    keptCount = nnz(keepMask);
    keepPct = 100 * keptCount / max(baseCount, 1);
    clipPct = 100 - keepPct;

    [stats, rms30Max, rms30P95, validBins] = binnedStats(times, clean, binEdges, binCenters);
    plotPath = plotPointPreview(plotDir, pointId, thresholdAbs, binCenters, stats, ...
        t0, t1 - seconds(1), binMinutes);
    plotPaths{i} = plotPath;

    keptValues = clean(keepMask);
    if isempty(keptValues)
        cleanMin = NaN;
        cleanMax = NaN;
        cleanRms = NaN;
        cleanAbsP99 = NaN;
    else
        cleanMin = min(keptValues, [], 'omitnan');
        cleanMax = max(keptValues, [], 'omitnan');
        cleanRms = sqrt(mean(keptValues.^2, 'omitnan'));
        cleanAbsP99 = prctile(abs(keptValues), 99);
    end

    rows(end+1, :) = {pointId, thresholdAbs, baseCount, keptCount, keepPct, ...
        clipPct, cleanMin, cleanMax, cleanRms, cleanAbsP99, rms30Max, rms30P95, validBins, plotPath}; %#ok<AGROW>
end

summary = cell2table(rows, 'VariableNames', { ...
    'PointID','ThresholdAbs','BaseFiniteCount','KeptCount','KeepPct','ClipPct', ...
    'CleanMin','CleanMax','CleanRMS','CleanAbsP99','RMS30Max','RMS30P95', ...
    'ValidRMS30Bins','PlotPath'});

xlsxPath = fullfile(outRoot, 'cable_accel_threshold_preview.xlsx');
csvPath = fullfile(outRoot, 'cable_accel_threshold_preview.csv');
writetable(summary, xlsxPath, 'Sheet', 'summary');
writetable(summary, csvPath, 'Encoding', 'UTF-8');
boardPath = buildReviewBoard(plotPaths, points, outRoot, thresholdAbs);
markdownPath = writeMarkdown(outRoot, runName, thresholdAbs, xlsxPath, csvPath, boardPath, summary);

result = struct();
result.run_name = runName;
result.output_folder = outRoot;
result.threshold_abs = thresholdAbs;
result.xlsx = xlsxPath;
result.csv = csvPath;
result.board = boardPath;
result.markdown = markdownPath;
result.summary = summary;

fprintf('wrote %s\n', xlsxPath);
fprintf('wrote %s\n', csvPath);
fprintf('review board %s\n', boardPath);
fprintf('summary markdown %s\n', markdownPath);
disp(summary(:, {'PointID','KeepPct','ClipPct','CleanMin','CleanMax','RMS30Max','RMS30P95'}));
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

function points = resolveCableAccelPoints(cfg)
points = {};
if isfield(cfg, 'points') && isfield(cfg.points, 'cable_accel')
    points = cellstr(string(cfg.points.cable_accel(:)));
end
if isempty(points)
    points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);
end
end

function [stats, rms30Max, rms30P95, validBins] = binnedStats(times, values, binEdges, binCenters)
nBins = numel(binCenters);
stats = struct();
stats.count = zeros(nBins, 1);
stats.p01 = NaN(nBins, 1);
stats.p05 = NaN(nBins, 1);
stats.p50 = NaN(nBins, 1);
stats.p95 = NaN(nBins, 1);
stats.p99 = NaN(nBins, 1);
stats.ymin = NaN(nBins, 1);
stats.ymax = NaN(nBins, 1);
stats.rms = NaN(nBins, 1);

valid = isfinite(values) & ~isnat(times);
if ~any(valid)
    rms30Max = NaN;
    rms30P95 = NaN;
    validBins = 0;
    return;
end

idx = discretize(times(valid), binEdges);
good = ~isnan(idx);
if ~any(good)
    rms30Max = NaN;
    rms30P95 = NaN;
    validBins = 0;
    return;
end

vals = values(valid);
vals = vals(good);
idx = idx(good);
stats.count = accumarray(idx, 1, [nBins 1], @sum, 0);
stats.p01 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 1), NaN);
stats.p05 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 5), NaN);
stats.p50 = accumarray(idx, vals, [nBins 1], @(x) median(x, 'omitnan'), NaN);
stats.p95 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 95), NaN);
stats.p99 = accumarray(idx, vals, [nBins 1], @(x) prctile(x, 99), NaN);
stats.ymin = accumarray(idx, vals, [nBins 1], @(x) min(x, [], 'omitnan'), NaN);
stats.ymax = accumarray(idx, vals, [nBins 1], @(x) max(x, [], 'omitnan'), NaN);
stats.rms = accumarray(idx, vals, [nBins 1], @(x) sqrt(mean(x.^2, 'omitnan')), NaN);

finiteRms = stats.rms(isfinite(stats.rms));
validBins = numel(finiteRms);
if isempty(finiteRms)
    rms30Max = NaN;
    rms30P95 = NaN;
else
    rms30Max = max(finiteRms);
    rms30P95 = prctile(finiteRms, 95);
end
end

function plotPath = plotPointPreview(plotDir, pointId, thresholdAbs, binCenters, stats, xStart, xEnd, binMinutes)
fig = figure('Visible', 'off', 'Position', [100 100 1280 720]);
tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
hold(ax1, 'on');
fillBand(ax1, binCenters, stats.p01, stats.p99, [0.80 0.87 0.96], '1%~99%');
fillBand(ax1, binCenters, stats.p05, stats.p95, [0.46 0.68 0.88], '5%~95%');
plot(ax1, binCenters, stats.p50, 'Color', [0.04 0.22 0.48], 'LineWidth', 1.2, 'DisplayName', 'median');
plot(ax1, binCenters, stats.ymin, ':', 'Color', [0.55 0.55 0.55], 'LineWidth', 0.6, 'DisplayName', 'min/max');
plot(ax1, binCenters, stats.ymax, ':', 'Color', [0.55 0.55 0.55], 'LineWidth', 0.6, 'HandleVisibility', 'off');
hold(ax1, 'off');
grid(ax1, 'on');
grid(ax1, 'minor');
xlim(ax1, [xStart xEnd]);
yline(ax1, thresholdAbs, '--', sprintf('+%.0f', thresholdAbs), 'Color', [0.75 0.20 0.18]);
yline(ax1, -thresholdAbs, '--', sprintf('-%.0f', thresholdAbs), 'Color', [0.75 0.20 0.18]);
ylabel(ax1, 'm/s^2');
title(ax1, sprintf('Cable acceleration threshold preview %s | +/-%.0f m/s^2', pointId, thresholdAbs), ...
    'Interpreter', 'none');
legend(ax1, 'Location', 'northeast', 'Box', 'off');

ax2 = nexttile;
plot(ax2, binCenters, stats.rms, 'Color', [0.85 0.33 0.10], 'LineWidth', 1.2);
grid(ax2, 'on');
grid(ax2, 'minor');
xlim(ax2, [xStart xEnd]);
ylabel(ax2, 'RMS (m/s^2)');
xlabel(ax2, sprintf('time, %d min bins', binMinutes));
title(ax2, sprintf('30 min RMS %s', pointId), 'Interpreter', 'none');
xtickformat(ax1, 'MM-dd');
xtickformat(ax2, 'MM-dd');

plotPath = fullfile(plotDir, sprintf('CableAccelThresholdPreview_abs%.0f_%s.jpg', thresholdAbs, pointId));
exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
end

function fillBand(ax, t, lo, hi, color, label)
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
    fill(ax, x, y, color, 'FaceAlpha', 0.6, 'EdgeColor', 'none', ...
        'DisplayName', displayName, 'HandleVisibility', visibility);
end
end

function runs = continuousRuns(mask)
mask = mask(:);
starts = find(mask & [true; ~mask(1:end-1)]);
ends = find(mask & [~mask(2:end); true]);
runs = [starts ends];
end

function boardPath = buildReviewBoard(plotPaths, points, outRoot, thresholdAbs)
valid = ~cellfun(@isempty, plotPaths);
plotPaths = plotPaths(valid);
points = points(valid);

fig = figure('Visible', 'off', 'Position', [100 100 1800 2200]);
tiledlayout(fig, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
for i = 1:numel(plotPaths)
    ax = nexttile;
    img = imread(plotPaths{i});
    image(ax, img);
    axis(ax, 'image');
    axis(ax, 'off');
    title(ax, sprintf('%s | +/-%.0f m/s^2', points{i}, thresholdAbs), 'Interpreter', 'none');
end
boardPath = fullfile(outRoot, sprintf('cable_accel_threshold_preview_abs%.0f_review_board.jpg', thresholdAbs));
exportgraphics(fig, boardPath, 'Resolution', 150);
close(fig);
end

function markdownPath = writeMarkdown(outRoot, runName, thresholdAbs, xlsxPath, csvPath, boardPath, summary)
markdownPath = fullfile(outRoot, 'cable_accel_threshold_preview.md');
fid = fopen(markdownPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Cable Acceleration Threshold Preview\n\n');
fprintf(fid, '- Run: `%s`\n', runName);
fprintf(fid, '- Threshold: `[-%.0f, %.0f] m/s^2`\n', thresholdAbs, thresholdAbs);
fprintf(fid, '- Workbook: `%s`\n', xlsxPath);
fprintf(fid, '- CSV: `%s`\n', csvPath);
fprintf(fid, '- Review board: `%s`\n\n', boardPath);
fprintf(fid, '| Point | Keep %% | Clip %% | Min | Max | RMS30 max | RMS30 p95 |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|\n');
for i = 1:height(summary)
    fprintf(fid, '| %s | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f |\n', ...
        summary.PointID{i}, summary.KeepPct(i), summary.ClipPct(i), ...
        summary.CleanMin(i), summary.CleanMax(i), summary.RMS30Max(i), summary.RMS30P95(i));
end
end
