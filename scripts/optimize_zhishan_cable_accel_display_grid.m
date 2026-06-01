function result = optimize_zhishan_cable_accel_display_grid()
%OPTIMIZE_ZHISHAN_CABLE_ACCEL_DISPLAY_GRID Search display-only CF cleaning.
%   This does not modify formal spectrum/force calculation settings.

projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(projectRoot));

dataRoot = fullfile('D:\', char([33437 23665 22823 26725 25968 25454]), ...
    ['2026' char(24180) '1-3' char(26376)]);
startDate = '2026-03-01';
endDate = '2026-03-31';
points = arrayfun(@(k) sprintf('CF-%d', k), 1:8, 'UniformOutput', false);

formalThreshold = 100;
thresholdGrid = [5 10 15 20 30 40 50 75 100];
segmentPctGrid = [0 2 5 8 10];
minKeepPct = 90;
binMinutes = 30;
segmentMinutes = 30;
maxSearchSamples = 200000;

cfg = load_config(fullfile(projectRoot, 'config', 'zhishan_config.json'));
cfg.notify.enabled = false;
cfgLoad = removeCableAccelThresholds(cfg);
subfolder = bms.config.ConfigReader.getSubfolder(cfgLoad, 'cable_accel', '');

stamp = datestr(now, 'yyyymmdd_HHMMSS');
runName = ['cable_accel_display_grid_search_' stamp];
outRoot = fullfile(dataRoot, 'run_logs', runName);
plotDir = fullfile(outRoot, 'plots');
if ~exist(plotDir, 'dir'), mkdir(plotDir); end

t0 = datetime(startDate, 'InputFormat', 'yyyy-MM-dd');
t1 = datetime(endDate, 'InputFormat', 'yyyy-MM-dd') + days(1);
binEdges = t0:minutes(binMinutes):t1;
binCenters = binEdges(1:end-1)' + minutes(binMinutes / 2);
segmentEdges = t0:minutes(segmentMinutes):t1;

allRows = {};
selectedRows = {};
plotPaths = cell(numel(points), 1);
trendPlotPaths = cell(numel(points), 1);

