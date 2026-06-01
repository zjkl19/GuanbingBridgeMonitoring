function result = diagnose_zhishan_cable_accel_segments(points)
%DIAGNOSE_ZHISHAN_CABLE_ACCEL_SEGMENTS Diagnose hard cable-accel points by time segments.
%   This diagnostic does not modify zhishan_config.json or formal outputs.

if nargin < 1 || isempty(points)
    points = {'CF-2', 'CF-5', 'CF-7', 'CF-8'};
end

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
startDate = '2026-03-01';
endDate = '2026-03-31';
segmentMinutes = 60;
formalThreshold = 100;
strictPreviewThreshold = 20;
badSegmentPctGrid = [2 5 10 15 20];
minDisplayKeepPct = 90;
minRmsReductionPct = 25;

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
subfolder = bms.config.ConfigReader.getSubfolder(cfgLoad, 'cable_accel', '');

stamp = datestr(now, 'yyyymmdd_HHMMSS');
runName = ['cable_accel_segment_quality_' stamp];
outRoot = fullfile(dataRoot, 'run_logs', runName);
plotDir = fullfile(outRoot, 'plots');
if ~exist(plotDir, 'dir'), mkdir(plotDir); end

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
edges = t0:minutes(segmentMinutes):t1;
centers = edges(1:end-1)' + minutes(segmentMinutes / 2);
nSegments = numel(centers);

summaryRows = {};
segmentRows = {};
segmentSweepRows = {};
plotPaths = cell(numel(points), 1);

for i = 1:numel(points)
    pointId = points{i};
    fprintf('segment quality %s\n', pointId);
    [times, values] = load_timeseries_range(dataRoot, subfolder, pointId, ...
        startDate, endDate, cfgLoad, 'cable_accel');
    times = times(:);
    values = double(values(:));
    baseMask = isfinite(values) & ~isnat(times);
    baseCount = nnz(baseMask);
    if baseCount == 0
        warning('%s has no finite values.', pointId);
        continue;
    end

    baseSeg = discretize(times(baseMask), edges);
    validBaseSeg = ~isnan(baseSeg);
    baseSeg = baseSeg(validBaseSeg);
    segmentBaseCount = accumarray(baseSeg, 1, [nSegments 1], @sum, 0);

    formalClean = clipAbs(values, formalThreshold);
    strictClean = clipAbs(values, strictPreviewThreshold);
    formalMetric = segmentMetric(times, formalClean, edges, centers, segmentBaseCount);
    strictMetric = segmentMetric(times, strictClean, edges, centers, segmentBaseCount);

    formalKeepPct = 100 * nnz(isfinite(formalClean) & ~isnat(times)) / baseCount;
    strictKeepPct = 100 * nnz(isfinite(strictClean) & ~isnat(times)) / baseCount;
    [sweepRows, selected] = sweepSegmentFilters(pointId, times, formalClean, formalMetric, ...
        edges, centers, segmentBaseCount, baseCount, badSegmentPctGrid, ...
        minDisplayKeepPct, minRmsReductionPct);
    segmentFilteredMetric = selected.metric;
    badSegmentMask = selected.badSegmentMask;
    rmsCutoff = selected.rmsCutoff;
    segmentKeepPct = selected.keepPct;
    removedSegmentPct = selected.badSegmentPctActual;
    rmsReductionPct = selected.rmsReductionPct;
    displayDecision = selected.decision;

    summaryRows(end+1, :) = {pointId, baseCount, formalThreshold, formalKeepPct, ...
        strictPreviewThreshold, strictKeepPct, selected.badSegmentPctTarget, nnz(badSegmentMask), ...
        removedSegmentPct, segmentKeepPct, rmsCutoff, formalMetric.rmsMax, ...
        formalMetric.rmsP95, segmentFilteredMetric.rmsMax, segmentFilteredMetric.rmsP95, ...
        rmsReductionPct, displayDecision}; %#ok<AGROW>
    for j = 1:size(sweepRows, 1)
        segmentSweepRows(end+1, :) = sweepRows(j, :); %#ok<AGROW>
    end

    for j = 1:nSegments
        if segmentBaseCount(j) <= 0
            continue;
        end
        reason = '';
        if badSegmentMask(j)
            reason = 'top RMS segment';
        end
        segmentRows(end+1, :) = {pointId, edges(j), edges(j+1), segmentBaseCount(j), ...
            formalMetric.keepPct(j), strictMetric.keepPct(j), formalMetric.rms(j), ...
            strictMetric.rms(j), segmentFilteredMetric.rms(j), badSegmentMask(j), reason}; %#ok<AGROW>
    end

    plotPaths{i} = plotPoint(plotDir, pointId, centers, formalMetric, segmentFilteredMetric, ...
        badSegmentMask, rmsCutoff, formalThreshold, segmentKeepPct, rmsReductionPct);