for i = 1:numel(points)
    pointId = points{i};
    fprintf('grid search cable_accel display %s\n', pointId);
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
    searchStride = max(1, ceil(numel(values) / maxSearchSamples));
    searchTimes = times(1:searchStride:end);
    searchValues = values(1:searchStride:end);
    searchMask = isfinite(searchValues) & ~isnat(searchTimes);
    searchBaseCount = nnz(searchMask);

    formalClean = clipAbs(values, formalThreshold);
    formalMetric = binnedMetric(times, formalClean, binEdges, binCenters);
    formalKeepPct = 100 * nnz(isfinite(formalClean) & ~isnat(times)) / baseCount;
    formalSearchClean = clipAbs(searchValues, formalThreshold);
    formalSearchMetric = binnedMetric(searchTimes, formalSearchClean, binEdges, binCenters);
    formalSearchKeepPct = 100 * nnz(isfinite(formalSearchClean) & ~isnat(searchTimes)) / searchBaseCount;

    pointRows = {};
    for th = thresholdGrid
        for segPct = segmentPctGrid
            clean = clipAbs(searchValues, th);
            if segPct > 0
                clean = applyTopRmsSegmentMask(searchTimes, clean, segmentEdges, segPct);
            end
            metric = binnedMetric(searchTimes, clean, binEdges, binCenters);
            keepPct = 100 * nnz(isfinite(clean) & ~isnat(searchTimes)) / searchBaseCount;
            maxReductionPct = pctReduction(formalSearchMetric.rmsMax, metric.rmsMax);
            p95ReductionPct = pctReduction(formalSearchMetric.rmsP95, metric.rmsP95);
            widthReductionPct = pctReduction(formalSearchMetric.bandWidthP95Median, metric.bandWidthP95Median);
            score = scoreCandidate(keepPct, maxReductionPct, p95ReductionPct, ...
                widthReductionPct, th, segPct, formalThreshold, minKeepPct);
            strategy = strategyText(th, formalThreshold, segPct, segmentMinutes);
            conclusion = conclusionText(keepPct, maxReductionPct, score, pointId, minKeepPct);
            pointRows(end+1, :) = {pointId, searchStride, th, segPct, strategy, searchBaseCount, ...
                keepPct, formalSearchKeepPct - keepPct, metric.rmsMax, metric.rmsP95, ...
                metric.bandWidthP95Median, maxReductionPct, p95ReductionPct, ...
                widthReductionPct, score, conclusion}; %#ok<AGROW>
        end
    end

    pointEval = cell2table(pointRows, 'VariableNames', gridVariableNames());
    selectedIdx = selectCandidate(pointEval, thresholdGrid, segmentPctGrid, formalThreshold, minKeepPct);
    selected = pointEval(selectedIdx, :);
    selectedClean = clipAbs(values, selected.ThresholdAbs);
    if selected.SegmentFilterTopPct > 0
        selectedClean = applyTopRmsSegmentMask(times, selectedClean, segmentEdges, selected.SegmentFilterTopPct);
    end
    selectedMetric = binnedMetric(times, selectedClean, binEdges, binCenters);
    selectedKeepPct = 100 * nnz(isfinite(selectedClean) & ~isnat(times)) / baseCount;
    selectedMaxReductionPct = pctReduction(formalMetric.rmsMax, selectedMetric.rmsMax);
    selectedP95ReductionPct = pctReduction(formalMetric.rmsP95, selectedMetric.rmsP95);
    selectedWidthReductionPct = pctReduction(formalMetric.bandWidthP95Median, selectedMetric.bandWidthP95Median);
    selectedScore = scoreCandidate(selectedKeepPct, selectedMaxReductionPct, ...
        selectedP95ReductionPct, selectedWidthReductionPct, selected.ThresholdAbs, ...
        selected.SegmentFilterTopPct, formalThreshold, minKeepPct);
    selected.BaseFiniteCount = baseCount;
    selected.KeepPct = selectedKeepPct;
    selected.KeepLossFromFormalPct = formalKeepPct - selectedKeepPct;
    selected.DisplayRMS30Max = selectedMetric.rmsMax;
    selected.DisplayRMS30P95 = selectedMetric.rmsP95;
    selected.BandWidthP95Median = selectedMetric.bandWidthP95Median;
    selected.RMS30MaxReductionPct = selectedMaxReductionPct;
    selected.RMS30P95ReductionPct = selectedP95ReductionPct;
    selected.BandWidthReductionPct = selectedWidthReductionPct;
    selected.Score = selectedScore;
    selected.Conclusion = {conclusionText(selectedKeepPct, selectedMaxReductionPct, selectedScore, pointId, minKeepPct)};
    selectedRows(end+1, :) = table2cell(selected); %#ok<AGROW>
    allRows = [allRows; pointRows]; %#ok<AGROW>

    plotPaths{i} = plotPoint(plotDir, pointId, binCenters, selectedMetric, ...
        selected.ThresholdAbs, selected.SegmentFilterTopPct, selected.KeepPct, ...
        selected.RMS30MaxReductionPct, selected.Score, selected.Conclusion{1});
    trendPlotPaths{i} = plotTrendPoint(plotDir, pointId, binCenters, selectedMetric, ...
        selected.ThresholdAbs, selected.SegmentFilterTopPct, selected.KeepPct, ...
        selected.RMS30MaxReductionPct, selected.Score, selected.Conclusion{1});
end

gridEval = cell2table(allRows, 'VariableNames', gridVariableNames());
selectedSummary = cell2table(selectedRows, 'VariableNames', gridVariableNames());
xlsxPath = fullfile(outRoot, 'cable_accel_display_grid_search.xlsx');
csvPath = fullfile(outRoot, 'cable_accel_display_grid_search_selected.csv');
writetable(gridEval, xlsxPath, 'Sheet', 'grid_eval');
writetable(selectedSummary, xlsxPath, 'Sheet', 'selected_summary');
writetable(selectedSummary, csvPath, 'Encoding', 'UTF-8');

boardPath = buildReviewBoard(plotPaths, points, outRoot, 'cable_accel_display_grid_selected_review_board.jpg');
trendBoardPath = buildReviewBoard(trendPlotPaths, points, outRoot, 'cable_accel_display_grid_selected_trend_board.jpg');
markdownPath = writeMarkdown(outRoot, runName, selectedSummary, xlsxPath, csvPath, boardPath, trendBoardPath, minKeepPct);
latestPaths = writeLatest(dataRoot, runName, selectedSummary, xlsxPath, csvPath, boardPath, trendBoardPath, markdownPath, minKeepPct);

result = struct();
result.run_name = runName;
result.output_folder = outRoot;
result.grid_eval = gridEval;
result.selected_summary = selectedSummary;
result.workbook = xlsxPath;
result.csv = csvPath;
result.board = boardPath;
result.trend_board = trendBoardPath;
result.markdown = markdownPath;
result.latest = latestPaths;

fprintf('wrote %s\n', xlsxPath);
fprintf('wrote %s\n', csvPath);
fprintf('review board %s\n', boardPath);
fprintf('trend board %s\n', trendBoardPath);
fprintf('summary markdown %s\n', markdownPath);
fprintf('latest html %s\n', latestPaths.html);
disp(selectedSummary(:, {'PointID','Strategy','KeepPct','RMS30MaxReductionPct','Score','Conclusion'}));
end

function names = gridVariableNames()
names = {'PointID','SearchStride','ThresholdAbs','SegmentFilterTopPct','Strategy', ...
    'BaseFiniteCount','KeepPct','KeepLossFromFormalPct','DisplayRMS30Max', ...
    'DisplayRMS30P95','BandWidthP95Median','RMS30MaxReductionPct', ...
    'RMS30P95ReductionPct','BandWidthReductionPct','Score','Conclusion'};
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

function value = pctReduction(beforeValue, afterValue)
if ~isfinite(beforeValue) || beforeValue <= 0 || ~isfinite(afterValue)
    value = NaN;
else
    value = 100 * (beforeValue - afterValue) / max(beforeValue, eps);
end
end

function score = scoreCandidate(keepPct, maxReductionPct, p95ReductionPct, widthReductionPct, ...
        thresholdAbs, segmentPct, formalThreshold, minKeepPct)
if keepPct < minKeepPct || ~isfinite(maxReductionPct)
    score = -Inf;
    return;
end
score = maxReductionPct;
if isfinite(p95ReductionPct)
    score = score + 0.45 * p95ReductionPct;
end
if isfinite(widthReductionPct)
    score = score + 0.20 * widthReductionPct;
end
score = score - 1.8 * max(0, 95 - keepPct);
score = score - 8.0 * max(0, 93 - keepPct);
score = score - 0.15 * segmentPct;
if thresholdAbs == formalThreshold && segmentPct == 0
    score = score - 2;
end
end

function idx = selectCandidate(pointEval, thresholdGrid, segmentPctGrid, formalThreshold, minKeepPct)
eligible = pointEval.KeepPct >= minKeepPct & isfinite(pointEval.Score);
if any(eligible)
    eligibleIdx = find(eligible);
    [~, bestLocal] = max(pointEval.Score(eligibleIdx));
    idx = eligibleIdx(bestLocal);
    return;
end
idx = find(pointEval.ThresholdAbs == formalThreshold & pointEval.SegmentFilterTopPct == 0, 1);
if isempty(idx)
    idx = numel(thresholdGrid) * numel(segmentPctGrid);
end
end

function text = strategyText(displayThreshold, formalThreshold, segmentFilterPct, segmentMinutes)
parts = {};
if displayThreshold < formalThreshold
    parts{end+1} = sprintf('abs<=%.0f display', displayThreshold); %#ok<AGROW>