end

pointSummary = cell2table(summaryRows, 'VariableNames', { ...
    'PointID','BaseFiniteCount','FormalThresholdAbs','FormalKeepPct', ...
    'StrictPreviewThresholdAbs','StrictPreviewKeepPct','BadSegmentPctTarget', ...
    'BadSegmentCount','BadSegmentPctActual','SegmentFilteredKeepPct','RMSCutoff', ...
    'FormalRMSMax','FormalRMSP95','SegmentFilteredRMSMax','SegmentFilteredRMSP95', ...
    'SegmentRMSMaxReductionPct','Decision'});
segmentTable = cell2table(segmentRows, 'VariableNames', { ...
    'PointID','SegmentStart','SegmentEnd','BaseCount','FormalKeepPct', ...
    'StrictPreviewKeepPct','FormalRMS','StrictPreviewRMS','SegmentFilteredRMS', ...
    'BadSegment','Reason'});
segmentSweep = cell2table(segmentSweepRows, 'VariableNames', { ...
    'PointID','BadSegmentPctTarget','BadSegmentCount','BadSegmentPctActual', ...
    'SegmentFilteredKeepPct','RMSCutoff','SegmentFilteredRMSMax', ...
    'SegmentFilteredRMSP95','SegmentRMSMaxReductionPct','Decision'});

xlsxPath = fullfile(outRoot, 'cable_accel_segment_quality.xlsx');
csvPath = fullfile(outRoot, 'cable_accel_segment_quality_summary.csv');
writetable(pointSummary, xlsxPath, 'Sheet', 'point_summary');
writetable(segmentTable, xlsxPath, 'Sheet', 'segment_table');
writetable(segmentSweep, xlsxPath, 'Sheet', 'segment_sweep');
writetable(pointSummary, csvPath, 'Encoding', 'UTF-8');
boardPath = buildReviewBoard(plotPaths, points, outRoot);
markdownPath = writeMarkdown(outRoot, runName, pointSummary, xlsxPath, csvPath, boardPath);

result = struct();
result.run_name = runName;
result.output_folder = outRoot;
result.summary = pointSummary;
result.segment_table = segmentTable;
result.segment_sweep = segmentSweep;
result.workbook = xlsxPath;
result.csv = csvPath;
result.board = boardPath;
result.markdown = markdownPath;

fprintf('wrote %s\n', xlsxPath);
fprintf('wrote %s\n', csvPath);
fprintf('review board %s\n', boardPath);
fprintf('summary markdown %s\n', markdownPath);
disp(pointSummary);
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

function metric = segmentMetric(times, values, edges, centers, segmentBaseCount)
nSegments = numel(centers);
metric = struct();
metric.keepCount = zeros(nSegments, 1);
metric.keepPct = NaN(nSegments, 1);
metric.p05 = NaN(nSegments, 1);
metric.p50 = NaN(nSegments, 1);
metric.p95 = NaN(nSegments, 1);
metric.rms = NaN(nSegments, 1);
metric.rmsMax = NaN;
metric.rmsP95 = NaN;

valid = isfinite(values) & ~isnat(times);
if any(valid)
    idx = discretize(times(valid), edges);
    good = ~isnan(idx);
    vals = values(valid);
    vals = vals(good);
    idx = idx(good);
    metric.keepCount = accumarray(idx, 1, [nSegments 1], @sum, 0);
    metric.p05 = accumarray(idx, vals, [nSegments 1], @(x) prctile(x, 5), NaN);
    metric.p50 = accumarray(idx, vals, [nSegments 1], @(x) median(x, 'omitnan'), NaN);
    metric.p95 = accumarray(idx, vals, [nSegments 1], @(x) prctile(x, 95), NaN);
    metric.rms = accumarray(idx, vals, [nSegments 1], @(x) sqrt(mean(x.^2, 'omitnan')), NaN);
end

hasBase = segmentBaseCount > 0;
metric.keepPct(hasBase) = 100 * metric.keepCount(hasBase) ./ segmentBaseCount(hasBase);
finiteRms = metric.rms(isfinite(metric.rms));
if ~isempty(finiteRms)
    metric.rmsMax = max(finiteRms);
    metric.rmsP95 = prctile(finiteRms, 95);
end
end