else
    parts{end+1} = sprintf('formal abs<=%.0f', formalThreshold); %#ok<AGROW>
end
if segmentFilterPct > 0
    parts{end+1} = sprintf('drop top %.0f%% RMS%d segments', segmentFilterPct, segmentMinutes); %#ok<AGROW>
end
text = strjoin(parts, ' + ');
end

function text = conclusionText(keepPct, maxReductionPct, score, pointId, minKeepPct)
if keepPct < minKeepPct || ~isfinite(score)
    text = 'reject: excessive data loss';
elseif maxReductionPct >= 35 && keepPct >= 93
    text = 'strong display improvement';
elseif maxReductionPct >= 20 && keepPct >= 90
    text = 'moderate display improvement';
elseif any(strcmp(pointId, {'CF-2','CF-8'}))
    text = 'limited improvement; likely original signal quality limitation';
else
    text = 'limited improvement';
end
end

function plotPath = plotPoint(plotDir, pointId, binCenters, metric, displayThreshold, ...
        segmentFilterPct, keepPct, reductionPct, score, conclusion)
fig = figure('Visible', 'off', 'Position', [100 100 1250 700]);
tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile;
hold(ax1, 'on');
fillBand(ax1, binCenters, metric.p05, metric.p95, [0.80 0.88 0.96], 0.45, '5%~95%');
fillBand(ax1, binCenters, metric.p25, metric.p75, [0.38 0.64 0.86], 0.70, '25%~75%');
plot(ax1, binCenters, metric.p50, 'Color', [0 0.18 0.42], 'LineWidth', 1.3, 'DisplayName', 'median');
hold(ax1, 'off');
grid(ax1, 'on');
grid(ax1, 'minor');
ylabel(ax1, 'm/s^2');
title(ax1, sprintf('%s grid selected | abs<=%.0f | segment %.0f%% | keep %.2f%%', ...
    pointId, displayThreshold, segmentFilterPct, keepPct), 'Interpreter', 'none');
legend(ax1, 'Location', 'northeast', 'Box', 'off');
xtickformat(ax1, 'yyyy-MM-dd');

ax2 = nexttile;
plot(ax2, binCenters, metric.rms, 'Color', [0.85 0.33 0.10], 'LineWidth', 1.2);
grid(ax2, 'on');
grid(ax2, 'minor');
ylabel(ax2, 'RMS30 (m/s^2)');
xlabel(ax2, 'time');
title(ax2, sprintf('RMS30 max %.2f | reduction %.1f%% | score %.1f | %s', ...
    metric.rmsMax, reductionPct, score, conclusion), 'Interpreter', 'none');
xtickformat(ax2, 'yyyy-MM-dd');
linkaxes([ax1 ax2], 'x');
xlim(ax1, [binCenters(1), binCenters(end)]);

plotPath = fullfile(plotDir, sprintf('GridSelected_%s.jpg', pointId));
exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
end

function plotPath = plotTrendPoint(plotDir, pointId, binCenters, metric, displayThreshold, ...
        segmentFilterPct, keepPct, reductionPct, score, conclusion)
fig = figure('Visible', 'off', 'Position', [100 100 1250 520]);
ax = axes(fig);
hold(ax, 'on');
fillBand(ax, binCenters, metric.p05, metric.p95, [0.72 0.82 0.92], 0.22, '5%~95%');
fillBand(ax, binCenters, metric.p25, metric.p75, [0.22 0.57 0.78], 0.55, '25%~75%');
plot(ax, binCenters, metric.p50, 'Color', [0 0.17 0.38], 'LineWidth', 1.5, 'DisplayName', 'median');
hold(ax, 'off');
grid(ax, 'on');
grid(ax, 'minor');
ylabel(ax, 'm/s^2');
xlabel(ax, 'time');
title(ax, sprintf('%s trend selected | abs<=%.0f | segment %.0f%% | keep %.2f%% | down %.1f%% | score %.1f | %s', ...
    pointId, displayThreshold, segmentFilterPct, keepPct, reductionPct, score, conclusion), 'Interpreter', 'none');
legend(ax, 'Location', 'northeast', 'Box', 'off');
xtickformat(ax, 'yyyy-MM-dd');
xlim(ax, [binCenters(1), binCenters(end)]);
setTrendYLimits(ax, metric);

plotPath = fullfile(plotDir, sprintf('GridSelectedTrend_%s.jpg', pointId));
exportgraphics(fig, plotPath, 'Resolution', 150);
close(fig);
end

function setTrendYLimits(ax, metric)
core = [metric.p25(:); metric.p50(:); metric.p75(:)];
core = core(isfinite(core));
if isempty(core)
    return;
end
lo = prctile(core, 1);
hi = prctile(core, 99);
if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
    lo = min(core);
    hi = max(core);
end
if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
    center = median(core, 'omitnan');
    lo = center - 1;
    hi = center + 1;
end
pad = max((hi - lo) * 0.18, 0.5);
ylim(ax, [lo - pad, hi + pad]);
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

function boardPath = buildReviewBoard(plotPaths, points, outRoot, fileName)
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
boardPath = fullfile(outRoot, fileName);
exportgraphics(fig, boardPath, 'Resolution', 150);
close(fig);
end

function markdownPath = writeMarkdown(outRoot, runName, selectedSummary, xlsxPath, csvPath, boardPath, trendBoardPath, minKeepPct)
markdownPath = fullfile(outRoot, 'cable_accel_display_grid_search.md');
fid = fopen(markdownPath, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Zhishan Cable Acceleration Display Grid Search\n\n');
fprintf(fid, '- Run: `%s`\n', runName);
fprintf(fid, '- Workbook: `%s`\n', xlsxPath);
fprintf(fid, '- CSV: `%s`\n', csvPath);
fprintf(fid, '- Detail board: `%s`\n', boardPath);
fprintf(fid, '- Trend board: `%s`\n', trendBoardPath);
fprintf(fid, '- Minimum keep target: `%.1f%%`\n\n', minKeepPct);
fprintf(fid, 'Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`. This search is display-only.\n\n');
fprintf(fid, '| Point | Strategy | Keep %% | RMS30 max | RMS30 max reduction %% | Score | Conclusion |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---|\n');
for i = 1:height(selectedSummary)
    fprintf(fid, '| %s | %s | %.3f | %.3f | %.1f | %.1f | %s |\n', ...
        selectedSummary.PointID{i}, selectedSummary.Strategy{i}, selectedSummary.KeepPct(i), ...
        selectedSummary.DisplayRMS30Max(i), selectedSummary.RMS30MaxReductionPct(i), ...
        selectedSummary.Score(i), selectedSummary.Conclusion{i});
end
end

function latestPaths = writeLatest(dataRoot, runName, selectedSummary, xlsxPath, csvPath, boardPath, trendBoardPath, markdownPath, minKeepPct)
runLogs = fullfile(dataRoot, 'run_logs');
latestPaths = struct( ...
    'json', fullfile(runLogs, 'cable_accel_display_grid_search_latest.json'), ...
    'markdown', fullfile(runLogs, 'cable_accel_display_grid_search_latest.md'), ...
    'html', fullfile(runLogs, 'cable_accel_display_grid_search_latest.html'));

pointer = struct();
pointer.generated_at = datestr(now, 'yyyy-mm-dd HH:MM:SS');
pointer.run_name = runName;
pointer.output_folder = relPath(fileparts(xlsxPath), dataRoot);
pointer.summary = relPath(markdownPath, dataRoot);
pointer.workbook = relPath(xlsxPath, dataRoot);
pointer.csv = relPath(csvPath, dataRoot);
pointer.detail_board = relPath(boardPath, dataRoot);
pointer.trend_board = relPath(trendBoardPath, dataRoot);
pointer.review_html = relPath(latestPaths.html, dataRoot);
pointer.min_keep_pct = minKeepPct;
pointer.formal_policy = 'Formal spectrum/force calculation remains daily_median + [-100,100] m/s^2.';
pointer.display_policy = 'Display-only grid search over threshold and top-RMS segment removal.';

fid = fopen(latestPaths.json, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(pointer));
clear cleaner;

fid = fopen(latestPaths.markdown, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '# Latest Zhishan Cable Acceleration Display Grid Search\n\n');
fprintf(fid, '- Generated: %s\n', pointer.generated_at);
fprintf(fid, '- Run: `%s`\n', pointer.run_name);
fprintf(fid, '- Summary: `%s`\n', pointer.summary);
fprintf(fid, '- Workbook: `%s`\n', pointer.workbook);
fprintf(fid, '- Detail board: `%s`\n', pointer.detail_board);
fprintf(fid, '- Trend board: `%s`\n', pointer.trend_board);
fprintf(fid, '- Review HTML: `%s`\n', pointer.review_html);
fprintf(fid, '- Formal policy: %s\n', pointer.formal_policy);
fprintf(fid, '- Display policy: %s\n\n', pointer.display_policy);
fprintf(fid, '| Point | Strategy | Keep %% | RMS30 max | RMS30 max reduction %% | Score | Conclusion |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---|\n');
for i = 1:height(selectedSummary)
    fprintf(fid, '| %s | %s | %.3f | %.3f | %.1f | %.1f | %s |\n', ...
        selectedSummary.PointID{i}, selectedSummary.Strategy{i}, selectedSummary.KeepPct(i), ...
        selectedSummary.DisplayRMS30Max(i), selectedSummary.RMS30MaxReductionPct(i), ...
        selectedSummary.Score(i), selectedSummary.Conclusion{i});
end
clear cleaner;

writeLatestHtml(latestPaths.html, pointer, selectedSummary);
end

function writeLatestHtml(path, pointer, selectedSummary)
fid = fopen(path, 'w', 'n', 'UTF-8');
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n');
fprintf(fid, '<title>Zhishan Cable Acceleration Display Grid Search</title>\n');
fprintf(fid, '<style>');
fprintf(fid, 'body{font-family:Arial,"Microsoft YaHei",sans-serif;margin:24px;color:#172033;background:#f7f8fa;}');
fprintf(fid, 'h1{font-size:24px;margin:0 0 10px;} h2{font-size:18px;margin:28px 0 12px;}');
fprintf(fid, '.meta,.note{line-height:1.7;color:#4b5563;} .note{background:white;border-left:4px solid #2f6fed;padding:10px 12px;margin:14px 0 20px;}');
fprintf(fid, 'table{border-collapse:collapse;background:white;width:100%%;margin:12px 0 22px;}');
fprintf(fid, 'th,td{border:1px solid #d7dce2;padding:7px 9px;text-align:left;font-size:13px;} th{background:#eef2f6;} .num{text-align:right;font-variant-numeric:tabular-nums;}');
fprintf(fid, '.quality{background:#fff8e1;} .figure{background:white;border:1px solid #d7dce2;padding:12px;margin:14px 0 24px;} img{max-width:100%%;height:auto;display:block;margin:auto;}');
fprintf(fid, '.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:14px;} a{color:#075da8;text-decoration:none;} a:hover{text-decoration:underline;}');
fprintf(fid, '</style>\n</head>\n<body>\n');
fprintf(fid, '<h1>&#33437;&#23665;&#22823;&#26725;&#32034;&#21147;&#21152;&#36895;&#24230;&#23637;&#31034;&#32593;&#26684;&#25628;&#32034; / Display Grid Search</h1>\n');
fprintf(fid, '<div class="meta">Generated: %s<br>Run: <code>%s</code><br>Summary: <a href="%s">%s</a><br>Workbook: <a href="%s">%s</a></div>\n', ...
    htmlText(pointer.generated_at), htmlText(pointer.run_name), htmlPath(pointer.summary), htmlText(pointer.summary), ...
    htmlPath(pointer.workbook), htmlText(pointer.workbook));
fprintf(fid, '<div class="note">&#27491;&#24335;&#39057;&#35889;/&#32034;&#21147;&#35745;&#31639;&#19981;&#21464;: <code>daily_median + [-100,100] m/s^2</code>. &#26412;&#39029;&#20165;&#29992;&#20110;&#25253;&#21578;/&#23457;&#22270;&#23637;&#31034;&#25628;&#32034;&#12290;</div>\n');

fprintf(fid, '<h2>&#31574;&#30053;&#27719;&#24635; / Selected Strategy</h2>\n<table>\n');
fprintf(fid, '<tr><th>&#27979;&#28857;</th><th>&#23637;&#31034;&#31574;&#30053;</th><th>&#20445;&#30041;&#29575;</th><th>RMS30 &#26368;&#22823;&#20540;</th><th>RMS30 &#38477;&#20302;</th><th>Score</th><th>&#32467;&#35770;</th></tr>\n');
for i = 1:height(selectedSummary)
    cls = '';
    if contains(selectedSummary.Conclusion{i}, 'quality limitation')
        cls = ' class="quality"';
    end
    fprintf(fid, '<tr%s><td>%s</td><td>%s</td><td class="num">%.3f%%</td><td class="num">%.3f</td><td class="num">%.1f%%</td><td class="num">%.1f</td><td>%s</td></tr>\n', ...
        cls, htmlText(selectedSummary.PointID{i}), htmlText(selectedSummary.Strategy{i}), ...
        selectedSummary.KeepPct(i), selectedSummary.DisplayRMS30Max(i), ...
        selectedSummary.RMS30MaxReductionPct(i), selectedSummary.Score(i), ...
        htmlText(selectedSummary.Conclusion{i}));
end
fprintf(fid, '</table>\n');

fprintf(fid, '<h2>&#35814;&#32454;&#24635;&#35272;&#22270; / Detail Board</h2>\n<div class="figure"><img src="%s" alt="detail board"></div>\n', htmlPath(pointer.detail_board));
fprintf(fid, '<h2>&#36235;&#21183;&#24635;&#35272;&#22270; / Trend Board</h2>\n<div class="figure"><img src="%s" alt="trend board"></div>\n', htmlPath(pointer.trend_board));
fprintf(fid, '<h2>&#21333;&#28857;&#22270; / Per-Point Figures</h2>\n<div class="grid">\n');
for i = 1:height(selectedSummary)
    rel = fullfile(pointer.output_folder, 'plots', sprintf('GridSelected_%s.jpg', selectedSummary.PointID{i}));
    fprintf(fid, '<div class="figure"><h2>%s</h2><img src="%s" alt="%s"></div>\n', ...
        htmlText(selectedSummary.PointID{i}), htmlPath(rel), htmlText(selectedSummary.PointID{i}));
end
fprintf(fid, '</div>\n<h2>&#21333;&#28857;&#36235;&#21183;&#22270; / Per-Point Trend Figures</h2>\n<div class="grid">\n');
for i = 1:height(selectedSummary)
    rel = fullfile(pointer.output_folder, 'plots', sprintf('GridSelectedTrend_%s.jpg', selectedSummary.PointID{i}));
    fprintf(fid, '<div class="figure"><h2>%s trend</h2><img src="%s" alt="%s trend"></div>\n', ...
        htmlText(selectedSummary.PointID{i}), htmlPath(rel), htmlText(selectedSummary.PointID{i}));
end
fprintf(fid, '</div>\n</body>\n</html>\n');
end

function out = htmlPath(pathText)
out = char(pathText);
prefix = ['run_logs' filesep];
if startsWith(out, prefix)
    out = out(numel(prefix)+1:end);
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