function [rows, selected] = sweepSegmentFilters(pointId, times, formalClean, formalMetric, ...
        edges, centers, segmentBaseCount, baseCount, pctGrid, minKeepPct, minReductionPct)
rows = {};
options = repmat(emptySegmentOption(), numel(pctGrid), 1);
for i = 1:numel(pctGrid)
    pct = pctGrid(i);
    [badMask, rmsCutoff] = topRmsSegments(formalMetric.rms, segmentBaseCount, pct);
    filteredClean = applySegmentMask(times, formalClean, edges, badMask);
    filteredMetric = segmentMetric(times, filteredClean, edges, centers, segmentBaseCount);
    keepPct = 100 * nnz(isfinite(filteredClean) & ~isnat(times)) / baseCount;
    badPctActual = 100 * nnz(badMask) / max(nnz(segmentBaseCount > 0), 1);
    reductionPct = 100 * (formalMetric.rmsMax - filteredMetric.rmsMax) / max(formalMetric.rmsMax, eps);
    decision = segmentDecision(keepPct, reductionPct, minKeepPct, minReductionPct);

    options(i).badSegmentPctTarget = pct;
    options(i).badSegmentMask = badMask;
    options(i).badSegmentCount = nnz(badMask);
    options(i).badSegmentPctActual = badPctActual;
    options(i).keepPct = keepPct;
    options(i).rmsCutoff = rmsCutoff;
    options(i).metric = filteredMetric;
    options(i).rmsReductionPct = reductionPct;
    options(i).decision = decision;

    rows(end+1, :) = {pointId, pct, nnz(badMask), badPctActual, keepPct, rmsCutoff, ...
        filteredMetric.rmsMax, filteredMetric.rmsP95, reductionPct, decision}; %#ok<AGROW>
end

hit = find([options.keepPct] >= minKeepPct & [options.rmsReductionPct] >= minReductionPct, 1, 'first');
if isempty(hit)
    feasible = find([options.keepPct] >= minKeepPct);
    if isempty(feasible)
        [~, hit] = max([options.keepPct]);
    else
        [~, local] = max([options(feasible).rmsReductionPct]);
        hit = feasible(local);
    end
end
selected = options(hit);
end

function option = emptySegmentOption()
option = struct('badSegmentPctTarget', NaN, 'badSegmentMask', [], ...
    'badSegmentCount', 0, 'badSegmentPctActual', NaN, 'keepPct', NaN, ...
    'rmsCutoff', NaN, 'metric', [], 'rmsReductionPct', NaN, 'decision', '');
end

function [badMask, cutoff] = topRmsSegments(rmsValues, segmentBaseCount, pct)
valid = isfinite(rmsValues) & segmentBaseCount > 0;
badMask = false(size(rmsValues));
if ~any(valid)
    cutoff = NaN;
    return;
end
cutoff = prctile(rmsValues(valid), 100 - pct);
badMask = valid & rmsValues >= cutoff;
end

function filtered = applySegmentMask(times, values, edges, badSegmentMask)
filtered = values;
allSeg = discretize(times, edges);
hasSeg = ~isnan(allSeg);
reject = false(size(values));
reject(hasSeg) = badSegmentMask(allSeg(hasSeg));
filtered(reject) = NaN;
end

function decision = segmentDecision(segmentKeepPct, rmsReductionPct, minKeepPct, minReductionPct)
if segmentKeepPct >= minKeepPct && rmsReductionPct >= minReductionPct
    decision = 'segment filter helps display';
elseif segmentKeepPct >= minKeepPct
    decision = 'limited benefit after segment filter';
else
    decision = 'segment filter deletes too much data';
end
end

function plotPath = plotPoint(plotDir, pointId, centers, formalMetric, filteredMetric, ...
        badSegmentMask, rmsCutoff, formalThreshold, segmentKeepPct, rmsReductionPct)
fig = figure('Visible', 'off', 'Position', [100 100 1300 780]);
tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

envLimits = paddedLim([formalMetric.p05; formalMetric.p95; filteredMetric.p05; filteredMetric.p95]);
rmsLimits = paddedLim([formalMetric.rms; filteredMetric.rms]);

ax1 = nexttile;
plotEnvelope(ax1, centers, formalMetric, envLimits, sprintf('%s formal +/-%.0f m/s^2', pointId, formalThreshold));

ax2 = nexttile;
plotEnvelope(ax2, centers, filteredMetric, envLimits, ...
    sprintf('%s segment-filtered display, keep %.2f%%', pointId, segmentKeepPct));

ax3 = nexttile;
hold(ax3, 'on');
plot(ax3, centers, formalMetric.rms, 'LineWidth', 1.1, 'DisplayName', 'formal RMS60');
plot(ax3, centers, filteredMetric.rms, 'LineWidth', 1.1, 'DisplayName', 'segment-filtered RMS60');
badIdx = find(badSegmentMask(:));
if ~isempty(badIdx)
    scatter(ax3, centers(badIdx), formalMetric.rms(badIdx), 18, [0.85 0.10 0.10], 'filled', 'DisplayName', 'removed segment');
end
if isfinite(rmsCutoff)
    yline(ax3, rmsCutoff, '--', sprintf('top 5%% cutoff %.2f', rmsCutoff), 'Color', [0.55 0.10 0.10]);
end
hold(ax3, 'off');
grid(ax3, 'on');
grid(ax3, 'minor');
ylim(ax3, rmsLimits);
ylabel(ax3, 'RMS (m/s^2)');
xlabel(ax3, 'time');
title(ax3, sprintf('Segment RMS diagnosis, RMS max reduction %.1f%%', rmsReductionPct), 'Interpreter', 'none');
legend(ax3, 'Location', 'northeast', 'Box', 'off');
xtickformat(ax3, 'yyyy-MM-dd');

linkaxes([ax1 ax2 ax3], 'x');
xlim(ax1, [centers(1), centers(end)]);
plotPath = fullfile(plotDir, sprintf('SegmentQuality_%s.jpg', pointId));
exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
end

function plotEnvelope(ax, centers, metric, yLimits, titleText)
hold(ax, 'on');
fillBand(ax, centers, metric.p05, metric.p95, [0.55 0.75 0.93], '5%~95%');
plot(ax, centers, metric.p50, 'Color', [0 0.25 0.55], 'LineWidth', 1.1, 'DisplayName', 'median');
hold(ax, 'off');
grid(ax, 'on');
grid(ax, 'minor');
ylim(ax, yLimits);
ylabel(ax, 'm/s^2');
title(ax, titleText, 'Interpreter', 'none');
legend(ax, 'Location', 'northeast', 'Box', 'off');
xtickformat(ax, 'yyyy-MM-dd');
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
    fill(ax, x, y, color, 'FaceAlpha', 0.55, 'EdgeColor', 'none', ...
        'DisplayName', displayName, 'HandleVisibility', visibility);
end
end

function runs = continuousRuns(mask)
mask = mask(:);
starts = find(mask & [true; ~mask(1:end-1)]);
ends = find(mask & [~mask(2:end); true]);
runs = [starts ends];
end

function yLimits = paddedLim(values)
values = values(isfinite(values));
if isempty(values)
    yLimits = [0 1];
    return;
end
lo = min(values);
hi = max(values);
if lo == hi
    pad = max(1, abs(lo) * 0.1);
else
    pad = max(1e-6, 0.08 * (hi - lo));
end
yLimits = [lo - pad, hi + pad];
end

function boardPath = buildReviewBoard(plotPaths, points, outRoot)
fig = figure('Visible', 'off', 'Position', [100 100 1800 1800]);
tiledlayout(fig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
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
boardPath = fullfile(outRoot, 'cable_accel_segment_quality_review_board.jpg');
exportgraphics(fig, boardPath, 'Resolution', 150);
close(fig);
end

function markdownPath = writeMarkdown(outRoot, runName, pointSummary, xlsxPath, csvPath, boardPath)
markdownPath = fullfile(outRoot, 'cable_accel_segment_quality.md');
fid = fopen(markdownPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Segment Quality Diagnosis\n\n');
fprintf(fid, '- Run: `%s`\n', runName);
fprintf(fid, '- Workbook: `%s`\n', xlsxPath);
fprintf(fid, '- CSV: `%s`\n', csvPath);
fprintf(fid, '- Review board: `%s`\n\n', boardPath);
fprintf(fid, '| Point | Formal keep %% | Strict +/-20 keep %% | Segment-filtered keep %% | Bad segments | RMS max reduction %% | Decision |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---|\n');
for i = 1:height(pointSummary)
    fprintf(fid, '| %s | %.3f | %.3f | %.3f | %d | %.1f | %s |\n', ...
        pointSummary.PointID{i}, pointSummary.FormalKeepPct(i), ...
        pointSummary.StrictPreviewKeepPct(i), pointSummary.SegmentFilteredKeepPct(i), ...
        pointSummary.BadSegmentCount(i), pointSummary.SegmentRMSMaxReductionPct(i), ...
        pointSummary.Decision{i});
end
end
